import SwiftUI
import AppKit

// Configures the NSWindow on first appear: removes title, enables
// full-size content view so our custom TitleBarView covers the frame.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 700, height: 400)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
