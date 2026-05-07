import SwiftUI

@main
struct TypaApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let updater = UpdaterService.shared   // starts Sparkle

    var body: some Scene {
        Window("Typa", id: "main") {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.settings.theme.colorScheme)
                .onAppear {
                    appDelegate.appState = appState

                    // Drain any files that arrived via "Open With" before the
                    // window appeared (application(_:open:) fires early).
                    let hadPendingFiles = !appDelegate.pendingURLs.isEmpty
                    appDelegate.openPendingURLs()

                    if hadPendingFiles {
                        // A real file was opened — hydrate recents for the
                        // sidebar but skip the sample-file seed.
                        appState.hydrateRecentFiles()
                    } else if appState.recentURLs.isEmpty && appState.files.isEmpty {
                        // First-run: seed the sidebar with sample content so
                        // the empty state isn't completely barren.
                        appState.loadSampleFiles()
                    } else {
                        appState.hydrateRecentFiles()
                    }
                }
        }
        .defaultSize(width: 1200, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
