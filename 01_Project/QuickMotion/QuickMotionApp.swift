import SwiftUI
import Sparkle
import QuickMotionFeature

@main
struct QuickMotionApp: App {
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updaterController.updater)
            }

            // File menu commands
            CommandGroup(after: .newItem) {
                Button("Open...") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Export...") {
                    NotificationCenter.default.post(name: .exportFile, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}

// Note: Notification.Name.openFile and .exportFile are defined in QuickMotionFeature

/// Menu item that triggers Sparkle's update check
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: checkForUpdatesViewModel.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

/// View model that observes Sparkle's updater state
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
