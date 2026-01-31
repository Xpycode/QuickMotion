import AVFoundation
import Foundation
import Observation

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

    /// Passthrough exporter (keyframes only, no decode/encode - fastest)
    private var passthroughExporter: PassthroughExporter?

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

        // Normalize output URL for passthrough (requires .mov)
        // Must happen BEFORE startAccessingSecurityScopedResource()
        if speedMultiplier > 2.0 && outputURL.pathExtension.lowercased() != "mov" {
            outputURL = outputURL.deletingPathExtension().appendingPathExtension("mov")
        }

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

            // Choose export method based on speed
            // For speed > 2x, use passthrough (keyframes only, no decode/encode)
            // This is I/O bound but much faster than re-encoding
            if speedMultiplier > 2.0 {
                #if DEBUG
                print("[Export] Using Passthrough exporter (speed > 2x)")
                #endif
                try await exportWithPassthrough()
                return
            }
            #if DEBUG
            print("[Export] Using legacy AVAssetExportSession (speed <= 2x)")
            #endif

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

    /// Exports using PassthroughExporter (keyframes only, no decode/encode - FASTEST)
    /// This copies compressed keyframes directly without any transcoding
    private func exportWithPassthrough() async throws {
        let exporter = PassthroughExporter()
        self.passthroughExporter = exporter

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

        // Note: outputURL already normalized to .mov in start() for speed > 2x

        do {
            try await exporter.export(
                asset: sourceAsset,
                to: outputURL,
                speedMultiplier: speedMultiplier,
                timeRange: timeRange
            ) { [weak self] progress in
                self?.fractionComplete = progress
                self?.state = .exporting(progress: progress)
            }

            stopProgressTimer()
            fractionComplete = 1.0
            stopSecurityScopedAccess()
            state = .completed(url: outputURL)

        } catch {
            stopProgressTimer()
            stopSecurityScopedAccess()

            // Check if this was a cancellation vs actual failure
            if let qmError = error as? QuickMotionError, case .cancelled = qmError {
                state = .cancelled
            } else {
                cleanupOnFailure()
                state = .failed(error: error.localizedDescription)
            }
        }

        self.passthroughExporter = nil
    }

    /// Cancels the export operation
    public func cancel() {
        stopProgressTimer()
        exportSession?.cancelExport()
        passthroughExporter?.cancel()
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
