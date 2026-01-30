import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

/// High-performance timelapse exporter using AVAssetReader/Writer with frame skipping
///
/// Key performance insight: This reads frames sequentially (hardware decode is fast)
/// but only WRITES every Nth frame to the output. At 16x speed, we only encode
/// 1/16th of the frames, making export ~16x faster than full re-encode.
///
/// Comparison with other approaches:
/// - AVAssetExportSession + scaleTimeRange: Encodes ALL frames (slow for high speeds)
/// - AVAssetImageGenerator: Software decode (extremely slow for 6K)
/// - This approach: Hardware decode all, hardware encode only selected frames (fast)
public final class SampleBufferExporter: @unchecked Sendable {

    // MARK: - Public Types

    public typealias ProgressCallback = @MainActor @Sendable (Double) -> Void

    // MARK: - Private Properties

    private var assetReader: AVAssetReader?
    private var assetWriter: AVAssetWriter?
    private let cancelledLock = NSLock()
    private var _cancelled = false

    private var cancelled: Bool {
        get {
            cancelledLock.lock()
            defer { cancelledLock.unlock() }
            return _cancelled
        }
        set {
            cancelledLock.lock()
            _cancelled = newValue
            cancelledLock.unlock()
        }
    }

    public init() {}

    // MARK: - Public Methods

    /// Exports a timelapse video by reading all frames but only writing every Nth frame
    /// - Parameters:
    ///   - asset: Source video asset
    ///   - outputURL: Destination URL
    ///   - speedMultiplier: Speed factor (e.g., 16x = keep every 16th frame)
    ///   - timeRange: Optional trim range
    ///   - settings: Export configuration
    ///   - progress: Progress callback
    @MainActor
    public func export(
        asset: AVAsset,
        to outputURL: URL,
        speedMultiplier: Double,
        timeRange: CMTimeRange? = nil,
        settings: ExportSettings,
        progress: ProgressCallback? = nil
    ) async throws {
        cancelled = false

        // Remove existing output file
        try? FileManager.default.removeItem(at: outputURL)

        // Get source video track
        let sourceTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = sourceTracks.first else {
            throw QuickMotionError.exportFailed(reason: "No video track found")
        }

        // Load track properties
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)

        // Calculate output dimensions respecting rotation
        let outputSize = calculateOutputSize(naturalSize: naturalSize, transform: preferredTransform)

        // Determine time range
        let effectiveTimeRange = timeRange ?? CMTimeRange(start: .zero, duration: duration)

        // Calculate frame skip interval
        // At 16x speed with 25fps source: skip = 16 (keep every 16th frame)
        let frameSkip = max(1, Int(round(speedMultiplier)))
        let sourceFrameRate = nominalFrameRate > 0 ? nominalFrameRate : 30.0
        let outputFrameRate: Float = min(sourceFrameRate, 30.0)

        // Estimate total frames for progress
        let totalSourceFrames = Int(CMTimeGetSeconds(effectiveTimeRange.duration) * Double(sourceFrameRate))
        let estimatedOutputFrames = totalSourceFrames / frameSkip

        // Setup reader
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = effectiveTimeRange

        // Reader output - decode to CVPixelBuffer for writing
        // Using recommended pixel format for hardware acceleration
        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: sourceVideoTrack, outputSettings: readerOutputSettings)
        readerOutput.alwaysCopiesSampleData = false // Performance optimization

        guard reader.canAdd(readerOutput) else {
            throw QuickMotionError.exportFailed(reason: "Cannot add reader output")
        }
        reader.add(readerOutput)
        self.assetReader = reader

        // Setup writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: settings.outputFileType)

        // Video encoding settings
        let videoCodec: AVVideoCodecType
        switch settings.quality {
        case .fast:
            videoCodec = .hevc
        case .quality:
            videoCodec = .proRes422
        }

        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: calculateBitrate(for: outputSize, quality: settings.quality),
            AVVideoExpectedSourceFrameRateKey: outputFrameRate
        ]

        // Enable hardware acceleration for HEVC
        if videoCodec == .hevc {
            compressionProperties[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = preferredTransform

        guard writer.canAdd(writerInput) else {
            throw QuickMotionError.exportFailed(reason: "Cannot add writer input")
        }
        writer.add(writerInput)
        self.assetWriter = writer

        // Start reading and writing
        guard reader.startReading() else {
            throw QuickMotionError.exportFailed(reason: "Failed to start reading: \(reader.error?.localizedDescription ?? "unknown")")
        }

        guard writer.startWriting() else {
            throw QuickMotionError.exportFailed(reason: "Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)

        // Output frame timing
        let outputFrameDuration = CMTime(value: 1, timescale: CMTimeScale(outputFrameRate))

        // Capture for background task
        let capturedReader = reader
        let capturedWriter = writer
        let capturedWriterInput = writerInput
        let capturedReaderOutput = readerOutput
        let capturedFrameSkip = frameSkip
        let capturedOutputFrameDuration = outputFrameDuration
        let capturedEstimatedOutputFrames = estimatedOutputFrames

        // Process on background thread
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var frameIndex = 0
                var framesWritten = 0

                while let sampleBuffer = capturedReaderOutput.copyNextSampleBuffer() {
                    // Check cancellation
                    guard let self = self, !self.cancelled else {
                        capturedReader.cancelReading()
                        capturedWriter.cancelWriting()
                        continuation.resume(throwing: QuickMotionError.exportFailed(reason: "Export cancelled"))
                        return
                    }

                    // Only write every Nth frame
                    if frameIndex % capturedFrameSkip == 0 {
                        // Wait for writer to be ready
                        while !capturedWriterInput.isReadyForMoreMediaData {
                            if self.cancelled {
                                capturedReader.cancelReading()
                                capturedWriter.cancelWriting()
                                continuation.resume(throwing: QuickMotionError.exportFailed(reason: "Export cancelled"))
                                return
                            }
                            Thread.sleep(forTimeInterval: 0.001)
                        }

                        // Create sample buffer with new timing
                        let outputPresentationTime = CMTimeMultiply(capturedOutputFrameDuration, multiplier: Int32(framesWritten))

                        var timingInfo = CMSampleTimingInfo(
                            duration: capturedOutputFrameDuration,
                            presentationTimeStamp: outputPresentationTime,
                            decodeTimeStamp: .invalid
                        )

                        var newSampleBuffer: CMSampleBuffer?
                        let status = CMSampleBufferCreateCopyWithNewTiming(
                            allocator: kCFAllocatorDefault,
                            sampleBuffer: sampleBuffer,
                            sampleTimingEntryCount: 1,
                            sampleTimingArray: &timingInfo,
                            sampleBufferOut: &newSampleBuffer
                        )

                        if status == noErr, let newBuffer = newSampleBuffer {
                            if !capturedWriterInput.append(newBuffer) {
                                let error = capturedWriter.error?.localizedDescription ?? "Failed to append sample buffer"
                                continuation.resume(throwing: QuickMotionError.exportFailed(reason: error))
                                return
                            }
                            framesWritten += 1

                            // Report progress
                            if let progress = progress {
                                let fractionComplete = min(1.0, Double(framesWritten) / Double(max(1, capturedEstimatedOutputFrames)))
                                Task { @MainActor in
                                    progress(fractionComplete)
                                }
                            }
                        }
                    }

                    frameIndex += 1
                }

                // Check reader status
                if capturedReader.status == .failed {
                    let error = capturedReader.error?.localizedDescription ?? "Reading failed"
                    continuation.resume(throwing: QuickMotionError.exportFailed(reason: error))
                    return
                }

                continuation.resume()
            }
        }

        // Finish writing
        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw QuickMotionError.exportFailed(reason: writer.error?.localizedDescription ?? "Writing failed")
        }

        // Cleanup
        self.assetReader = nil
        self.assetWriter = nil
    }

    /// Cancels the export
    public func cancel() {
        cancelled = true
        assetReader?.cancelReading()
        assetWriter?.cancelWriting()
    }

    // MARK: - Private Methods

    private func calculateOutputSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let isRotated = abs(transform.b) == 1.0 && abs(transform.c) == 1.0
        if isRotated {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        }
        return naturalSize
    }

    private func calculateBitrate(for size: CGSize, quality: ExportQuality) -> Int {
        let pixels = size.width * size.height

        switch quality {
        case .fast:
            // HEVC: ~0.15 bits per pixel for high quality
            return Int(pixels * 0.15 * 30.0)
        case .quality:
            // ProRes doesn't really use bitrate hint
            return Int(pixels * 0.5 * 30.0)
        }
    }
}
