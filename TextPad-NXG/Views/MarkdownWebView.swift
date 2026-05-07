import SwiftUI
import WebKit
import AppKit

// WKWebView-backed markdown preview. Mirrors MacDown's renderer pipeline:
// markdown → HTML → load via loadHTMLString → WebKit handles layout & scroll.
//
// Solves several issues at once vs. the SwiftUI block renderer:
//   • Native cross-block text selection
//   • No SwiftUI layout cost for huge docs (no LazyVStack churn)
//   • No window auto-resize (WKWebView is sized to its frame, full stop)
//   • Smooth scrolling
struct MarkdownWebView: NSViewRepresentable {

    let source:      String
    let fontSize:    CGFloat
    let lineLength:  Int
    let accentColor: Color
    let colorScheme: ColorScheme

    /// Optional scroll fraction (0..1). If supplied, the preview is driven
    /// from this value (used for split-view source → preview sync).
    var scrollFraction: CGFloat? = nil

    /// Called when the user scrolls the preview directly (preview → source).
    var onScrollFraction: ((CGFloat) -> Void)? = nil

    /// Anchor (heading slug) the preview should scroll to. Paired with
    /// `anchorJumpRequest` (a counter) so repeated clicks on the same
    /// heading always re-trigger the scroll.
    var anchorToJump:      String? = nil
    var anchorJumpRequest: Int     = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "tpScroll")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.setValue(false, forKey: "drawsBackground") // honor body bg from CSS
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = false
        // Open links in the default browser, not inside the web view
        wv.uiDelegate = context.coordinator

        context.coordinator.webView = wv
        context.coordinator.lastSource = source
        context.coordinator.lastCSSKey = cssKey
        wv.loadHTMLString(fullPageHTML(), baseURL: nil)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        // Refresh the coordinator's struct snapshot so its delegate callbacks
        // see the current bindings.
        context.coordinator.parent = self

        let cssKeyNow = cssKey
        if cssKeyNow != context.coordinator.lastCSSKey {
            // Theme/font/accent/length change → CSS needs updating, full reload.
            // didFinish restores scroll position from lastPreviewFraction (or
            // source-driven scrollFraction if syncScroll is on).
            context.coordinator.lastCSSKey = cssKeyNow
            context.coordinator.lastSource = source
            wv.loadHTMLString(fullPageHTML(), baseURL: nil)
        } else if source != context.coordinator.lastSource {
            // Only the markdown source changed → swap body via JS. Avoids the
            // navigation flash and preserves scroll position natively.
            context.coordinator.lastSource = source
            let bodyHTML = MarkdownEngine.renderBodyHTML(source)
            // Use JSONEncoder to safely escape arbitrary HTML for embedding
            // as a JS string literal — no manual quote/backslash juggling.
            if let data = try? JSONEncoder().encode([bodyHTML]),
               let jsArray = String(data: data, encoding: .utf8) {
                wv.evaluateJavaScript("window.tpReplaceBody(\(jsArray)[0]);",
                                      completionHandler: nil)
            }
        } else if let f = scrollFraction {
            context.coordinator.applyScroll(fraction: f)
        }

        // Anchor jump (sidebar outline click). Counter-based so repeated
        // clicks on the same heading still trigger a re-scroll.
        if anchorJumpRequest != context.coordinator.lastAnchorRequest,
           let anchor = anchorToJump {
            context.coordinator.lastAnchorRequest = anchorJumpRequest
            if let data = try? JSONEncoder().encode([anchor]),
               let jsArray = String(data: data, encoding: .utf8) {
                wv.evaluateJavaScript(
                    "document.getElementById(\(jsArray)[0])?.scrollIntoView({behavior:'smooth',block:'start'});",
                    completionHandler: nil
                )
            }
        }
    }

    private func fullPageHTML() -> String {
        MarkdownEngine.renderHTML(
            source,
            colorScheme: colorScheme,
            fontSize: fontSize,
            lineLength: lineLength,
            accentHex: accentColor.hexString
        )
    }

    /// Hash of the CSS-affecting inputs. When this changes, we must reload
    /// the page; when only `source` differs, we can swap body HTML in place.
    private var cssKey: String {
        "\(colorScheme)|\(fontSize)|\(lineLength)|\(accentColor.hexString)"
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        weak var webView: WKWebView?
        var lastSource: String = ""           // last source we rendered
        var lastCSSKey: String = ""           // last CSS-affecting input set
        var lastPreviewFraction: CGFloat = 0  // user's last reading position
        var lastAnchorRequest: Int = 0        // last anchor-jump counter we acted on
        var ignorePreviewScrollUntil: Date = .distantPast

        init(_ parent: MarkdownWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // After every reload, restore the scroll position. If syncScroll
            // is on, use the source-driven fraction; otherwise stay where the
            // user was reading before the edit.
            let f = parent.scrollFraction ?? lastPreviewFraction
            applyScroll(fraction: f)
        }

        func applyScroll(fraction: CGFloat) {
            guard let wv = webView else { return }
            // Suppress the JS scroll → native callback for a brief window so
            // we don't ricochet back into the source pane.
            ignorePreviewScrollUntil = Date().addingTimeInterval(0.15)
            wv.evaluateJavaScript("window.tpSetScrollFraction(\(fraction))", completionHandler: nil)
        }

        // Open external links in the default browser
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // Receive scroll fraction posted from the page
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "tpScroll",
                  let f = message.body as? Double else { return }
            // Always remember where the user last was — this is what we
            // restore to after a reload so live preview doesn't snap to top.
            lastPreviewFraction = CGFloat(f)
            if Date() < ignorePreviewScrollUntil { return }
            parent.onScrollFraction?(CGFloat(f))
        }
    }
}
