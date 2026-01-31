import Foundation

/// Typed errors for QuickMotion operations
public enum QuickMotionError: LocalizedError {
    case videoLoadFailed(url: URL, underlying: Error?)
    case exportFailed(reason: String)
    case invalidTimeRange(String)
    case unsupportedFormat(String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .videoLoadFailed(let url, let underlying):
            if let underlying = underlying {
                return "Failed to load video from \(url.lastPathComponent): \(underlying.localizedDescription)"
            } else {
                return "Failed to load video from \(url.lastPathComponent)"
            }

        case .exportFailed(let reason):
            return "Export failed: \(reason)"

        case .invalidTimeRange(let details):
            return "Invalid time range: \(details)"

        case .unsupportedFormat(let details):
            return "Unsupported video format: \(details)"

        case .insufficientDiskSpace(let required, let available):
            let requiredMB = Double(required) / 1_048_576
            let availableMB = Double(available) / 1_048_576
            return String(format: "Insufficient disk space. Required: %.1f MB, Available: %.1f MB", requiredMB, availableMB)

        case .cancelled:
            return "Export was cancelled"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .videoLoadFailed:
            return "Ensure the video file exists and is not corrupted. Try opening it in another application to verify."

        case .exportFailed:
            return "Check that the export destination is writable and has sufficient space. Try exporting to a different location."

        case .invalidTimeRange:
            return "Adjust the trim points so that the out point is after the in point."

        case .unsupportedFormat:
            return "Try converting the video to a common format like MP4 or MOV using a video converter."

        case .insufficientDiskSpace(let required, _):
            let requiredMB = Double(required) / 1_048_576
            return String(format: "Free up at least %.1f MB of disk space and try again.", requiredMB)

        case .cancelled:
            return nil
        }
    }
}
