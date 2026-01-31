import AppKit
import SwiftUI

/// Controller for presenting export windows as standalone macOS windows
/// Supports multiple concurrent exports, each with its own window
@MainActor
public final class ExportWindowController {
    private var windows: [UUID: NSWindow] = [:]
    private var sessions: [UUID: ExportSession] = [:]

    public static let shared = ExportWindowController()

    private init() {}

    /// Opens a new export window with the given session and project info
    /// Returns the window ID for tracking
    @discardableResult
    public func open(
        session: ExportSession,
        sourceFileName: String,
        estimatedInputSize: Int64,
        sourceCodec: String?
    ) -> UUID {
        let windowID = UUID()

        self.sessions[windowID] = session

        // Create the SwiftUI content
        let contentView = ExportWindow(
            session: session,
            sourceFileName: sourceFileName,
            estimatedInputSize: estimatedInputSize,
            sourceCodec: sourceCodec,
            onDismiss: { [weak self] in
                self?.close(windowID)
            }
        )

        // Create the hosting view
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Calculate ideal size
        let fittingSize = hostingView.fittingSize

        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: max(480, fittingSize.width), height: fittingSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Export Timelapse"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false

        // Position: cascade from existing windows or center if first
        if let lastWindow = windows.values.first {
            // Offset from last window
            let lastFrame = lastWindow.frame
            let newOrigin = NSPoint(
                x: lastFrame.origin.x + 30,
                y: lastFrame.origin.y - 30
            )
            window.setFrameOrigin(newOrigin)
        } else {
            // First window - center it
            window.center()
        }

        self.windows[windowID] = window
        window.makeKeyAndOrderFront(nil)

        return windowID
    }

    /// Closes a specific export window by ID
    public func close(_ windowID: UUID) {
        windows[windowID]?.close()
        windows.removeValue(forKey: windowID)
        sessions.removeValue(forKey: windowID)
    }

    /// Number of active export windows
    public var activeExportCount: Int {
        windows.count
    }
}
