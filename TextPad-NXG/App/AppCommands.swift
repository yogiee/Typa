import SwiftUI

struct AppCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") {
                appState.newFile()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open…") {
                appState.openFilePanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                appState.saveActive()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState.activeFile == nil)

            Button("Save As…") {
                appState.saveActiveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(appState.activeFile == nil)
        }

        CommandMenu("View") {
            Button(appState.sidebarOpen ? "Hide Sidebar" : "Show Sidebar") {
                appState.toggleSidebar()
            }
            .keyboardShortcut("1", modifiers: .command)

            Divider()

            Button("Quick Switcher") {
                appState.qsOpen = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Find") {
                appState.findOpen = true
                appState.replaceMode = false
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find & Replace") {
                appState.findOpen = true
                appState.replaceMode = true
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }

        CommandMenu("Markdown") {
            Button(appState.activeMdMode == .read ? "Switch to Edit Mode" : "Switch to Read Mode") {
                appState.toggleMdMode()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!appState.isMd)
        }
    }
}
