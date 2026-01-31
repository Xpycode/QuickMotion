import AppKit
import SwiftUI

/// A view that provides access to the hosting NSWindow
/// Used to set frame autosave name for SwiftUI windows
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Sets the frame autosave name for the window containing this view
    /// macOS will automatically save and restore the window's frame
    func windowFrameAutosaveName(_ name: String) -> some View {
        background(
            WindowAccessor { window in
                window.setFrameAutosaveName(name)
            }
        )
    }
}
