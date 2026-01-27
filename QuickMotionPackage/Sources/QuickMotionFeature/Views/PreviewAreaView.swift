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
        // Main slider row with fixed padding - overlay keeps trim indicator out of layout
        HStack(alignment: .center, spacing: 12) {
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

            // Loop toggle button
            Button {
                appState.isLooping.toggle()
            } label: {
                Image(systemName: appState.isLooping ? "repeat" : "repeat")
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(appState.isLooping ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .help(appState.isLooping ? "Looping on" : "Looping off")

            // Timeline with trim overlay
            timelineScrubber

            // Time display (current / trimmed duration)
            Text("\(formatTime(appState.currentTime - appState.effectiveInPoint)) / \(formatTime(appState.effectiveOutPoint - appState.effectiveInPoint))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 26)  // Fixed space for trim indicator row below
        .frame(maxWidth: .infinity, alignment: .leading)
        // Overlay excludes trim indicator from parent layout calculation entirely
        .overlay(alignment: .bottomLeading) {
            trimIndicatorBar
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .opacity(appState.hasTrimPoints ? 1 : 0)
        }
        .background(.bar, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Timeline Scrubber with Trim Overlay

    private var timelineScrubber: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Trim overlay (yellow region with handles) - always in tree, visibility via opacity
                // Removing the 'if' prevents structural identity changes that cause layout shifts
                trimOverlay(in: geometry)
                    .opacity(appState.hasTrimPoints ? 1 : 0)

                // Full-range slider on top
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
            }
        }
        .frame(height: 24)
    }

    /// Yellow trim overlay showing the selected region using Canvas for pixel-perfect positioning
    private func trimOverlay(in geometry: GeometryProxy) -> some View {
        // macOS small slider thumb radius is approximately 7px
        let sliderPadding: CGFloat = 7
        let trackWidth = geometry.size.width - (sliderPadding * 2)
        let duration = max(0.1, appState.duration)

        let inFraction = appState.effectiveInPoint / duration
        let outFraction = appState.effectiveOutPoint / duration

        let inX = sliderPadding + (trackWidth * inFraction)
        let outX = sliderPadding + (trackWidth * outFraction)

        return Canvas { context, size in
            let overlayHeight: CGFloat = 16
            let cornerRadius: CGFloat = 4
            let yCenter = (size.height - overlayHeight) / 2

            // Dimmed region before IN
            if inX > sliderPadding {
                let rect = CGRect(x: sliderPadding, y: yCenter, width: inX - sliderPadding, height: overlayHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: cornerRadius), with: .color(Color.black.opacity(0.4)))
            }

            // Trimmed region (yellow highlight with border)
            let trimWidth = max(0, outX - inX)
            if trimWidth > 0 {
                let trimRect = CGRect(x: inX, y: yCenter, width: trimWidth, height: overlayHeight)
                context.fill(Path(roundedRect: trimRect, cornerRadius: cornerRadius), with: .color(Color.yellow.opacity(0.15)))
                context.stroke(Path(roundedRect: trimRect, cornerRadius: cornerRadius), with: .color(.yellow), lineWidth: 2)
            }

            // Dimmed region after OUT
            if outX < size.width - sliderPadding {
                let rect = CGRect(x: outX, y: yCenter, width: size.width - sliderPadding - outX, height: overlayHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: cornerRadius), with: .color(Color.black.opacity(0.4)))
            }

            // IN handle (yellow bar)
            let inHandleRect = CGRect(x: inX - 2, y: yCenter, width: 4, height: overlayHeight)
            context.fill(Path(roundedRect: inHandleRect, cornerRadius: 2), with: .color(.yellow))

            // OUT handle (yellow bar)
            let outHandleRect = CGRect(x: outX - 2, y: yCenter, width: 4, height: overlayHeight)
            context.fill(Path(roundedRect: outHandleRect, cornerRadius: 2), with: .color(.yellow))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Trim Indicator

    private var trimIndicatorBar: some View {
        // Always render all elements for consistent layout sizing
        HStack(spacing: 8) {
            // IN point - always present, visibility controlled separately
            Label("IN \(formatTime(appState.inPoint ?? 0))", systemImage: "arrow.right.to.line")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(appState.inPoint != nil ? 1 : 0)

            // OUT point - always present, visibility controlled separately
            Label("OUT \(formatTime(appState.outPoint ?? 0))", systemImage: "arrow.left.to.line")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(appState.outPoint != nil ? 1 : 0)

            Spacer()

            // Clear button - always present
            Button {
                appState.clearTrimPoints()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear trim points (X)")
        }
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
