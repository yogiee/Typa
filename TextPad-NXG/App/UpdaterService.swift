@preconcurrency import Sparkle
import Foundation

/// Sparkle wrapper. Mirrors the IPMSGX / WallP pattern.
///
/// Update modes (persisted in UserDefaults so the choice survives launches
/// without bloating AppSettings):
///   0 = auto-update — check + download + install automatically
///   1 = download updates, ask before installing
///   2 = disabled — no automatic checking
@Observable
@MainActor
final class UpdaterService {
    @MainActor static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController
    private let modeKey = "tp.updateMode"

    var updateMode: Int {
        get { UserDefaults.standard.integer(forKey: modeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: modeKey)
            applyUpdateMode(newValue)
        }
    }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        applyUpdateMode(UserDefaults.standard.integer(forKey: modeKey))
    }

    /// Triggered by the "Check for updates" button in Settings → About.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private func applyUpdateMode(_ mode: Int) {
        let updater = controller.updater
        switch mode {
        case 0:  // auto-update
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
        case 1:  // download, ask to install
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = false
        default: // disabled
            updater.automaticallyChecksForUpdates = false
            updater.automaticallyDownloadsUpdates = false
        }
    }
}
