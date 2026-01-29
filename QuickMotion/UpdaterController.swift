import Foundation
import Sparkle

/// Manages Sparkle auto-updates for the app
final class UpdaterController: ObservableObject {
    let updaterController: SPUStandardUpdaterController

    init() {
        // Start the updater automatically on app launch
        // It will check for updates based on user preferences
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}
