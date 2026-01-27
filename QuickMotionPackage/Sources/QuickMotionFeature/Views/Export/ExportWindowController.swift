import AppKit
import SwiftUI

/// Controller for presenting the export window as a standalone macOS window
@MainActor
public final class ExportWindowController {
    private var window: NSWindow?
    private var session: ExportSession?

    public static let shared = ExportWindowController()

    private init() {}

    /// Opens the export window with the given session and project info
    public func open(
        session: ExportSession,
        sourceFileName: String,
        estimatedInputSize: Int64,
        sourceCodec: String?
    ) {
        // Close existing window if any
        close()

        self.session = session

        // Create the SwiftUI content
        let contentView = ExportWindow(
            session: session,
            sourceFileName: sourceFileName,
            estimatedInputSize: estimatedInputSize,
            sourceCodec: sourceCodec,
            onDismiss: { [weak self] in
                self?.close()
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

        // Make it a proper panel that floats above
        window.level = .floating

        // Restore saved position, or center if first launch
        if !window.setFrameAutosaveName("ExportWindow") {
            // Frame autosave name already set (shouldn't happen with singleton)
            window.center()
        } else if window.frame.origin == .zero {
            // First launch - no saved position yet
            window.center()
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the export window
    public func close() {
        window?.close()
        window = nil
        session = nil
    }
}
