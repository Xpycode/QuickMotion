import Foundation

/// Delegate protocol for video player events
@MainActor
public protocol VideoPlayerServiceDelegate: AnyObject {
    /// Called periodically during playback to update current time (~10Hz)
    func playerService(_ service: VideoPlayerService, didUpdateTime time: Double)

    /// Called when playback reaches the end of the video
    func playerServiceDidReachEnd(_ service: VideoPlayerService)

    /// Called when playback reaches the OUT point (trim boundary)
    func playerServiceDidReachOutPoint(_ service: VideoPlayerService)
}

/// Abstraction for video player operations
@MainActor
public protocol VideoPlayerService: AnyObject {

    // MARK: - Properties

    /// Current playback time in seconds
    var currentTime: Double { get }

    /// Total video duration in seconds
    var duration: Double { get }

    /// Whether the player is currently playing
    var isPlaying: Bool { get }

    /// Current playback rate (speed multiplier)
    var rate: Float { get set }

    /// Delegate for receiving player events
    var delegate: VideoPlayerServiceDelegate? { get set }

    // MARK: - Methods

    /// Loads a video from the given URL
    /// - Parameter url: URL of the video file to load
    /// - Throws: Error if video cannot be loaded
    func load(url: URL) async throws

    /// Starts playback at the current rate
    func play()

    /// Pauses playback
    func pause()

    /// Seeks to a specific time in the video
    /// - Parameter time: Target time in seconds
    func seek(to time: Double)

    /// Sets the playback rate (speed multiplier)
    /// - Parameter rate: Playback rate (1.0 = normal speed)
    func setRate(_ rate: Float)

    /// Configures trim boundaries for constrained playback
    /// - Parameters:
    ///   - inPoint: Optional IN point in seconds (nil = start of video)
    ///   - outPoint: Optional OUT point in seconds (nil = end of video)
    func setTrimBoundaries(inPoint: Double?, outPoint: Double?)
}
