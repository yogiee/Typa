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
                        // A real file was opened via Open With — hydrate recents,
                        // don't also open a blank file.
                        appState.hydrateRecentFiles()
                    } else {
                        // Normal launch: populate recents list, then open a blank
                        // document so the user lands directly in the editor.
                        appState.hydrateRecentFiles()
                        appState.newFile()
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
