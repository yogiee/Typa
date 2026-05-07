import SwiftUI

@main
struct TextPadApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let updater = UpdaterService.shared   // starts Sparkle

    var body: some Scene {
        Window("TextPad-NXG", id: "main") {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.settings.theme.colorScheme)
                .onAppear {
                    // Hand the AppDelegate a reference so its
                    // applicationShouldTerminate hook can check for unsaved
                    // changes before the app quits.
                    appDelegate.appState = appState

                    if appState.recentURLs.isEmpty && appState.files.isEmpty {
                        // First-run: seed the sidebar with sample content so
                        // the empty state isn't completely barren. Subsequent
                        // launches restore the user's actual recent files.
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
                .frame(width: 480)
        }
    }
}
