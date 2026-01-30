import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Frame decimation exporter that writes every Nth frame for ~10x faster timelapse exports
@MainActor
public final class FrameDecimationExporter {

    // MARK: - Public Types

    /// Progress callback with fraction complete (0.0-1.0)
    public typealias ProgressCallback = @MainActor @Sendable (Double) -> Void

    // MARK: - Private Properties

    private var assetReader: AVAssetReader?
    private var assetWriter: AVAssetWriter?
    private var cancelled = false

    public init() {}

    // MARK: - Public Methods

    /// Exports a timelapse video using frame decimation
    /// - Parameters:
    ///   - asset: Source video asset
    ///   - outputURL: Destination URL for exported file
    ///   - speedMultiplier: Speed factor (e.g., 10x means keep every 10th frame)
    ///   - timeRange: Optional time range for trimming (nil = full duration)
    ///   - settings: Export configuration (quality, resolution, framerate)
    ///   - progress: Optional progress callback
    /// - Throws: QuickMotionError on failure
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
            throw QuickMotionError.exportFailed(reason: "No video track found in source")
        }

        // Load track properties
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)

        // Determine effective time range
        let effectiveTimeRange: CMTimeRange
        if let timeRange = timeRange {
            effectiveTimeRange = timeRange
        } else {
            let duration = try await asset.load(.duration)
            effectiveTimeRange = CMTimeRange(start: .zero, duration: duration)
        }

        // Calculate frame decimation interval
        let frameInterval = max(1, Int(speedMultiplier.rounded()))

        // Determine output framerate (match source or cap at 30fps)
        let sourceFrameRate = nominalFrameRate > 0 ? nominalFrameRate : 30.0
        let outputFrameRate = min(sourceFrameRate, 30.0)
        let outputFrameDuration = CMTime(value: 1, timescale: CMTimeScale(outputFrameRate))

        // Setup reader
        let reader = try AVAssetReader(asset: asset)

        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: sourceVideoTrack, outputSettings: readerOutputSettings)
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            throw QuickMotionError.exportFailed(reason: "Failed to add reader output")
        }
        reader.add(readerOutput)
        reader.timeRange = effectiveTimeRange

        // Setup writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: settings.outputFileType)

        // Configure video settings based on quality
        let videoCodec: AVVideoCodecType
        switch settings.quality {
        case .fast:
            videoCodec = .hevc
        case .quality:
            videoCodec = .proRes422
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: Int(naturalSize.width),
            AVVideoHeightKey: Int(naturalSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: calculateBitrate(for: naturalSize, quality: settings.quality),
                AVVideoExpectedSourceFrameRateKey: outputFrameRate,
                AVVideoProfileLevelKey: videoCodec == .hevc ? kVTProfileLevel_HEVC_Main_AutoLevel as String : nil
            ].compactMapValues { $0 }
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = preferredTransform

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: Int(naturalSize.width),
                kCVPixelBufferHeightKey as String: Int(naturalSize.height)
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw QuickMotionError.exportFailed(reason: "Failed to add writer input")
        }
        writer.add(writerInput)

        // Start reading and writing
        guard writer.startWriting() else {
            throw QuickMotionError.exportFailed(reason: "Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")")
        }

        writer.startSession(atSourceTime: CMTime.zero)

        guard reader.startReading() else {
            throw QuickMotionError.exportFailed(reason: "Failed to start reading: \(reader.error?.localizedDescription ?? "unknown")")
        }

        // Store for cleanup
        self.assetReader = reader
        self.assetWriter = writer

        // Estimate total frames for progress
        let sourceDuration = CMTimeGetSeconds(effectiveTimeRange.duration)
        let sourceFrameCount = Int(sourceDuration * Double(sourceFrameRate))
        let expectedOutputFrames = sourceFrameCount / frameInterval

        // Process frames
        var frameIndex = 0
        var outputFrameIndex = 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.quickmotion.frameDecimation")) {
                var shouldContinue = true

                while writerInput.isReadyForMoreMediaData && shouldContinue {
                    // Check for cancellation
                    if self.cancelled {
                        reader.cancelReading()
                        writer.cancelWriting()
                        continuation.resume(throwing: QuickMotionError.exportFailed(reason: "Export cancelled"))
                        return
                    }

                    // Read next sample
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        // No more samples - finish writing
                        writerInput.markAsFinished()

                        Task { @MainActor in
                            await writer.finishWriting()

                            switch writer.status {
                            case .completed:
                                continuation.resume()
                            case .failed:
                                let errorMsg = writer.error?.localizedDescription ?? "Unknown error"
                                continuation.resume(throwing: QuickMotionError.exportFailed(reason: errorMsg))
                            case .cancelled:
                                continuation.resume(throwing: QuickMotionError.exportFailed(reason: "Export cancelled"))
                            default:
                                continuation.resume(throwing: QuickMotionError.exportFailed(reason: "Unexpected writer status: \(writer.status.rawValue)"))
                            }
                        }

                        shouldContinue = false
                        break
                    }

                    // Keep every Nth frame
                    if frameIndex % frameInterval == 0 {
                        // Extract pixel buffer
                        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                            frameIndex += 1
                            continue
                        }

                        // Calculate remapped presentation time
                        let outputPresentationTime = CMTimeMultiply(outputFrameDuration, multiplier: Int32(outputFrameIndex))

                        // Write frame with remapped timestamp
                        if !pixelBufferAdaptor.append(imageBuffer, withPresentationTime: outputPresentationTime) {
                            reader.cancelReading()
                            writer.cancelWriting()
                            let errorMsg = writer.error?.localizedDescription ?? "Failed to append pixel buffer"
                            continuation.resume(throwing: QuickMotionError.exportFailed(reason: errorMsg))
                            shouldContinue = false
                            break
                        }

                        outputFrameIndex += 1

                        // Report progress
                        if let progress = progress, expectedOutputFrames > 0 {
                            let fractionComplete = Double(outputFrameIndex) / Double(expectedOutputFrames)
                            Task { @MainActor in
                                progress(min(fractionComplete, 1.0))
                            }
                        }
                    }

                    frameIndex += 1
                }
            }
        }

        // Cleanup
        self.assetReader = nil
        self.assetWriter = nil
    }

    /// Cancels an in-progress export
    public func cancel() {
        cancelled = true
    }

    // MARK: - Private Methods

    /// Calculates appropriate bitrate based on resolution and quality
    private func calculateBitrate(for size: CGSize, quality: ExportQuality) -> Int {
        let pixels = size.width * size.height

        switch quality {
        case .fast:
            // HEVC: ~0.1 bits per pixel for good quality
            return Int(pixels * 0.1 * 30.0)
        case .quality:
            // ProRes is VBR and doesn't use bitrate hint in the same way
            // Return a nominal value
            return Int(pixels * 0.5 * 30.0)
        }
    }
}
