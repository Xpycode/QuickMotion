import SwiftUI
import AppKit

/// Displayed when export completes (success or failure)
struct ExportCompleteView: View {
    let result: ExportResult
    let fileInfo: String?
    let onShowInFinder: (() -> Void)?
    let onDone: () -> Void

    init(
        result: ExportResult,
        fileInfo: String? = nil,
        onShowInFinder: (() -> Void)?,
        onDone: @escaping () -> Void
    ) {
        self.result = result
        self.fileInfo = fileInfo
        self.onShowInFinder = onShowInFinder
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch result {
            case .success(let url):
                successContent(url: url)
            case .failure(let message):
                failureContent(message: message)
            }
        }
        .padding(24)
        .frame(minWidth: 300)
    }

    // MARK: - Success Content

    @ViewBuilder
    private func successContent(url: URL) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.green)

        Text("Export Complete")
            .font(.headline)

        VStack(spacing: 4) {
            Text("\"\(url.lastPathComponent)\"")
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            if let fileInfo {
                Text(fileInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        HStack(spacing: 12) {
            if let onShowInFinder {
                Button("Show in Finder") {
                    onShowInFinder()
                }
                .buttonStyle(.bordered)
            }

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
    }

    // MARK: - Failure Content

    @ViewBuilder
    private func failureContent(message: String) -> some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.red)

        Text("Export Failed")
            .font(.headline)

        Text("\"\(message)\"")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        Button("Done") {
            onDone()
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 8)
    }
}

// MARK: - Previews

#Preview("Export Success") {
    ExportCompleteView(
        result: .success(URL(fileURLWithPath: "/Users/demo/Movies/vacation_timelapse.mp4")),
        fileInfo: "ProRes 422 \u{2022} 1920\u{00D7}1080 \u{2022} 180.2 MB",
        onShowInFinder: { print("Show in Finder tapped") },
        onDone: { print("Done tapped") }
    )
    .frame(width: 400)
}

#Preview("Export Success - No File Info") {
    ExportCompleteView(
        result: .success(URL(fileURLWithPath: "/Users/demo/Movies/output.mov")),
        onShowInFinder: { print("Show in Finder tapped") },
        onDone: { print("Done tapped") }
    )
    .frame(width: 400)
}

#Preview("Export Failed") {
    ExportCompleteView(
        result: .failure("Disk full - need 180 MB free"),
        onShowInFinder: nil,
        onDone: { print("Done tapped") }
    )
    .frame(width: 400)
}
