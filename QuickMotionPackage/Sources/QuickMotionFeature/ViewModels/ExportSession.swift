import AVFoundation
import Foundation
import Observation

// MARK: - Export State

/// Represents the current state of an export operation
public enum ExportState: Sendable, Equatable {
    case idle
    case preparing
    case exporting(progress: Double)
    case completed(url: URL)
    case failed(error: String)
    case cancelled

    public static func == (lhs: ExportState, rhs: ExportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.preparing, .preparing):
            return true
        case (.exporting(let lProgress), .exporting(let rProgress)):
            return lProgress == rProgress
        case (.completed(let lURL), .completed(let rURL)):
            return lURL == rURL
        case (.failed(let lError), .failed(let rError)):
            return lError == rError
        case (.cancelled, .cancelled):
            return true
        default:
            return false
        }
    }
}

// MARK: - Export Session

/// Manages a single video export operation
@MainActor
@Observable
public final class ExportSession: Identifiable {
    public let id = UUID()

    // MARK: - Stored Properties (Captured at Init)

    /// Source video asset to export
    public let sourceAsset: AVAsset

    /// Speed multiplier for timelapse effect
    public let speedMultiplier: Double

    /// Export configuration settings
    public var settings: ExportSettings

    /// Destination URL for exported file
    public var outputURL: URL

    /// Optional IN point for trimming (seconds from start)
    public let inPoint: Double?

    /// Optional OUT point for trimming (seconds from start)
    public let outPoint: Double?

    // MARK: - Observable State

    /// Current state of the export
    public private(set) var state: ExportState = .idle

    /// Export progress from 0.0 to 1.0
    public private(set) var fractionComplete: Double = 0

    /// Time elapsed since export started
    public private(set) var elapsedTime: TimeInterval = 0

    /// Estimated time remaining (nil if cannot be calculated)
    public private(set) var estimatedTimeRemaining: TimeInterval?

    // MARK: - Private Properties

    /// The underlying AVAssetExportSession (for future real implementation)
    private var exportSession: AVAssetExportSession?
    
    /// Frame decimation exporter for fast timelapse exports
    private var frameDecimationExporter: FrameDecimationExporter?

    /// Timer for progress updates
    private var progressTimer: Timer?

    /// When the export started
    private var startTime: Date?

    /// Whether we're using security-scoped resource access for the output URL
    private var accessingSecurityScopedResource = false

    // MARK: - Initialization

    /// Creates a new export session
    /// - Parameters:
    ///   - asset: Source video asset
    ///   - speedMultiplier: Speed factor for timelapse (2x-100x)
    ///   - settings: Export configuration
    ///   - outputURL: Destination file URL
    ///   - inPoint: Optional trim IN point (seconds)
    ///   - outPoint: Optional trim OUT point (seconds)
    public init(
        asset: AVAsset,
        speedMultiplier: Double,
        settings: ExportSettings,
        outputURL: URL,
        inPoint: Double? = nil,
        outPoint: Double? = nil
    ) {
        self.sourceAsset = asset
        self.speedMultiplier = speedMultiplier
        self.settings = settings
        self.outputURL = outputURL
        self.inPoint = inPoint
        self.outPoint = outPoint
    }

    // MARK: - Public Methods

    /// Starts the export operation
    public func start() async {
        guard case .idle = state else { return }

        state = .preparing
        startTime = Date()
        fractionComplete = 0
        elapsedTime = 0
        estimatedTimeRemaining = nil

        // Start security-scoped resource access for sandboxed apps
        // This is required when outputURL comes from NSSavePanel/NSOpenPanel
        accessingSecurityScopedResource = outputURL.startAccessingSecurityScopedResource()

        do {
            // Pre-flight check: verify sufficient disk space
            let estimatedSize = settings.estimatedFileSize(
                inputSize: await estimateSourceSize(),
                speedMultiplier: speedMultiplier
            )
            try checkDiskSpace(estimatedSize: estimatedSize)

            // Choose export method based on settings
            if settings.shouldUseFrameDecimation(speedMultiplier: speedMultiplier) {
                // Use frame decimation for speed > 2x (faster export)
                try await exportWithFrameDecimation()
                return
            }

            // Fall through to legacy AVAssetExportSession path for speed <= 2x

            // Create composition and configure export
            let (_, export) = try await prepareExport()

            // Check if cancelled during preparation
            if case .cancelled = state {
                cleanupOnFailure()
                stopSecurityScopedAccess()
                return
            }

            // Store export session for cancellation support
            self.exportSession = export

            // Start exporting state and progress timer
            state = .exporting(progress: 0)
            startProgressTimer()

            // Execute the export
            await export.export()

            // Stop progress timer
            stopProgressTimer()

            // Handle export result
            switch export.status {
            case .completed:
                fractionComplete = 1.0
                stopSecurityScopedAccess()
                state = .completed(url: outputURL)

            case .cancelled:
                cleanupOnFailure()
                stopSecurityScopedAccess()
                state = .cancelled

            case .failed:
                let errorMessage = mapExportError(export.error)
                cleanupOnFailure()
                stopSecurityScopedAccess()
                state = .failed(error: errorMessage)

            default:
                cleanupOnFailure()
                stopSecurityScopedAccess()
                state = .failed(error: "Export ended with unexpected status: \(export.status.rawValue)")
            }

        } catch {
            stopProgressTimer()
            cleanupOnFailure()
            stopSecurityScopedAccess()
            state = .failed(error: error.localizedDescription)
        }
    }

    // MARK: - Export Preparation

    /// Prepares the AVMutableComposition and AVAssetExportSession
    private func prepareExport() async throws -> (AVMutableComposition, AVAssetExportSession) {
        // Create composition
        let composition = AVMutableComposition()

        // Add video track to composition
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.failedToCreateVideoTrack
        }

        // Get source video track
        let sourceTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = sourceTracks.first else {
            throw ExportError.noVideoTrackInSource
        }

        // Load duration and preferred transform
        let fullDuration = try await sourceAsset.load(.duration)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        // Calculate effective time range (using trim points if set)
        let effectiveStart = inPoint ?? 0
        let effectiveEnd = outPoint ?? fullDuration.seconds
        let trimmedDuration = effectiveEnd - effectiveStart

        // Validate time range
        guard effectiveEnd > effectiveStart else {
            throw QuickMotionError.invalidTimeRange("Out point must be after in point")
        }
        guard trimmedDuration > 0.1 else {
            throw QuickMotionError.invalidTimeRange("Selected duration too short (minimum 0.1 seconds)")
        }

        let startTime = CMTime(seconds: effectiveStart, preferredTimescale: fullDuration.timescale)
        let durationTime = CMTime(seconds: trimmedDuration, preferredTimescale: fullDuration.timescale)
        let timeRange = CMTimeRange(start: startTime, duration: durationTime)

        // Insert trimmed video into composition
        try videoTrack.insertTimeRange(
            timeRange,
            of: sourceVideoTrack,
            at: .zero
        )

        // Preserve video orientation
        videoTrack.preferredTransform = preferredTransform

        // Optionally include audio (also trimmed)
        if settings.includeAudio {
            let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first,
               let audioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try audioTrack.insertTimeRange(
                    timeRange,
                    of: sourceAudioTrack,
                    at: .zero
                )
            }
        }

        // Scale time for timelapse effect
        // Speed multiplier of 10x means duration becomes 1/10th
        let scaledDuration = CMTimeMultiplyByFloat64(durationTime, multiplier: 1.0 / speedMultiplier)
        composition.scaleTimeRange(
            CMTimeRange(start: .zero, duration: durationTime),
            toDuration: scaledDuration
        )

        // Remove existing output file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Configure export session
        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: settings.avExportPreset
        ) else {
            throw ExportError.failedToCreateExportSession
        }

        export.outputURL = outputURL
        export.outputFileType = settings.outputFileType
        export.shouldOptimizeForNetworkUse = false

        // Use fast audio algorithm for sped-up audio (varispeed = pitch shifts with speed)
        // Default .spectral is very slow for large speed changes
        if settings.includeAudio {
            export.audioTimePitchAlgorithm = .varispeed
        }

        return (composition, export)
    }

    /// Exports using frame decimation (faster for high speeds)
    private func exportWithFrameDecimation() async throws {
        let exporter = FrameDecimationExporter()
        self.frameDecimationExporter = exporter
        
        // Calculate time range if trim points are set
        let timeRange: CMTimeRange?
        if let inPoint = inPoint, let outPoint = outPoint {
            let duration = try await sourceAsset.load(.duration)
            let startTime = CMTime(seconds: inPoint, preferredTimescale: duration.timescale)
            let endTime = CMTime(seconds: outPoint, preferredTimescale: duration.timescale)
            timeRange = CMTimeRange(start: startTime, end: endTime)
        } else if let inPoint = inPoint {
            let duration = try await sourceAsset.load(.duration)
            let startTime = CMTime(seconds: inPoint, preferredTimescale: duration.timescale)
            timeRange = CMTimeRange(start: startTime, duration: CMTimeSubtract(duration, startTime))
        } else if let outPoint = outPoint {
            let duration = try await sourceAsset.load(.duration)
            let endTime = CMTime(seconds: outPoint, preferredTimescale: duration.timescale)
            timeRange = CMTimeRange(start: .zero, duration: endTime)
        } else {
            timeRange = nil
        }
        
        state = .exporting(progress: 0)
        startProgressTimer()
        
        do {
            try await exporter.export(
                asset: sourceAsset,
                to: outputURL,
                speedMultiplier: speedMultiplier,
                timeRange: timeRange,
                settings: settings
            ) { [weak self] progress in
                self?.fractionComplete = progress
                self?.state = .exporting(progress: progress)
            }
            
            // Success
            stopProgressTimer()
            fractionComplete = 1.0
            stopSecurityScopedAccess()
            state = .completed(url: outputURL)
            
        } catch {
            stopProgressTimer()
            cleanupOnFailure()
            stopSecurityScopedAccess()
            state = .failed(error: error.localizedDescription)
        }
        
        self.frameDecimationExporter = nil
    }

    /// Cancels the export operation
    public func cancel() {
        stopProgressTimer()
        exportSession?.cancelExport()
        frameDecimationExporter?.cancel()
        state = .cancelled
    }

    // MARK: - Private Methods

    /// Starts the timer that updates progress by polling exportSession.progress
    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    /// Stops the progress timer
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Updates progress by polling the export session
    private func updateProgress() {
        // Update elapsed time
        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }

        // Get actual progress from export session
        if let export = exportSession {
            fractionComplete = Double(export.progress)
        }

        // Calculate estimated time remaining
        if fractionComplete > 0.01 {
            let totalEstimatedTime = elapsedTime / fractionComplete
            estimatedTimeRemaining = max(0, totalEstimatedTime - elapsedTime)
        }

        // Update state with current progress
        state = .exporting(progress: fractionComplete)
    }

    /// Cleans up partial output file on failure or cancellation
    private func cleanupOnFailure() {
        try? FileManager.default.removeItem(at: outputURL)
    }

    /// Stops security-scoped resource access if it was started
    private func stopSecurityScopedAccess() {
        if accessingSecurityScopedResource {
            outputURL.stopAccessingSecurityScopedResource()
            accessingSecurityScopedResource = false
        }
    }

    // MARK: - Source Size Estimation

    /// Estimates the source file size for disk space calculations
    /// - Returns: Estimated source file size in bytes
    private func estimateSourceSize() async -> Int64 {
        // Try to get actual file size if source is a URL asset
        if let urlAsset = sourceAsset as? AVURLAsset {
            let fileURL = urlAsset.url
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                return fileSize
            }
        }

        // Fallback: estimate based on duration and typical bitrate
        // Use conservative estimate: 20 Mbps for HD video
        do {
            let duration = try await sourceAsset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            let estimatedBitrate: Double = 20_000_000 // 20 Mbps
            return Int64(seconds * estimatedBitrate / 8)
        } catch {
            // Last resort: assume 500 MB
            return 500_000_000
        }
    }

    // MARK: - Disk Space Checking

    /// Checks if there's enough disk space for the estimated output file
    /// - Parameter estimatedSize: Estimated output file size in bytes
    /// - Throws: ExportError.insufficientDiskSpace if not enough space
    private func checkDiskSpace(estimatedSize: Int64) throws {
        let directory = outputURL.deletingLastPathComponent()

        do {
            let resourceValues = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

            // Use volumeAvailableCapacityForImportantUsage which accounts for purgeable space
            if let availableCapacity = resourceValues.volumeAvailableCapacityForImportantUsage {
                // Add 10% buffer for safety
                let requiredSpace = Int64(Double(estimatedSize) * 1.1)

                if availableCapacity < requiredSpace {
                    throw QuickMotionError.insufficientDiskSpace(
                        required: requiredSpace,
                        available: availableCapacity
                    )
                }
            }
        } catch let error as QuickMotionError {
            throw error
        } catch {
            // If we can't check disk space, proceed anyway and let the export fail naturally
            // This is better than blocking exports when the check fails
        }
    }

    // MARK: - Error Message Mapping

    /// Maps AVAssetExportSession errors to user-friendly messages
    /// - Parameter error: The original error from AVAssetExportSession
    /// - Returns: A user-friendly error message
    private func mapExportError(_ error: Error?) -> String {
        guard let error = error else {
            return "Export failed for an unknown reason"
        }

        let nsError = error as NSError

        // Map common AVFoundation error codes to friendly messages
        switch nsError.domain {
        case AVFoundationErrorDomain:
            switch nsError.code {
            case AVError.diskFull.rawValue:
                return "Disk is full. Free up space and try again."
            case AVError.outOfMemory.rawValue:
                return "Not enough memory. Try closing other apps."
            case AVError.contentIsProtected.rawValue:
                return "This video is copy-protected and cannot be exported."
            case AVError.exportFailed.rawValue:
                // Check for underlying errors
                if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    return mapUnderlyingError(underlying)
                }
                return "Export failed. The video format may not be supported."
            case AVError.decodeFailed.rawValue:
                return "Could not decode the video. The file may be corrupted."
            default:
                break
            }
        case NSCocoaErrorDomain:
            switch nsError.code {
            case NSFileWriteNoPermissionError:
                return "Permission denied. Try saving to a different location."
            case NSFileWriteOutOfSpaceError:
                return "Disk is full. Free up space and try again."
            case NSFileWriteVolumeReadOnlyError:
                return "Cannot write to this location. The disk may be read-only."
            default:
                break
            }
        default:
            break
        }

        // Fallback to localized description
        return error.localizedDescription
    }

    /// Maps underlying errors to friendly messages
    private func mapUnderlyingError(_ error: NSError) -> String {
        // Common underlying error patterns
        if error.domain == NSOSStatusErrorDomain {
            // OSStatus errors from Core Media/Video Toolbox
            return "Video encoding failed. Try a different quality setting."
        }

        return error.localizedDescription
    }
}

// MARK: - Export Errors

/// Internal errors specific to export session setup
/// For user-facing errors (disk space, time range), use QuickMotionError
private enum ExportError: LocalizedError {
    case failedToCreateVideoTrack
    case noVideoTrackInSource
    case failedToCreateExportSession

    var errorDescription: String? {
        switch self {
        case .failedToCreateVideoTrack:
            return "Failed to create video track in composition"
        case .noVideoTrackInSource:
            return "Source video does not contain a video track"
        case .failedToCreateExportSession:
            return "Failed to create export session with the selected preset"
        }
    }
}

// MARK: - Convenience Extensions

extension ExportSession {
    /// Formatted elapsed time string (e.g., "0:05")
    public var formattedElapsedTime: String {
        formatTimeInterval(elapsedTime)
    }

    /// Formatted estimated remaining time string (e.g., "0:12")
    public var formattedTimeRemaining: String? {
        guard let remaining = estimatedTimeRemaining else { return nil }
        return formatTimeInterval(remaining)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
