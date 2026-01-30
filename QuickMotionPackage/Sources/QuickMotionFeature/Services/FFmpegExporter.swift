import Foundation

/// FFmpeg-based timelapse exporter - the fastest option
///
/// Uses FFmpeg for frame selection and hardware-accelerated encoding:
/// - Can select every Nth frame efficiently (doesn't read skipped frames fully)
/// - Hardware encoding with hevc_videotoolbox
/// - Proven, battle-tested tool for video processing
///
/// Requires FFmpeg to be installed (e.g., via Homebrew: brew install ffmpeg)
public final class FFmpegExporter: @unchecked Sendable {

    public typealias ProgressCallback = @MainActor @Sendable (Double) -> Void

    private var process: Process?
    private let cancelledLock = NSLock()
    private var _cancelled = false

    private var cancelled: Bool {
        get {
            cancelledLock.lock()
            defer { cancelledLock.unlock() }
            return _cancelled
        }
        set {
            cancelledLock.lock()
            _cancelled = newValue
            cancelledLock.unlock()
        }
    }

    public init() {}

    /// Common FFmpeg paths (checked in order - bundled first)
    private static var ffmpegPaths: [String] {
        var paths: [String] = []

        // Check bundled FFmpeg first (in app bundle's Helpers folder)
        if let bundlePath = Bundle.main.path(forResource: "ffmpeg", ofType: nil, inDirectory: "Helpers") {
            paths.append(bundlePath)
        }
        // Also check Resources folder as fallback
        if let resourcePath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            paths.append(resourcePath)
        }

        // Fall back to system paths
        paths.append(contentsOf: [
            "/opt/homebrew/bin/ffmpeg",  // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",      // Intel Homebrew
            "/usr/bin/ffmpeg"             // System
        ])

        return paths
    }

    /// Checks if FFmpeg is available
    public static var isAvailable: Bool {
        return ffmpegPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Find FFmpeg path
    private func findFFmpegPath() -> String? {
        return Self.ffmpegPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Exports timelapse using FFmpeg
    /// - Parameters:
    ///   - inputURL: Source video URL
    ///   - outputURL: Destination URL
    ///   - speedMultiplier: Speed factor (e.g., 16x)
    ///   - duration: Total duration for progress calculation
    ///   - progress: Progress callback
    @MainActor
    public func export(
        inputURL: URL,
        to outputURL: URL,
        speedMultiplier: Double,
        duration: Double,
        progress: ProgressCallback? = nil
    ) async throws {
        cancelled = false

        guard let ffmpegPath = findFFmpegPath() else {
            throw QuickMotionError.exportFailed(reason: "FFmpeg not found. Install with: brew install ffmpeg")
        }

        // Remove existing output
        try? FileManager.default.removeItem(at: outputURL)

        // Calculate frame selection interval
        // At 16x speed: select every 16th frame
        let frameInterval = max(1, Int(round(speedMultiplier)))

        // Build FFmpeg command
        // Using select filter to pick every Nth frame, then hardware encode
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)

        // FFmpeg arguments:
        // -i input: input file
        // -vf "select='not(mod(n,N))',setpts=N/FRAME_RATE/TB": select every Nth frame, fix timestamps
        // -c:v hevc_videotoolbox: hardware-accelerated HEVC encoding
        // -q:v 65: quality (lower = better, 65 is good balance)
        // -tag:v hvc1: compatibility tag for Apple devices
        // -an: no audio
        // -progress pipe:1: output progress to stdout
        // -y: overwrite output

        let outputFrameRate = 30 // Target output framerate

        process.arguments = [
            "-i", inputURL.path,
            "-vf", "select='not(mod(n,\(frameInterval)))',setpts=N/\(outputFrameRate)/TB",
            "-c:v", "hevc_videotoolbox",
            "-q:v", "65",
            "-tag:v", "hvc1",
            "-an",
            "-progress", "pipe:1",
            "-y",
            outputURL.path
        ]

        // Capture stdout for progress
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process

        // Log command for debugging
        print("[FFmpeg] Command: \(ffmpegPath) \(process.arguments?.joined(separator: " ") ?? "")")
        print("[FFmpeg] Input: \(inputURL.path)")
        print("[FFmpeg] Output: \(outputURL.path)")

        // Start process
        do {
            try process.run()
            print("[FFmpeg] Process started with PID: \(process.processIdentifier)")
        } catch {
            print("[FFmpeg] Failed to start: \(error)")
            throw QuickMotionError.exportFailed(reason: "Failed to start FFmpeg: \(error.localizedDescription)")
        }

        // Read progress in background
        let capturedDuration = duration
        let capturedProcess = process

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let handle = stdoutPipe.fileHandleForReading

                // Read progress updates
                while capturedProcess.isRunning {
                    guard let self = self, !self.cancelled else {
                        capturedProcess.terminate()
                        continuation.resume(throwing: QuickMotionError.exportFailed(reason: "Cancelled"))
                        return
                    }

                    if let data = try? handle.availableData, !data.isEmpty,
                       let output = String(data: data, encoding: .utf8) {
                        // Parse progress output (format: out_time_ms=123456)
                        if let match = output.range(of: "out_time_ms=([0-9]+)", options: .regularExpression),
                           let msString = output[match].split(separator: "=").last,
                           let ms = Double(msString) {
                            let currentTime = ms / 1_000_000
                            let fraction = min(1.0, currentTime / (capturedDuration / Double(speedMultiplier)))

                            if let progress = progress {
                                Task { @MainActor in
                                    progress(fraction)
                                }
                            }
                        }
                    }

                    Thread.sleep(forTimeInterval: 0.1)
                }

                capturedProcess.waitUntilExit()

                if capturedProcess.terminationStatus != 0 {
                    // Read stderr for error details
                    if let errorData = try? stderrPipe.fileHandleForReading.readToEnd(),
                       let errorString = String(data: errorData, encoding: .utf8) {
                        let lastLines = errorString.split(separator: "\n").suffix(3).joined(separator: "\n")
                        continuation.resume(throwing: QuickMotionError.exportFailed(reason: "FFmpeg failed: \(lastLines)"))
                    } else {
                        continuation.resume(throwing: QuickMotionError.exportFailed(reason: "FFmpeg failed with code \(capturedProcess.terminationStatus)"))
                    }
                    return
                }

                continuation.resume()
            }
        }

        self.process = nil
    }

    public func cancel() {
        cancelled = true
        process?.terminate()
    }
}
