import SwiftUI

/// Displays metadata about the loaded video
public struct VideoInfoView: View {
    let metadata: TimelapseProject.VideoMetadata
    let fileName: String

    public init(metadata: TimelapseProject.VideoMetadata, fileName: String) {
        self.metadata = metadata
        self.fileName = fileName
    }

    public var body: some View {
        HStack(spacing: 24) {
            // File name
            Label(fileName, systemImage: "film")
                .lineLimit(1)
                .truncationMode(.middle)

            Divider()
                .frame(height: 16)

            // Duration
            Label(metadata.formattedDuration, systemImage: "clock")

            // Resolution
            Label(metadata.resolutionString, systemImage: "rectangle.on.rectangle")

            // Frame rate
            Label(String(format: "%.0f fps", metadata.frameRate), systemImage: "gauge.with.needle")

            // Codec (if available)
            if let codec = metadata.codec {
                Label(codec, systemImage: "cpu")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    VideoInfoView(
        metadata: .init(
            duration: 334,
            naturalSize: CGSize(width: 1920, height: 1080),
            frameRate: 30,
            codec: "avc1"
        ),
        fileName: "vacation-footage-2024.mov"
    )
    .padding()
}
