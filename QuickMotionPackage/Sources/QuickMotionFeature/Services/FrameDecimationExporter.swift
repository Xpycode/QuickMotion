import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Frame decimation exporter that seeks to specific frames for fast timelapse exports
/// Uses AVAssetImageGenerator for efficient seeking (skips intermediate frames)
@MainActor
public final class FrameDecimationExporter {

    // MARK: - Public Types

    /// Progress callback with fraction complete (0.0-1.0)
    public typealias ProgressCallback = @MainActor @Sendable (Double) -> Void

    // MARK: - Private Properties

    private var imageGenerator: AVAssetImageGenerator?
    private var assetWriter: AVAssetWriter?
    private var cancelled = false

    public init() {}

    // MARK: - Public Methods

    /// Exports a timelapse video using frame seeking (NOT sequential reading)
    /// - Parameters:
    ///   - asset: Source video asset
    ///   - outputURL: Destination URL for exported file
    ///   - speedMultiplier: Speed factor (e.g., 32x means sample every 32nd frame time)
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

        // Get source video track for properties
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
            effectiveTimeRange = CMTimeRange(start: CMTime.zero, duration: duration)
        }

        // Calculate frame times to extract
        let sourceFrameRate = nominalFrameRate > 0 ? nominalFrameRate : 30.0
        let outputFrameRate: Float = min(sourceFrameRate, 30.0)

        // Time between frames we want to sample (in source video time)
        // At 32x speed with 25fps source: sample every 32/25 = 1.28 seconds
        let sampleInterval = Double(speedMultiplier) / Double(sourceFrameRate)

        // Generate list of times to extract
        var frameTimes: [CMTime] = []
        let startSeconds = CMTimeGetSeconds(effectiveTimeRange.start)
        let endSeconds = CMTimeGetSeconds(CMTimeAdd(effectiveTimeRange.start, effectiveTimeRange.duration))

        var currentTime = startSeconds
        while currentTime < endSeconds {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            frameTimes.append(time)
            currentTime += sampleInterval
        }

        let totalFrames = frameTimes.count
        guard totalFrames > 0 else {
            throw QuickMotionError.exportFailed(reason: "No frames to export")
        }

        // Setup image generator for frame extraction
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        // Request full resolution
        generator.maximumSize = CGSize(width: naturalSize.width, height: naturalSize.height)
        self.imageGenerator = generator

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

        // Calculate output dimensions respecting rotation
        let outputSize = calculateOutputSize(naturalSize: naturalSize, transform: preferredTransform)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: calculateBitrate(for: outputSize, quality: settings.quality),
                AVVideoExpectedSourceFrameRateKey: outputFrameRate,
                AVVideoProfileLevelKey: videoCodec == .hevc ? kVTProfileLevel_HEVC_Main_AutoLevel as String : nil
            ].compactMapValues { $0 }
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw QuickMotionError.exportFailed(reason: "Failed to add writer input")
        }
        writer.add(writerInput)
        self.assetWriter = writer

        // Start writing
        guard writer.startWriting() else {
            throw QuickMotionError.exportFailed(reason: "Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: CMTime.zero)

        // Output frame duration
        let outputFrameDuration = CMTime(value: 1, timescale: CMTimeScale(outputFrameRate))

        // Process frames using seeking (not sequential reading!)
        var framesWritten = 0

        for (index, requestedTime) in frameTimes.enumerated() {
            // Check for cancellation
            if cancelled {
                generator.cancelAllCGImageGeneration()
                writer.cancelWriting()
                throw QuickMotionError.exportFailed(reason: "Export cancelled")
            }

            do {
                // Generate image at this specific time (seeks efficiently)
                // Use copyCGImage which is synchronous but efficient for seeking
                var actualTime = CMTime.zero
                let cgImage = try generator.copyCGImage(at: requestedTime, actualTime: &actualTime)

                // Wait for writer to be ready
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    if cancelled {
                        throw QuickMotionError.exportFailed(reason: "Export cancelled")
                    }
                }

                // Create pixel buffer from CGImage
                guard let pixelBuffer = createPixelBuffer(from: cgImage, size: outputSize, pool: pixelBufferAdaptor.pixelBufferPool) else {
                    continue // Skip this frame if we can't create a buffer
                }

                // Calculate presentation time for output
                let presentationTime = CMTimeMultiply(outputFrameDuration, multiplier: Int32(framesWritten))

                // Write frame
                if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                    let errorMsg = writer.error?.localizedDescription ?? "Failed to append pixel buffer"
                    throw QuickMotionError.exportFailed(reason: errorMsg)
                }

                framesWritten += 1

                // Report progress
                if let progress = progress {
                    let fractionComplete = Double(index + 1) / Double(totalFrames)
                    progress(min(fractionComplete, 1.0))
                }

            } catch let error as QuickMotionError {
                throw error
            } catch {
                // Skip frames that fail to generate (corrupted sections, etc.)
                continue
            }
        }

        // Finish writing
        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw QuickMotionError.exportFailed(reason: writer.error?.localizedDescription ?? "Unknown error")
        }

        // Cleanup
        self.imageGenerator = nil
        self.assetWriter = nil
    }

    /// Cancels an in-progress export
    public func cancel() {
        cancelled = true
        imageGenerator?.cancelAllCGImageGeneration()
    }

    // MARK: - Private Methods

    /// Creates a pixel buffer from a CGImage
    private func createPixelBuffer(from cgImage: CGImage, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        if let pool = pool {
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                return nil
            }
            pixelBuffer = buffer
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(size.width),
                Int(size.height),
                kCVPixelFormatType_32ARGB,
                attrs as CFDictionary,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                return nil
            }
            pixelBuffer = buffer
        }

        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }

    /// Calculate output size respecting video rotation
    private func calculateOutputSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        // Check if video is rotated 90 or 270 degrees
        let isRotated = abs(transform.b) == 1.0 && abs(transform.c) == 1.0
        if isRotated {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        }
        return naturalSize
    }

    /// Calculates appropriate bitrate based on resolution and quality
    private func calculateBitrate(for size: CGSize, quality: ExportQuality) -> Int {
        let pixels = size.width * size.height

        switch quality {
        case .fast:
            // HEVC: ~0.1 bits per pixel for good quality
            return Int(pixels * 0.1 * 30.0)
        case .quality:
            // ProRes is VBR and doesn't use bitrate hint in the same way
            return Int(pixels * 0.5 * 30.0)
        }
    }
}
