import SwiftUI

@main
struct TextPadApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("TextPad-NXG", id: "main") {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.settings.theme.colorScheme)
                .onAppear {
                    appState.loadSampleFiles()
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
