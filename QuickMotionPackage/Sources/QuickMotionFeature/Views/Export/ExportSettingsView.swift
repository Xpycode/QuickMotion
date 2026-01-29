import SwiftUI
import UniformTypeIdentifiers

/// Export settings view shown when ExportSession state is `.idle`
/// Allows users to configure output filename, quality, and advanced options before exporting
public struct ExportSettingsView: View {
    @Binding var settings: ExportSettings
    let sourceFileName: String
    let estimatedInputSize: Int64
    let speedMultiplier: Double
    let sourceCodec: String?
    let onCancel: () -> Void
    let onExport: () -> Void

    @State private var outputFileName: String = ""
    @State private var outputDirectory: URL?

    public init(
        settings: Binding<ExportSettings>,
        sourceFileName: String,
        estimatedInputSize: Int64,
        speedMultiplier: Double,
        sourceCodec: String?,
        onCancel: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) {
        self._settings = settings
        self.sourceFileName = sourceFileName
        self.estimatedInputSize = estimatedInputSize
        self.speedMultiplier = speedMultiplier
        self.sourceCodec = sourceCodec
        self.onCancel = onCancel
        self.onExport = onExport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Output filename row
            outputRow

            Divider()

            // Quality picker
            qualitySection

            Divider()

            // Audio option
            Toggle("Include audio (sped up)", isOn: $settings.includeAudio)
                .toggleStyle(.checkbox)

            Divider()

            // Advanced options
            advancedOptionsSection

            Divider()

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Export…", action: showSavePanel)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            // Initialize output filename from source
            outputFileName = suggestedFileName
            outputDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            updateOutputURL()
        }
        .onChange(of: outputFileName) {
            updateOutputURL()
        }
        .onChange(of: settings.quality) {
            // Update filename extension when quality changes
            let baseName = (outputFileName as NSString).deletingPathExtension
            outputFileName = "\(baseName).\(settings.fileExtension)"
        }
    }

    // MARK: - Output Row

    private var outputRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Save as:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Filename", text: $outputFileName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    selectOutputDirectory()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .help("Choose output folder")
            }

            if let dir = outputDirectory {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                    Text(friendlyDirectoryName(for: dir))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Quality", selection: $settings.quality) {
                ForEach(ExportQuality.allCases, id: \.self) { quality in
                    qualityLabel(for: quality)
                        .tag(quality)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    private func qualityLabel(for quality: ExportQuality) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(quality.rawValue)
                Text(qualityDescription(for: quality))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("~\(estimatedSize(for: quality))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func qualityDescription(for quality: ExportQuality) -> String {
        switch quality {
        case .fast:
            return "HEVC, .mp4"
        case .quality:
            return "ProRes, .mov"
        }
    }

    private func estimatedSize(for quality: ExportQuality) -> String {
        let tempSettings = ExportSettings(quality: quality)
        let bytes = tempSettings.estimatedFileSize(inputSize: estimatedInputSize, speedMultiplier: speedMultiplier)
        return ExportSettings.formattedFileSize(bytes)
    }

    // MARK: - Advanced Options

    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Resolution:")
                        .frame(width: 80, alignment: .trailing)
                    Picker("Resolution", selection: $settings.resolution) {
                        ForEach(ExportResolution.allCases, id: \.self) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                // Note: Resolution only applies to HEVC quality
                GridRow {
                    Text("")
                        .frame(width: 80, alignment: .trailing)
                    Text("Resolution applies to Fast (HEVC) only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Frame rate picker hidden - not currently functional
                // TODO: v1.1 - Implement AVMutableVideoComposition for frame rate control
            }
        }
    }

    // MARK: - Helpers

    private var suggestedFileName: String {
        let baseName = (sourceFileName as NSString).deletingPathExtension
        return "\(baseName)_timelapse.\(settings.fileExtension)"
    }

    /// Updates settings.outputURL from current directory and filename
    private func updateOutputURL() {
        guard let dir = outputDirectory, !outputFileName.isEmpty else { return }
        settings.outputURL = dir.appendingPathComponent(outputFileName)
    }

    /// Returns a user-friendly name for standard directories
    private func friendlyDirectoryName(for url: URL) -> String {
        let name = url.lastPathComponent

        // Standard folder names get shown as-is
        let standardFolders = ["Movies", "Desktop", "Documents", "Downloads", "Pictures", "Music"]
        if standardFolders.contains(name) {
            return name
        }

        return name
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select output folder for the timelapse"

        if let currentDir = outputDirectory {
            panel.directoryURL = currentDir
        }

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            updateOutputURL()
        }
    }

    /// Shows NSSavePanel to get proper write permission, then starts export
    private func showSavePanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = outputFileName
        panel.allowedContentTypes = [
            settings.quality == .fast ? .mpeg4Movie : .quickTimeMovie
        ]

        if let dir = outputDirectory {
            panel.directoryURL = dir
        }

        if panel.runModal() == .OK, let url = panel.url {
            settings.outputURL = url
            outputDirectory = url.deletingLastPathComponent()
            outputFileName = url.lastPathComponent
            onExport()
        }
    }
}

#Preview("Default") {
    struct PreviewWrapper: View {
        @State var settings = ExportSettings()

        var body: some View {
            ExportSettingsView(
                settings: $settings,
                sourceFileName: "vacation-footage-2024.mov",
                estimatedInputSize: 500_000_000,
                speedMultiplier: 10.0,
                sourceCodec: "avc1",
                onCancel: { print("Cancel") },
                onExport: { print("Export") }
            )
        }
    }

    return PreviewWrapper()
}

#Preview("ProRes Selected") {
    struct PreviewWrapper: View {
        @State var settings = ExportSettings(quality: .quality)

        var body: some View {
            ExportSettingsView(
                settings: $settings,
                sourceFileName: "wedding-video.mp4",
                estimatedInputSize: 2_000_000_000,
                speedMultiplier: 8.0,
                sourceCodec: "hvc1",
                onCancel: { print("Cancel") },
                onExport: { print("Export") }
            )
        }
    }

    return PreviewWrapper()
}
