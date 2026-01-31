import SwiftUI
import UniformTypeIdentifiers

/// Empty state view with drag-drop target
public struct DropZoneView: View {
    let onDrop: (URL) -> Void

    @State private var isTargeted = false

    public init(onDrop: @escaping (URL) -> Void) {
        self.onDrop = onDrop
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Drop a video to create a timelapse")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("or")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Choose File...") {
                openFilePicker()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        }
        .padding()
        .onDrop(of: VideoDropHandler.supportedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            if let url = await VideoDropHandler.loadURL(from: providers) {
                await MainActor.run {
                    onDrop(url)
                }
            }
        }
        return true
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = VideoDropHandler.allowedContentTypes
        panel.message = "Select a video file"

        if panel.runModal() == .OK, let url = panel.url {
            onDrop(url)
        }
    }
}

#Preview {
    DropZoneView { url in
        print("Dropped: \(url)")
    }
    .frame(width: 600, height: 400)
}
