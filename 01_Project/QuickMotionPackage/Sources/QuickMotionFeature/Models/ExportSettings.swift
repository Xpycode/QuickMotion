import AVFoundation
import Foundation

// MARK: - Export Quality

/// Quality preset for export encoding
public enum ExportQuality: String, CaseIterable, Sendable {
    /// HEVC encoding - smaller file size, good quality
    case fast = "Fast (HEVC)"
    /// ProRes encoding - larger file size, best quality for editing
    case quality = "Quality (ProRes)"
}

// MARK: - Export Resolution

/// Resolution preset for export
public enum ExportResolution: String, CaseIterable, Sendable {
    /// Match source video resolution
    case match = "Match Source"
    /// 1920x1080
    case hd1080p = "1080p HD"
    /// 3840x2160
    case uhd4k = "4K UHD"
}

// MARK: - Export Frame Rate

/// Frame rate preset for export
public enum ExportFrameRate: String, CaseIterable, Sendable {
    /// Match source video frame rate
    case match = "Match Source"
    /// 24 fps - cinematic
    case fps24 = "24 fps"
    /// 30 fps - standard
    case fps30 = "30 fps"
    /// 60 fps - smooth
    case fps60 = "60 fps"

    // TODO: v1.1 - Implement AVMutableVideoComposition for frame rate control
    /// Numeric frame rate value, nil means match source
    public var frameRate: Float? {
        switch self {
        case .match: return nil
        case .fps24: return 24.0
        case .fps30: return 30.0
        case .fps60: return 60.0
        }
    }
}

// MARK: - Export Settings

/// Configuration for timelapse video export
public struct ExportSettings: Sendable {
    /// Quality/codec preset
    public var quality: ExportQuality

    /// Output resolution
    public var resolution: ExportResolution

    /// Output frame rate
    public var frameRate: ExportFrameRate

    /// Optional custom output URL (if nil, user will be prompted)
    public var outputURL: URL?

    /// Whether to include audio in the output (usually false for timelapse)
    public var includeAudio: Bool

    /// Creates export settings with default values
    public init(
        quality: ExportQuality = .fast,
        resolution: ExportResolution = .match,
        frameRate: ExportFrameRate = .match,
        outputURL: URL? = nil,
        includeAudio: Bool = false
    ) {
        self.quality = quality
        self.resolution = resolution
        self.frameRate = frameRate
        self.outputURL = outputURL
        self.includeAudio = includeAudio
    }
}

// MARK: - AVFoundation Mapping

extension ExportSettings {
    /// Returns the appropriate AVAssetExportPresetName for the current settings
    public var avExportPreset: String {
        switch quality {
        case .fast:
            // HEVC presets based on resolution
            switch resolution {
            case .match:
                return AVAssetExportPresetHEVCHighestQuality
            case .hd1080p:
                return AVAssetExportPresetHEVC1920x1080
            case .uhd4k:
                return AVAssetExportPresetHEVC3840x2160
            }
        case .quality:
            // ProRes presets based on resolution
            switch resolution {
            case .match:
                return AVAssetExportPresetAppleProRes422LPCM
            case .hd1080p:
                return AVAssetExportPresetAppleProRes422LPCM
            case .uhd4k:
                return AVAssetExportPresetAppleProRes422LPCM
            }
        }
    }

    /// Returns the appropriate AVFileType for the current quality setting
    public var outputFileType: AVFileType {
        switch quality {
        case .fast:
            return .mp4
        case .quality:
            return .mov
        }
    }

    /// Returns the file extension for the current quality setting
    public var fileExtension: String {
        switch quality {
        case .fast:
            return "mp4"
        case .quality:
            return "mov"
        }
    }
}

// MARK: - File Size Estimation

extension ExportSettings {
    /// Estimates the output file size based on input size, speed multiplier, and resolution
    /// - Parameters:
    ///   - inputSize: Size of the source video in bytes
    ///   - speedMultiplier: The timelapse speed multiplier (e.g., 10x)
    ///   - sourceResolution: The source video resolution (width, height) for scaling calculations.
    ///                       Pass nil to skip resolution-based adjustments.
    /// - Returns: Estimated output file size in bytes
    public func estimatedFileSize(
        inputSize: Int64,
        speedMultiplier: Double,
        sourceResolution: (width: Int, height: Int)? = nil
    ) -> Int64 {
        guard speedMultiplier > 0 else { return 0 }

        // Base estimate based on codec compression ratios
        let baseEstimate: Double
        switch quality {
        case .fast:
            // HEVC typically compresses to ~70% of source codec at same quality
            // HEVC is more efficient than most source codecs (H.264, etc.)
            baseEstimate = Double(inputSize) / speedMultiplier * 0.7

        case .quality:
            // ProRes 422 is roughly 8-15x larger than HEVC for the same content
            // Using 8.0 as a conservative multiplier
            baseEstimate = Double(inputSize) / speedMultiplier * 8.0
        }

        // Apply resolution scaling factor
        let resolutionFactor = calculateResolutionFactor(sourceResolution: sourceResolution)

        return Int64(baseEstimate * resolutionFactor)
    }

    /// Calculates the resolution scaling factor based on source and target resolution
    /// - Parameter sourceResolution: The source video resolution (width, height)
    /// - Returns: A multiplier to apply to the file size estimate
    private func calculateResolutionFactor(sourceResolution: (width: Int, height: Int)?) -> Double {
        guard let source = sourceResolution else {
            // No source resolution provided, assume no scaling
            return 1.0
        }

        // Determine if source is larger than 1080p (1920x1080 = 2,073,600 pixels)
        // Using 1920x1080 as the threshold for "larger than 1080p"
        let sourcePixels = source.width * source.height
        let hd1080pPixels = 1920 * 1080  // ~2.07M pixels
        let uhd4kPixels = 3840 * 2160    // ~8.29M pixels

        let sourceIsLargerThan1080p = sourcePixels > hd1080pPixels
        let sourceIs4kOrLarger = sourcePixels >= uhd4kPixels

        switch resolution {
        case .match:
            // No scaling, use original resolution
            return 1.0

        case .hd1080p:
            if sourceIs4kOrLarger {
                // Downscaling from 4K to 1080p: 1080p is ~1/4 the pixels of 4K
                return 0.25
            } else if sourceIsLargerThan1080p {
                // Downscaling from something between 1080p and 4K
                return Double(hd1080pPixels) / Double(sourcePixels)
            } else {
                // Source is 1080p or smaller, no significant change expected
                return 1.0
            }

        case .uhd4k:
            if sourceIs4kOrLarger {
                // Source is already 4K or larger, no upscaling benefit to file size
                return 1.0
            } else {
                // Source is smaller than 4K - upscaling doesn't increase data,
                // but encoding at higher resolution may slightly increase size
                // However, we don't artificially inflate the estimate
                return 1.0
            }
        }
    }

    /// Formats a file size in bytes to a human-readable string
    /// - Parameter bytes: File size in bytes
    /// - Returns: Formatted string (e.g., "125 MB")
    public static func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Export Method Selection

extension ExportSettings {
    /// Determines whether to use the fast sample buffer exporter
    ///
    /// The SampleBufferExporter uses AVAssetReader/Writer with frame skipping:
    /// - Hardware-accelerated decoding of ALL frames (fast on Apple Silicon)
    /// - Only ENCODES every Nth frame (the slow part)
    /// - At 16x speed, encodes 1/16th of frames = ~16x faster export
    ///
    /// This is used for speed > 2x. Below 2x, standard export is fine.
    public func shouldUseSampleBufferExporter(speedMultiplier: Double) -> Bool {
        return speedMultiplier > 2.0
    }

    /// Legacy: kept for backwards compatibility but no longer used
    public func shouldUseFrameDecimation(speedMultiplier: Double) -> Bool {
        return false
    }
}
