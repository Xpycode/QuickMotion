import AppKit
import SwiftUI

// MARK: - Export Result

/// Represents the result of an export operation for the complete view
public enum ExportResult {
    case success(URL)
    case failure(String)
}

/// Main container view for the export workflow.
/// Switches between Settings/Progress/Complete views based on ExportSession state.
public struct ExportWindow: View {

    // MARK: - Properties

    /// The export session managing the export operation
    @Bindable var session: ExportSession

    /// Original video filename for display
    let sourceFileName: String

    /// Input file size for estimates
    let estimatedInputSize: Int64

    /// Source video codec (FourCC string like "avc1", "hvc1")
    let sourceCodec: String?

    /// Called when the window should close
    let onDismiss: () -> Void

    // MARK: - Local State

    /// Settings are configured locally before export starts
    @State private var settings: ExportSettings

    // MARK: - Initialization

    public init(
        session: ExportSession,
        sourceFileName: String,
        estimatedInputSize: Int64,
        sourceCodec: String?,
        onDismiss: @escaping () -> Void
    ) {
        self.session = session
        self.sourceFileName = sourceFileName
        self.estimatedInputSize = estimatedInputSize
        self.sourceCodec = sourceCodec
        self.onDismiss = onDismiss
        // Initialize local settings from session's settings
        self._settings = State(initialValue: session.settings)
    }

    // MARK: - Body

    public var body: some View {
        Group {
            switch session.state {
            case .idle:
                ExportSettingsView(
                    settings: $settings,
                    sourceFileName: sourceFileName,
                    estimatedInputSize: estimatedInputSize,
                    speedMultiplier: session.speedMultiplier,
                    sourceCodec: sourceCodec,
                    onCancel: handleCancel,
                    onExport: handleExport
                )

            case .preparing:
                ExportProgressView(
                    fileName: sourceFileName,
                    progress: 0,
                    elapsedTime: session.formattedElapsedTime,
                    remainingTime: nil,
                    isPreparing: true,
                    onCancel: handleCancel
                )

            case .exporting:
                ExportProgressView(
                    fileName: sourceFileName,
                    progress: session.fractionComplete,
                    elapsedTime: session.formattedElapsedTime,
                    remainingTime: session.formattedTimeRemaining,
                    isPreparing: false,
                    onCancel: handleCancel
                )

            case .completed(let url):
                ExportCompleteView(
                    result: .success(url),
                    onShowInFinder: { showInFinder(url: url) },
                    onDone: onDismiss
                )

            case .failed(let error):
                ExportCompleteView(
                    result: .failure(error),
                    onShowInFinder: nil,
                    onDone: onDismiss
                )

            case .cancelled:
                Color.clear
                    .onAppear {
                        onDismiss()
                    }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    // MARK: - Actions

    /// Cancels the export and dismisses the window
    private func handleCancel() {
        session.cancel()
        onDismiss()
    }

    /// Starts the export operation
    private func handleExport() {
        // Update session with current settings (quality, audio, etc.)
        session.settings = settings
        // Update output URL
        if let outputURL = settings.outputURL {
            session.outputURL = outputURL
        }
        Task {
            await session.start()
        }
    }

    /// Opens Finder with the exported file selected
    private func showInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
