import AVFoundation
import Foundation

@MainActor
public final class AVPlayerService: VideoPlayerService {
    // MARK: - Public Properties

    public private(set) var player: AVPlayer?

    public var currentTime: Double {
        player?.currentTime().seconds ?? 0
    }

    public var duration: Double {
        player?.currentItem?.duration.seconds ?? 0
    }

    public var isPlaying: Bool {
        player?.rate != 0
    }

    public var rate: Float {
        get { player?.rate ?? 0 }
        set { player?.rate = newValue }
    }

    public weak var delegate: VideoPlayerServiceDelegate?

    // MARK: - Private Properties

    private var timeObserverToken: Any?
    private var endObserverToken: NSObjectProtocol?
    private var outPointObserverToken: Any?

    // MARK: - Initialization

    public init() {}

    /// Cleans up all observers. Call before discarding the service.
    public func cleanup() {
        cleanupCurrentPlayer()
    }

    // MARK: - Public Methods

    public func load(url: URL) async throws {
        cleanupCurrentPlayer()

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)

        self.player = newPlayer

        setupTimeObserver()
        setupEndObserver()
    }

    public func play() {
        player?.play()
    }

    public func pause() {
        player?.pause()
    }

    public func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }

    public func setRate(_ rate: Float) {
        player?.rate = rate
    }

    public func setTrimBoundaries(inPoint: Double?, outPoint: Double?) {
        guard let playerItem = player?.currentItem else { return }

        if let inPoint = inPoint {
            playerItem.reversePlaybackEndTime = CMTime(seconds: inPoint, preferredTimescale: 600)
        } else {
            playerItem.reversePlaybackEndTime = .invalid
        }

        if let outPoint = outPoint {
            playerItem.forwardPlaybackEndTime = CMTime(seconds: outPoint, preferredTimescale: 600)
            setupOutPointObserver(at: outPoint)
        } else {
            playerItem.forwardPlaybackEndTime = .invalid
            removeOutPointObserver()
        }
    }

    // MARK: - Private Methods

    private func cleanupCurrentPlayer() {
        removeTimeObserver()
        removeEndObserver()
        removeOutPointObserver()

        player?.pause()
        player = nil
    }

    private func setupTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                self.delegate?.playerService(self, didUpdateTime: time.seconds)
            }
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func setupEndObserver() {
        guard let playerItem = player?.currentItem else { return }

        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.delegate?.playerServiceDidReachEnd(self)
            }
        }
    }

    private func removeEndObserver() {
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
    }

    private func setupOutPointObserver(at outPoint: Double) {
        removeOutPointObserver()

        guard let player = player else { return }

        let outPointTime = CMTime(seconds: outPoint, preferredTimescale: 600)
        outPointObserverToken = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: outPointTime)],
            queue: .main
        ) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.delegate?.playerServiceDidReachOutPoint(self)
            }
        }
    }

    private func removeOutPointObserver() {
        if let token = outPointObserverToken {
            player?.removeTimeObserver(token)
            outPointObserverToken = nil
        }
    }
}
