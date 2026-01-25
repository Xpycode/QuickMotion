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
                    speedMultiplier: appState.speedMultiplier,
                    inputDuration: project.metadata?.formattedDuration,
                    outputDuration: project.formattedOutputDuration
                )

                // Speed presets
                SpeedPresetsView(sliderValue: $appState.sliderValue)

                // Bottom row: export settings + export button
                HStack {
                    // Placeholder for export settings (Phase 3)
                    Menu("Export Settings") {
                        Text("Fast (HEVC)")
                        Text("Quality (ProRes)")
                        Text("Match Original")
                    }
                    .disabled(true) // Enable in Phase 3

                    Spacer()

                    Button("Clear") {
                        appState.clearProject()
                    }
                    .buttonStyle(.bordered)

                    Button("Export...") {
                        // Phase 3
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true) // Enable in Phase 3
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
