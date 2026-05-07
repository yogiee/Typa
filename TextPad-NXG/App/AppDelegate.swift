import AppKit

/// Hosts the `applicationShouldTerminate(_:)` hook so quitting the app with
/// unsaved changes prompts the user to Save / Discard / Cancel.
///
/// SwiftUI doesn't expose a "before terminate" closure, so we drop down to a
/// classic NSApplicationDelegate registered via `@NSApplicationDelegateAdaptor`
/// in `TextPadApp`. The reference to AppState is wired in once the first
/// window appears.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Borrowed from the SwiftUI scene after first window appears. Weak so
    /// we don't fight @Observable's own retention.
    weak var appState: AppState?

    /// Quit the app when the last window closes (matches the user's mental
    /// model for a single-window editor; without this the menu bar stays
    /// up and ⌘Q is required to actually exit).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state = appState else { return .terminateNow }
        let dirty = state.allFiles.filter { $0.isDirty }
        guard !dirty.isEmpty else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        if dirty.count == 1 {
            alert.messageText = "Do you want to save the changes to \(dirty[0].name)?"
        } else {
            alert.messageText = "You have \(dirty.count) unsaved files."
        }
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: dirty.count == 1 ? "Save" : "Save All")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:                       // Save / Save All
            return state.saveAllDirty() ? .terminateNow : .terminateCancel
        case .alertSecondButtonReturn:                      // Discard
            return .terminateNow
        default:                                            // Cancel
            return .terminateCancel
        }
    }
}
