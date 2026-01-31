import AVFoundation
import Foundation

// MARK: - Export Errors

/// Internal errors specific to export session setup
/// For user-facing errors (disk space, time range), use QuickMotionError
enum ExportError: LocalizedError {
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

// MARK: - Error Message Mapping

extension ExportSession {
    /// Maps AVAssetExportSession errors to user-friendly messages
    /// - Parameter error: The original error from AVAssetExportSession
    /// - Returns: A user-friendly error message
    func mapExportError(_ error: Error?) -> String {
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
    func mapUnderlyingError(_ error: NSError) -> String {
        // Common underlying error patterns
        if error.domain == NSOSStatusErrorDomain {
            // OSStatus errors from Core Media/Video Toolbox
            return "Video encoding failed. Try a different quality setting."
        }

        return error.localizedDescription
    }
}
