import AVFoundation
import AVKit
import SwiftUI

/// Preview area - shows video playback with controls
public struct PreviewAreaView: View {
    var appState: AppState

    @State private var isHovering = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.05)

                    switch appState.previewState {
                    case .idle:
                        idlePlaceholder
                    case .loading:
                        loadingView
                    case .ready:
                        if let player = appState.player {
                            VideoPlayerView(player: player)
                                .overlay(alignment: .topTrailing) {
                                    if appState.speedMultiplier > 50 {
                                        Text("Preview may skip frames above 50x")
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                                            .padding(8)
                                    }
                                }
                        }
                    }
                }
                .onHover { hovering in
                    isHovering = hovering
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Playback controls when ready
            if appState.previewState == .ready {
                playbackControlBar
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Playback Control Bar

    private var playbackControlBar: some View {
        HStack(spacing: 12) {
            // Play/pause button
            Button {
                if appState.isPlaying {
                    appState.pause()
                } else {
                    appState.play()
                }
            } label: {
                Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            // Time-based scrubber
            Slider(
                value: Binding(
                    get: { appState.currentTime },
                    set: { newTime in
                        appState.seek(to: newTime)
                    }
                ),
                in: 0...max(0.1, appState.duration)
            )
            .controlSize(.small)

            // Time display (current / total)
            Text("\(formatTime(appState.currentTime)) / \(formatTime(appState.duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Sub-views

    private var idlePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop a video to begin")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading video...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    /// Formats seconds as "M:SS" or "H:MM:SS"
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

#Preview {
    Text("Preview requires AppState with loaded video")
        .frame(width: 600, height: 400)
}
