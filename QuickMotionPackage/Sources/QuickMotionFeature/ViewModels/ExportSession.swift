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
    public init(
        asset: AVAsset,
        speedMultiplier: Double,
        settings: ExportSettings,
        outputURL: URL
    ) {
        self.sourceAsset = asset
        self.speedMultiplier = speedMultiplier
        self.settings = settings
        self.outputURL = outputURL
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
                let errorMessage = export.error?.localizedDescription ?? "Unknown export error"
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
        let duration = try await sourceAsset.load(.duration)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        // Insert full video into composition
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )

        // Preserve video orientation
        videoTrack.preferredTransform = preferredTransform

        // Optionally include audio
        if settings.includeAudio {
            let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first,
               let audioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceAudioTrack,
                    at: .zero
                )
            }
        }

        // Scale time for timelapse effect
        // Speed multiplier of 10x means duration becomes 1/10th
        let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / speedMultiplier)
        composition.scaleTimeRange(
            CMTimeRange(start: .zero, duration: duration),
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

    /// Cancels the export operation
    public func cancel() {
        stopProgressTimer()
        exportSession?.cancelExport()
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

// MARK: - Export Errors

/// Errors that can occur during export
public enum ExportError: LocalizedError {
    case failedToCreateVideoTrack
    case noVideoTrackInSource
    case failedToCreateExportSession

    public var errorDescription: String? {
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
