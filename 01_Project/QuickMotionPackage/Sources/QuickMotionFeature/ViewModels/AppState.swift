import AVFoundation
import Observation
import SwiftUI

/// Speed adjustment mode for keyboard controls
public enum SpeedMode: String, CaseIterable {
    case linear = "linear"
    case multiplicative = "multiplicative"
    case presets = "presets"
}

/// Main application state
@MainActor
@Observable
public final class AppState: VideoPlayerServiceDelegate {

    // MARK: - Project State

    /// Current project (nil when no video loaded)
    public var project: TimelapseProject?

    /// Whether a video is currently loaded
    public var hasVideo: Bool { project != nil }

    // MARK: - Speed Control

    /// Current speed adjustment mode for keyboard controls
    public var speedMode: SpeedMode = .multiplicative

    /// Slider value (0...1) - maps logarithmically to speed
    public var sliderValue: Double = 0.5 {
        didSet {
            project?.speedMultiplier = speedFromSlider(sliderValue)
            desiredRate = Float(speedMultiplier)

            if isPlaying {
                playerService.setRate(desiredRate)
            }
        }
    }

    /// Computed speed multiplier from slider (2x to 100x, logarithmic)
    public var speedMultiplier: Double {
        speedFromSlider(sliderValue)
    }

    /// Formatted speed string (e.g., "12x")
    public var formattedSpeed: String {
        String(format: "%.0fx", speedMultiplier)
    }

    // MARK: - UI State

    /// Whether we're currently loading a video
    public var isLoading = false

    /// Current error message to display
    public var errorMessage: String?

    /// Whether to show the error alert
    public var showError = false

    // MARK: - Trim Points

    /// IN point for trimming (seconds from start)
    public var inPoint: Double? {
        didSet {
            project?.inPoint = inPoint
            updateTrimBoundaries()
        }
    }

    /// OUT point for trimming (seconds from start)
    public var outPoint: Double? {
        didSet {
            project?.outPoint = outPoint
            updateTrimBoundaries()
        }
    }

    /// Effective IN point (0 if not set)
    public var effectiveInPoint: Double { inPoint ?? 0 }

    /// Effective OUT point (duration if not set)
    public var effectiveOutPoint: Double { outPoint ?? duration }

    /// Whether any trim points are set
    public var hasTrimPoints: Bool { inPoint != nil || outPoint != nil }

    // MARK: - Preview State

    public enum PreviewState {
        case idle
        case loading
        case ready
    }

    public var previewState: PreviewState = .idle

    /// Current playback time in seconds
    public var currentTime: Double = 0

    /// Total video duration in seconds
    public var duration: Double = 0

    /// Whether preview is playing
    public var isPlaying: Bool = true

    /// Whether playback should loop
    public var isLooping: Bool = true {
        didSet {
            let endPoint = effectiveOutPoint
            if isLooping && currentTime >= endPoint - 0.1 && duration > 0 {
                seek(to: effectiveInPoint)
            }
        }
    }

    /// Desired playback rate (persisted across pause/play)
    public var desiredRate: Float = 1.0

    // MARK: - Private Dependencies

    private let playerService: AVPlayerService = AVPlayerService()

    /// Expose player for AVPlayerView binding
    public var player: AVPlayer? { playerService.player }

    // MARK: - Initialization

    public init() {
        playerService.delegate = self
    }

    // MARK: - Actions

    /// Loads a video from the given URL
    public func loadVideo(from url: URL) async {
        isLoading = true
        previewState = .loading
        errorMessage = nil

        do {
            var newProject = TimelapseProject(url: url)
            try await newProject.loadMetadata()

            let asset = AVURLAsset(url: url)
            let durationValue = try await asset.load(.duration)
            self.duration = durationValue.seconds

            try await playerService.load(url: url)

            self.project = newProject
            self.sliderValue = sliderFromSpeed(10.0)
            self.desiredRate = Float(speedMultiplier)
            self.previewState = .ready
            self.isPlaying = false
            playerService.pause()

        } catch {
            self.errorMessage = QuickMotionError.videoLoadFailed(url: url, underlying: error).localizedDescription
            self.showError = true
            self.previewState = .idle
        }

        isLoading = false
    }

    /// Clears the current project
    public func clearProject() {
        playerService.cleanup()
        project = nil
        previewState = .idle
        sliderValue = 0.5
        currentTime = 0
        duration = 0
        inPoint = nil
        outPoint = nil
    }

    // MARK: - VideoPlayerServiceDelegate

    public func playerService(_ service: VideoPlayerService, didUpdateTime time: Double) {
        self.currentTime = time
    }

    public func playerServiceDidReachEnd(_ service: VideoPlayerService) {
        if isLooping && isPlaying {
            seek(to: effectiveInPoint)
            playerService.setRate(desiredRate)
        } else {
            isPlaying = false
        }
    }

    public func playerServiceDidReachOutPoint(_ service: VideoPlayerService) {
        if isLooping && isPlaying {
            seek(to: effectiveInPoint)
            playerService.setRate(desiredRate)
        } else {
            pause()
        }
    }

    // MARK: - Playback Control

    /// Starts playback at the desired rate
    public func play() {
        isPlaying = true
        playerService.setRate(desiredRate)
    }

    /// Pauses playback
    public func pause() {
        isPlaying = false
        playerService.setRate(0)
    }

    /// Seeks to a specific time in seconds (clamped to trim bounds if set)
    public func seek(to time: Double) {
        let clampedTime = hasTrimPoints
            ? max(effectiveInPoint, min(effectiveOutPoint, time))
            : time
        playerService.seek(to: clampedTime)
    }

    // MARK: - Trim Point Actions

    /// Sets IN point at current playback time
    public func setInPoint() {
        if let out = outPoint, currentTime >= out {
            inPoint = max(0, out - 0.1)
        } else {
            inPoint = currentTime
        }
    }

    /// Sets OUT point at current playback time
    public func setOutPoint() {
        if let inPt = inPoint, currentTime <= inPt {
            outPoint = min(duration, inPt + 0.1)
        } else {
            outPoint = currentTime
        }
    }

    /// Clears both trim points, restoring full video access
    public func clearTrimPoints() {
        inPoint = nil
        outPoint = nil
    }

    // MARK: - Speed Adjustment (Keyboard)

    /// Increases speed based on current mode
    public func increaseSpeed(big: Bool) {
        let newSpeed: Double

        switch speedMode {
        case .linear:
            let increment = big ? 10.0 : 1.0
            newSpeed = min(100, speedMultiplier + increment)
        case .multiplicative:
            let factor = big ? 2.0 : 1.5
            newSpeed = min(100, speedMultiplier * factor)
        case .presets:
            let presets = [2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 100.0]
            let skip = big ? 2 : 1
            if let currentIndex = presets.firstIndex(where: { $0 >= speedMultiplier }) {
                let newIndex = min(presets.count - 1, currentIndex + skip)
                newSpeed = presets[newIndex]
            } else {
                newSpeed = presets.last!
            }
        }

        sliderValue = sliderFromSpeed(newSpeed)
    }

    /// Decreases speed based on current mode
    public func decreaseSpeed(big: Bool) {
        let newSpeed: Double

        switch speedMode {
        case .linear:
            let decrement = big ? 10.0 : 1.0
            newSpeed = max(2, speedMultiplier - decrement)
        case .multiplicative:
            let factor = big ? 2.0 : 1.5
            newSpeed = max(2, speedMultiplier / factor)
        case .presets:
            let presets = [2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 100.0]
            let skip = big ? 2 : 1
            if let currentIndex = presets.lastIndex(where: { $0 <= speedMultiplier }) {
                let newIndex = max(0, currentIndex - skip)
                newSpeed = presets[newIndex]
            } else {
                newSpeed = presets.first!
            }
        }

        sliderValue = sliderFromSpeed(newSpeed)
    }

    /// Toggles play/pause state
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Updates playback boundaries when trim points change
    private func updateTrimBoundaries() {
        playerService.setTrimBoundaries(inPoint: inPoint, outPoint: outPoint)

        if currentTime < effectiveInPoint || currentTime > effectiveOutPoint {
            seek(to: effectiveInPoint)
        }
    }

    // MARK: - Speed Conversion

    /// Converts slider value (0...1) to speed (2...100) using logarithmic scale
    /// Formula: speed = 2 * 50^sliderValue
    /// At 0.0 → 2x, at 0.5 → ~14x, at 1.0 → 100x
    private func speedFromSlider(_ value: Double) -> Double {
        let speed = 2.0 * pow(50.0, value)
        return min(100, max(2, speed))
    }

    /// Converts speed to slider value (inverse of above)
    public func sliderFromSpeed(_ speed: Double) -> Double {
        let value = log(speed / 2.0) / log(50.0)
        return min(1, max(0, value))
    }
}
