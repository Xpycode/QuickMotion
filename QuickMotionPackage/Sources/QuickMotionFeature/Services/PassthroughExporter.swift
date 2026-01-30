import AVFoundation
import CoreMedia
import Foundation

/// Ultra-fast timelapse exporter using passthrough mode (no decode/encode)
///
/// This is the fastest possible approach:
/// - Reads COMPRESSED samples directly (no decoding)
/// - Writes only keyframes (I-frames) which are independently decodable
/// - No re-encoding - just remuxing compressed data with new timestamps
///
/// Limitations:
/// - Output framerate depends on source keyframe interval (typically 1-2 sec)
/// - Only works with QuickTime .mov output (not .mp4)
/// - Quality matches source exactly (no re-compression)
///
/// For a 93-min video at 16x, export takes seconds instead of minutes.
public final class PassthroughExporter: @unchecked Sendable {

    public typealias ProgressCallback = @MainActor @Sendable (Double) -> Void

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

    /// Exports timelapse by copying only keyframes (no decode/encode)
    @MainActor
    public func export(
        asset: AVAsset,
        to outputURL: URL,
        speedMultiplier: Double,
        timeRange: CMTimeRange? = nil,
        progress: ProgressCallback? = nil
    ) async throws {
        cancelled = false

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        // Get source track
        let sourceTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = sourceTracks.first else {
            throw QuickMotionError.exportFailed(reason: "No video track found")
        }

        let duration = try await asset.load(.duration)
        let effectiveTimeRange = timeRange ?? CMTimeRange(start: .zero, duration: duration)

        // Setup reader - nil outputSettings = passthrough (compressed samples)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = effectiveTimeRange

        let readerOutput = AVAssetReaderTrackOutput(track: sourceVideoTrack, outputSettings: nil)
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            throw QuickMotionError.exportFailed(reason: "Cannot add reader output")
        }
        reader.add(readerOutput)
        self.assetReader = reader

        // Setup writer - must be .mov for passthrough, nil outputSettings
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Get source format description for passthrough
        let formatDescriptions = try await sourceVideoTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            throw QuickMotionError.exportFailed(reason: "No format description")
        }

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
        writerInput.expectsMediaDataInRealTime = false

        // Preserve transform
        let transform = try await sourceVideoTrack.load(.preferredTransform)
        writerInput.transform = transform

        guard writer.canAdd(writerInput) else {
            throw QuickMotionError.exportFailed(reason: "Cannot add writer input")
        }
        writer.add(writerInput)
        self.assetWriter = writer

        // Start
        guard reader.startReading() else {
            throw QuickMotionError.exportFailed(reason: "Failed to start reading")
        }

        guard writer.startWriting() else {
            throw QuickMotionError.exportFailed(reason: "Failed to start writing")
        }
        writer.startSession(atSourceTime: .zero)

        // Calculate how many samples to skip between keyframes we keep
        // At 16x speed, we want roughly 1/16th the duration
        // Keyframes are typically every 1-2 seconds, so we may need to skip some
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)
        let outputFrameRate: Float = min(nominalFrameRate, 30.0)
        let outputFrameDuration = CMTime(value: 1, timescale: CMTimeScale(outputFrameRate))

        // For progress estimation
        let totalDuration = CMTimeGetSeconds(effectiveTimeRange.duration)

        // Process on background
        let capturedReader = reader
        let capturedWriter = writer
        let capturedReaderOutput = readerOutput
        let capturedWriterInput = writerInput

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var framesWritten = 0
                var lastKeyframePTS: CMTime?
                let minKeyframeInterval = CMTime(seconds: speedMultiplier / Double(outputFrameRate), preferredTimescale: 600)

                var totalSamplesRead = 0
                var keyframesFound = 0

                while let sampleBuffer = capturedReaderOutput.copyNextSampleBuffer() {
                    totalSamplesRead += 1

                    guard let self = self, !self.cancelled else {
                        capturedReader.cancelReading()
                        capturedWriter.cancelWriting()
                        continuation.resume(throwing: QuickMotionError.exportFailed(reason: "Cancelled"))
                        return
                    }

                    // Check if this is a keyframe
                    let isKF = self.isKeyframe(sampleBuffer)
                    if isKF { keyframesFound += 1 }

                    // Log periodically
                    if totalSamplesRead % 10000 == 0 {
                        print("[Passthrough] Read \(totalSamplesRead) samples, found \(keyframesFound) keyframes")
                    }

                    guard isKF else {
                        continue // Skip non-keyframes
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    // Skip keyframes that are too close together (for high speed)
                    if let lastPTS = lastKeyframePTS {
                        let interval = CMTimeSubtract(pts, lastPTS)
                        if CMTimeCompare(interval, minKeyframeInterval) < 0 {
                            continue
                        }
                    }
                    lastKeyframePTS = pts

                    // Wait for writer
                    while !capturedWriterInput.isReadyForMoreMediaData {
                        if self.cancelled {
                            capturedReader.cancelReading()
                            capturedWriter.cancelWriting()
                            continuation.resume(throwing: QuickMotionError.exportFailed(reason: "Cancelled"))
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.001)
                    }

                    // Create new timing for output
                    let outputPTS = CMTimeMultiplyByFloat64(
                        CMTime(value: Int64(framesWritten), timescale: CMTimeScale(outputFrameRate)),
                        multiplier: 1.0
                    )

                    var timingInfo = CMSampleTimingInfo(
                        duration: outputFrameDuration,
                        presentationTimeStamp: outputPTS,
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
                            let error = capturedWriter.error?.localizedDescription ?? "Write failed"
                            continuation.resume(throwing: QuickMotionError.exportFailed(reason: error))
                            return
                        }
                        framesWritten += 1

                        // Progress
                        if let progress = progress {
                            let currentTime = CMTimeGetSeconds(pts)
                            let fraction = min(1.0, currentTime / totalDuration)
                            Task { @MainActor in
                                progress(fraction)
                            }
                        }
                    }
                }

                print("[Passthrough] DONE: Read \(totalSamplesRead) total samples, found \(keyframesFound) keyframes, wrote \(framesWritten) frames")

                if capturedReader.status == .failed {
                    continuation.resume(throwing: QuickMotionError.exportFailed(reason: capturedReader.error?.localizedDescription ?? "Read failed"))
                    return
                }

                continuation.resume()
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw QuickMotionError.exportFailed(reason: writer.error?.localizedDescription ?? "Write failed")
        }

        self.assetReader = nil
        self.assetWriter = nil
    }

    public func cancel() {
        cancelled = true
        assetReader?.cancelReading()
        assetWriter?.cancelWriting()
    }

    // MARK: - Private

    /// Checks if a sample buffer contains a keyframe (sync sample)
    private func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        // Get sample attachments
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let attachment = attachments.first else {
            // No attachments = assume keyframe
            return true
        }

        // kCMSampleAttachmentKey_NotSync indicates NOT a keyframe
        // If this key is absent or false, it's a keyframe
        if let notSync = attachment[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }

        // If DependsOnOthers is false, it's a keyframe
        if let dependsOnOthers = attachment[kCMSampleAttachmentKey_DependsOnOthers] as? Bool {
            return !dependsOnOthers
        }

        return true
    }
}
