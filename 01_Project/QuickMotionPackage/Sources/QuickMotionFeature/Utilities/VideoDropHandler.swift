import Foundation
import UniformTypeIdentifiers

/// Unified drop handling for video files across the application
public enum VideoDropHandler {
    /// Supported video UTTypes for drag-drop and file picker
    public static let supportedTypes: [UTType] = [
        .movie,
        .video,
        .mpeg4Movie,
        .quickTimeMovie
    ]

    /// Allowed content types for file picker dialogs
    public static var allowedContentTypes: [UTType] {
        supportedTypes
    }

    /// Extracts a video URL from drop providers
    /// - Parameter providers: NSItemProvider array from drop operation
    /// - Returns: First valid video URL found, or nil
    public static func loadURL(from providers: [NSItemProvider]) async -> URL? {
        guard let provider = providers.first else { return nil }

        for type in supportedTypes {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let url = try? await loadURL(from: provider, typeIdentifier: type.identifier) {
                    return url
                }
            }
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Loads URL from a provider for a specific type identifier
    private static func loadURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                // Try direct URL representation
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                // Try Data representation converted to URL
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
