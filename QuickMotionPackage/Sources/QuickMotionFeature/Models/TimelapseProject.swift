import AVFoundation
import Foundation

/// Core model representing a timelapse project
public struct TimelapseProject: Identifiable {
    public let id = UUID()

    /// Source video asset
    public let asset: AVAsset

    /// URL of the source file
    public let sourceURL: URL

    /// Speed multiplier (2x to 100x)
    public var speedMultiplier: Double = 10.0

    /// Optional in-point for trimming (seconds from start)
    public var inPoint: Double?

    /// Optional out-point for trimming (seconds from start)
    public var outPoint: Double?

    /// Video metadata extracted from asset
    public struct VideoMetadata: Sendable {
        public let duration: TimeInterval
        public let naturalSize: CGSize
        public let frameRate: Float
        public let codec: String?

        /// Formatted duration string (e.g., "2:34")
        public var formattedDuration: String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }

        /// Resolution string (e.g., "1920x1080")
        public var resolutionString: String {
            "\(Int(naturalSize.width))x\(Int(naturalSize.height))"
        }
    }

    public var metadata: VideoMetadata?

    public init(url: URL) {
        self.sourceURL = url
        self.asset = AVAsset(url: url)
    }

    /// Calculates the output duration based on speed multiplier
    public var outputDuration: TimeInterval? {
        guard let duration = metadata?.duration else { return nil }
        let effectiveDuration = (outPoint ?? duration) - (inPoint ?? 0)
        return effectiveDuration / speedMultiplier
    }

    /// Formatted output duration string
    public var formattedOutputDuration: String? {
        guard let duration = outputDuration else { return nil }
        if duration < 60 {
            return String(format: "%.0fs", duration)
        }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Metadata Loading

extension TimelapseProject {
    /// Loads metadata from the asset asynchronously
    @MainActor
    public mutating func loadMetadata() async throws {
        let duration = try await asset.load(.duration)

        // Get video track for size and frame rate
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw TimelapseError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        // Try to get codec info
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        let codec = formatDescriptions.first.flatMap { desc -> String? in
            let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
            return fourCCToString(mediaSubType)
        }

        self.metadata = VideoMetadata(
            duration: duration.seconds,
            naturalSize: naturalSize,
            frameRate: nominalFrameRate,
            codec: codec
        )
    }

    private func fourCCToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - Errors

public enum TimelapseError: LocalizedError {
    case noVideoTrack
    case exportFailed(String)
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The file doesn't contain a video track."
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .unsupportedFormat:
            return "This video format is not supported."
        }
    }
}
