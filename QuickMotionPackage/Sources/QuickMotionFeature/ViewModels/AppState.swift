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
public final class AppState {

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
            // Update project speed when slider changes
            project?.speedMultiplier = speedFromSlider(sliderValue)

            // Calculate and store desired rate
            desiredRate = Float(speedMultiplier)

            // If playing, apply rate immediately
            if isPlaying {
                player?.rate = desiredRate
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

    // MARK: - Preview State

    public enum PreviewState {
        case idle
        case loading
        case ready
    }

    public var previewState: PreviewState = .idle

    /// AVPlayer for video playback
    public var player: AVPlayer?

    /// Current playback time in seconds
    public var currentTime: Double = 0

    /// Total video duration in seconds
    public var duration: Double = 0

    /// Whether preview is playing
    public var isPlaying: Bool = true

    /// Whether playback should loop
    public var isLooping: Bool = true {
        didSet {
            // If enabling loop while at the end, seek to start
            if isLooping && currentTime >= duration - 0.1 && duration > 0 {
                seek(to: 0)
            }
        }
    }

    /// Desired playback rate (persisted across pause/play)
    public var desiredRate: Float = 1.0

    // MARK: - Private Dependencies

    /// Time observer for periodic time updates
    private var timeObserver: Any?

    /// Observer for end-of-playback (looping)
    private var endObserver: NSObjectProtocol?

    // MARK: - Initialization

    public init() {}

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
            let playerItem = AVPlayerItem(asset: asset)

            // Load duration
            let durationValue = try await asset.load(.duration)
            self.duration = durationValue.seconds

            // Create player
            let newPlayer = AVPlayer(playerItem: playerItem)
            self.player = newPlayer
            setupTimeObserver()

            self.project = newProject
            // Set slider to give ~10x speed initially
            self.sliderValue = sliderFromSpeed(10.0)
            self.desiredRate = Float(speedMultiplier)
            self.previewState = .ready
            self.isPlaying = false
            newPlayer.pause()  // Explicitly pause - AVPlayerView auto-plays otherwise
            setupLooping(for: newPlayer)

        } catch {
            self.errorMessage = error.localizedDescription
            self.showError = true
            self.previewState = .idle
        }

        isLoading = false
    }

    /// Clears the current project
    public func clearProject() {
        removeTimeObserver()
        removeEndObserver()
        player = nil
        project = nil
        previewState = .idle
        sliderValue = 0.5
        currentTime = 0
        duration = 0
    }

    // MARK: - Playback Control

    /// Starts playback at the desired rate
    public func play() {
        isPlaying = true
        player?.rate = desiredRate
    }

    /// Pauses playback
    public func pause() {
        isPlaying = false
        player?.rate = 0
    }

    /// Seeks to a specific time in seconds
    public func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
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

    // MARK: - Time Observer

    /// Sets up periodic time observer for currentTime updates
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
    }

    /// Removes the time observer
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    /// Sets up looping - when video ends, seek back to start if looping enabled
    private func setupLooping(for player: AVPlayer) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isLooping && self.isPlaying {
                    self.seek(to: 0)
                    self.player?.rate = self.desiredRate
                } else {
                    self.isPlaying = false
                }
            }
        }
    }

    /// Removes the end observer
    private func removeEndObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
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
        // speed = 2 * 50^value
        // speed/2 = 50^value
        // log(speed/2) = value * log(50)
        // value = log(speed/2) / log(50)
        let value = log(speed / 2.0) / log(50.0)
        return min(1, max(0, value))
    }
}
