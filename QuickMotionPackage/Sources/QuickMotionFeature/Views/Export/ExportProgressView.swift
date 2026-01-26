import SwiftUI

struct ExportProgressView: View {
    let fileName: String
    let progress: Double
    let elapsedTime: String
    let remainingTime: String?
    let isPreparing: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text(titleText)
                .font(.headline)

            // Progress bar
            if isPreparing {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            // Progress percentage
            if !isPreparing {
                Text("\(Int(progress * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Time display
            HStack {
                Text("Elapsed: \(elapsedTime)")
                    .font(.system(.body, design: .monospaced))

                Spacer()

                if let remaining = remainingTime {
                    Text("Remaining: ~\(remaining)")
                        .font(.system(.body, design: .monospaced))
                }
            }
            .foregroundStyle(.secondary)

            // Cancel button
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }

    private var titleText: String {
        if isPreparing {
            return "Preparing export..."
        } else {
            return "Exporting \"\(fileName)\"..."
        }
    }
}

#Preview("Exporting") {
    ExportProgressView(
        fileName: "vacation_timelapse.mp4",
        progress: 0.48,
        elapsedTime: "0:42",
        remainingTime: "0:45",
        isPreparing: false,
        onCancel: {}
    )
    .padding()
}

#Preview("Preparing") {
    ExportProgressView(
        fileName: "vacation_timelapse.mp4",
        progress: 0.0,
        elapsedTime: "0:02",
        remainingTime: nil,
        isPreparing: true,
        onCancel: {}
    )
    .padding()
}
