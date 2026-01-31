import AVFoundation
import Foundation

// MARK: - Source Size Estimation & Disk Space Validation

extension ExportSession {
    /// Estimates the source file size for disk space calculations
    /// - Returns: Estimated source file size in bytes
    func estimateSourceSize() async -> Int64 {
        // Try to get actual file size if source is a URL asset
        if let urlAsset = sourceAsset as? AVURLAsset {
            let fileURL = urlAsset.url
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                return fileSize
            }
        }

        // Fallback: estimate based on duration and typical bitrate
        // Use conservative estimate: 20 Mbps for HD video
        do {
            let duration = try await sourceAsset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            let estimatedBitrate: Double = 20_000_000 // 20 Mbps
            return Int64(seconds * estimatedBitrate / 8)
        } catch {
            // Last resort: assume 500 MB
            return 500_000_000
        }
    }

    /// Checks if there's enough disk space for the estimated output file
    /// - Parameter estimatedSize: Estimated output file size in bytes
    /// - Throws: QuickMotionError.insufficientDiskSpace if not enough space
    func checkDiskSpace(estimatedSize: Int64) throws {
        let directory = outputURL.deletingLastPathComponent()

        do {
            let resourceValues = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

            // Use volumeAvailableCapacityForImportantUsage which accounts for purgeable space
            if let availableCapacity = resourceValues.volumeAvailableCapacityForImportantUsage {
                // Add 10% buffer for safety
                let requiredSpace = Int64(Double(estimatedSize) * 1.1)

                if availableCapacity < requiredSpace {
                    throw QuickMotionError.insufficientDiskSpace(
                        required: requiredSpace,
                        available: availableCapacity
                    )
                }
            }
        } catch let error as QuickMotionError {
            throw error
        } catch {
            // If we can't check disk space, proceed anyway and let the export fail naturally
            // This is better than blocking exports when the check fails
        }
    }
}
