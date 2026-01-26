import SwiftUI

/// Main application view
public struct ContentView: View {
    @State private var appState = AppState()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let project = appState.project {
                // Video loaded - show main UI
                videoLoadedView(project: project)
            } else {
                // Empty state - show drop zone
                DropZoneView { url in
                    Task {
                        await appState.loadVideo(from: url)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .overlay {
            if appState.isLoading {
                loadingOverlay
            }
        }
        .alert("Error", isPresented: $appState.showError) {
            Button("OK") {
                appState.errorMessage = nil
            }
        } message: {
            if let error = appState.errorMessage {
                Text(error)
            }
        }
        .onDrop(of: [.movie, .video], isTargeted: nil) { providers in
            // Allow dropping anywhere when video is loaded
            handleDrop(providers)
        }
        .focusable()
        .focusEffectDisabled()  // Hide blue focus ring
        .onKeyPress { keyPress in
            guard appState.hasVideo else { return .ignored }

            switch keyPress.characters {
            case "j", "J":
                appState.decreaseSpeed(big: keyPress.modifiers.contains(.shift))
                return .handled
            case "k", "K":
                appState.togglePlayPause()
                return .handled
            case "l", "L":
                appState.increaseSpeed(big: keyPress.modifiers.contains(.shift))
                return .handled
            default:
                return .ignored
            }
        }
    }

    // MARK: - Video Loaded View

    @ViewBuilder
    private func videoLoadedView(project: TimelapseProject) -> some View {
        VStack(spacing: 0) {
            // Video info bar
            if let metadata = project.metadata {
                VideoInfoView(
                    metadata: metadata,
                    fileName: project.sourceURL.lastPathComponent
                )
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()
            }

            // Preview area (largest portion)
            PreviewAreaView(appState: appState)
                .padding()

            Divider()

            // Controls area
            VStack(spacing: 16) {
                // Speed slider
                SpeedSliderView(
                    sliderValue: $appState.sliderValue,
                    speedMode: $appState.speedMode,
                    speedMultiplier: appState.speedMultiplier,
                    inputDuration: project.metadata?.formattedDuration,
                    outputDuration: project.formattedOutputDuration
                )

                // Speed presets
                SpeedPresetsView(sliderValue: $appState.sliderValue)

                // Bottom row: clear + export button
                HStack {
                    Spacer()

                    Button("Clear") {
                        appState.clearProject()
                    }
                    .buttonStyle(.bordered)

                    Button("Export...") {
                        openExportWindow()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.bar)
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading video...")
                    .font(.headline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Export

    /// Opens the export window with the current project settings
    private func openExportWindow() {
        guard let project = appState.project else { return }

        // Create default export settings
        let settings = ExportSettings()

        // Generate output URL: same directory as source, with "_timelapse" suffix
        let sourceURL = project.sourceURL
        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = directory
            .appendingPathComponent("\(baseName)_timelapse")
            .appendingPathExtension(settings.fileExtension)

        // Create export session
        let session = ExportSession(
            asset: project.asset,
            speedMultiplier: appState.speedMultiplier,
            settings: settings,
            outputURL: outputURL
        )

        // Open in standalone window
        ExportWindowController.shared.open(
            session: session,
            sourceFileName: project.sourceURL.lastPathComponent,
            estimatedInputSize: fileSize(for: project.sourceURL),
            sourceCodec: project.metadata?.codec
        )
    }

    /// Returns the file size for a given URL
    private func fileSize(for url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.movie", options: nil) { item, _ in
            if let url = item as? URL {
                Task { @MainActor in
                    await appState.loadVideo(from: url)
                }
            }
        }

        return true
    }
}

#Preview {
    ContentView()
}
