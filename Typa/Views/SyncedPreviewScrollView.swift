import SwiftUI
import AppKit

// An NSScrollView wrapper that accepts a 0..1 scroll fraction and drives
// its scroll position accordingly. Used in MarkdownSplitView to sync the
// preview pane with the source editor.
struct SyncedPreviewScrollView<Content: View>: NSViewRepresentable {

    var scrollFraction:      CGFloat
    var onHeightsChanged:    ((CGFloat, CGFloat) -> Void)?
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false

        let hostView = NSHostingView(rootView: content().frame(maxWidth: .infinity))
        hostView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostView

        // Make the hosting view expand to the scroll view's width
        NSLayoutConstraint.activate([
            hostView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.hostView   = hostView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Update content
        if let hv = context.coordinator.hostView as? NSHostingView<AnyView> {
            // Only way to update content is to replace; wrap in AnyView
            _ = hv  // suppress warning — we recreate via coordinator below
        }
        // Re-host content when it changes (source text changed)
        context.coordinator.updateContent(content())

        // Apply scroll fraction
        DispatchQueue.main.async {
            context.coordinator.applyScrollFraction(self.scrollFraction,
                                                     report: self.onHeightsChanged)
        }
    }

    // MARK: Coordinator

    @MainActor
    class Coordinator: NSObject {
        var parent: SyncedPreviewScrollView
        weak var scrollView: NSScrollView?
        var hostView: NSView?

        init(_ parent: SyncedPreviewScrollView) { self.parent = parent }

        func updateContent<C: View>(_ newContent: C) {
            guard let sv = scrollView else { return }
            // Replace the hosting view content by creating a new one if type matches
            // We use AnyView boxing to update
            let wrapped = AnyView(newContent.frame(maxWidth: .infinity))
            if let hv = hostView as? NSHostingView<AnyView> {
                hv.rootView = wrapped
            } else {
                let hv = NSHostingView(rootView: wrapped)
                hv.translatesAutoresizingMaskIntoConstraints = false
                sv.documentView = hv
                NSLayoutConstraint.activate([
                    hv.widthAnchor.constraint(equalTo: sv.contentView.widthAnchor)
                ])
                hostView = hv
            }
        }

        func applyScrollFraction(_ fraction: CGFloat,
                                 report: ((CGFloat, CGFloat) -> Void)?) {
            guard let sv = scrollView, let docView = sv.documentView else { return }
            let contentH = docView.frame.height
            let viewH    = sv.contentView.frame.height
            report?(contentH, viewH)
            let maxY = max(contentH - viewH, 0)
            let targetY = fraction * maxY
            sv.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            sv.reflectScrolledClipView(sv.contentView)
        }

        @objc func boundsChanged(_ notification: Notification) {
            guard let sv = scrollView, let docView = sv.documentView else { return }
            let contentH = docView.frame.height
            let viewH    = sv.contentView.frame.height
            parent.onHeightsChanged?(contentH, viewH)
        }
    }
}
