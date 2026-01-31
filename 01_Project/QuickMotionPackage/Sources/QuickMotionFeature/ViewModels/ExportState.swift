import Foundation

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
