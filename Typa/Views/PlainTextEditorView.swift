import SwiftUI
import AppKit

struct PlainTextEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let file: FileItem

    @State private var activeLine:    Int       = 0
    // Document-space center Y of each logical line's first visual fragment,
    // emitted straight from the layout manager. Drawing numbers from these true
    // positions (instead of a cumulative lineHeight estimate) keeps them aligned
    // with content even when lines are taller than lineHeight (CJK, emoji).
    @State private var lineCenters:   [CGFloat] = []
    @State private var scrollOffset:  CGFloat   = 0

    private var fontSize:   CGFloat { CGFloat(appState.settings.fontSize) }
    private var fontName:   String  { appState.settings.fontName }
    private var lineHeightMultiplier: CGFloat { CGFloat(appState.settings.lineHeightMultiplier) }
    private var lineHeight: CGFloat {
        DesignTokens.lineHeight(for: fontSize,
                                 fontName: fontName,
                                 multiplier: lineHeightMultiplier)
    }

    var body: some View {
        HStack(spacing: 0) {
            if appState.settings.showLineNumbers {
                GutterView(
                    lineCenters:  lineCenters,
                    activeLine:   activeLine,
                    scrollOffset: scrollOffset,
                    lineHeight:   lineHeight,
                    fontSize:     fontSize,
                    accentColor:  appState.accentColor,
                    colorScheme:  colorScheme
                )
            }
            EditorNSTextView(
                text: Binding(
                    get: { file.body },
                    set: { appState.updateBody($0, for: file.id) }
                ),
                fontSize:    fontSize,
                fontName:    fontName,
                lineHeightMultiplier: lineHeightMultiplier,
                isEditable:  true,
                focusMode:   appState.settings.focusMode,
                accentColor: appState.accentColor,
                colorScheme: colorScheme,
                findMatches:       appState.findOpen ? appState.findMatches : [],
                currentMatchIndex: appState.findOpen ? appState.currentMatchIndex : -1,
                findScrollTrigger: appState.findScrollTrigger,
                onCaretLineChange: { line, _ in
                    activeLine = line
                },
                onScrollChange: { offset in
                    scrollOffset = offset
                },
                onLineCenters: { centers in
                    lineCenters = centers
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.bgPane(colorScheme))
    }
}

// MARK: - Gutter view (Canvas-based, draw-only-visible)

// Canvas renders only the line numbers that fall within the visible viewport.
// Previously a ForEach/VStack created one Text view per logical line, which
// forced SwiftUI to build O(total-lines) nodes on every scroll and cursor move.
// Now we iterate the array once, skip rows above/below the viewport, and only
// call context.resolve() for the ~30-50 visible rows.
struct GutterView: View {
    // Document-space center Y of each logical line's first visual fragment,
    // straight from the layout manager. Numbers are drawn at these exact
    // positions so they track real text — including lines taller than
    // lineHeight (CJK/emoji) and wrapped lines — with no cumulative drift.
    let lineCenters:    [CGFloat]
    let activeLine:     Int
    let scrollOffset:   CGFloat
    let lineHeight:     CGFloat   // only used as an off-screen cull margin
    let fontSize:       CGFloat
    let accentColor:    Color
    let colorScheme:    ColorScheme

    // Grows with the actual line count so numbers are never clipped.
    // Minimum 3 digits; expands to 4, 5, … as needed (log files, etc.).
    private var gutterWidth: CGFloat {
        let digits = max(String(lineCenters.count).count, 3)
        let font = NSFont(name: "JetBrains Mono", size: max(fontSize - 2, 8))
            ?? NSFont.monospacedSystemFont(ofSize: max(fontSize - 2, 8), weight: .regular)
        let charW = ("0" as NSString).size(withAttributes: [.font: font]).width
        // digit columns + 8pt leading gap + 13pt trailing gap + 0.5pt border
        return ceil(charW * CGFloat(digits)) + 21.5
    }

    var body: some View {
        Canvas { context, size in
            let textRightX = size.width - 13
            let margin = lineHeight   // cull rows comfortably outside the viewport

            for (i, center) in lineCenters.enumerated() {
                let drawY = center - scrollOffset

                // Centers are monotonically increasing — skip rows above the
                // viewport, stop once we've passed the bottom.
                if drawY + margin < 0 { continue }
                if drawY - margin > size.height { break }

                let isActive = (i == activeLine)
                let label = Text(verbatim: String(i + 1))
                    .font(DesignTokens.font(fontSize - 2))
                    .foregroundStyle(isActive ? accentColor : DesignTokens.fgFaint(colorScheme))

                let resolved = context.resolve(label)
                context.draw(resolved,
                             at: CGPoint(x: textRightX, y: drawY),
                             anchor: UnitPoint(x: 1.0, y: 0.5))
            }
        }
        .allowsHitTesting(false)
        .frame(width: gutterWidth)
        .clipped()
        .background(DesignTokens.bgElev(colorScheme))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignTokens.line(colorScheme))
                .frame(width: 0.5)
        }
    }
}

// MARK: - Style fingerprint

// Compared before every applyStyle call. If nothing changed, we skip the O(n)
// attribute walk over the entire text storage — the biggest per-keystroke cost.
private struct StyleStamp: Equatable {
    var fontSize:    CGFloat
    var fontName:    String
    var multiplier:  CGFloat
    var colorScheme: ColorScheme
    var accentColor: Color

    static func make(from p: EditorNSTextView) -> StyleStamp {
        StyleStamp(fontSize: p.fontSize, fontName: p.fontName,
                   multiplier: p.lineHeightMultiplier,
                   colorScheme: p.colorScheme, accentColor: p.accentColor)
    }
}

// MARK: - Active-line-aware text view

// Paints the active-line highlight in drawBackground(in:) instead of a CALayer.
// A CALayer highlight requires wantsLayer = true, which makes the text view
// layer-backed; layer-backed NSTextViews fail to repaint runs that shift Y on
// an edit (e.g. text below a newly inserted newline) until the next edit dirties
// that region — the "invisible line on Return" bug. Drawing in drawBackground
// keeps the view non-layer-backed so normal incremental redraw works.
final class ActiveLineTextView: NSTextView {
    var activeLineRect: CGRect = .zero
    var activeLineColor: NSColor = .clear

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard activeLineRect.height > 0, activeLineRect.intersects(rect) else { return }
        activeLineColor.setFill()
        activeLineRect.fill()
    }
}

// MARK: - NSTextView wrapper

struct EditorNSTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize:             CGFloat
    var fontName:             String  = "JetBrains Mono"
    var lineHeightMultiplier: CGFloat = 1.0
    var isEditable:         Bool
    var focusMode:          Bool
    var markdownFormatting: Bool = false
    var accentColor: Color
    var colorScheme: ColorScheme
    /// External-driven scroll position (0..1). When set and different from
    /// the editor's current scroll fraction, the editor scrolls to it
    /// programmatically. Used by the split view to drive source-from-preview.
    var sourceScrollFraction: CGFloat? = nil

    var findMatches:       [NSRange] = []
    var currentMatchIndex: Int      = -1
    var findScrollTrigger: Int      = -1

    var onCaretLineChange:  ((Int, Int) -> Void)? = nil
    var onScrollChange:     ((CGFloat) -> Void)?  = nil
    var onScrollFraction:   ((CGFloat) -> Void)?  = nil
    // Document-space center Y of each logical line's first visual fragment.
    // GutterView draws the line numbers at these exact positions.
    var onLineCenters:      (([CGFloat]) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false

        let tv = ActiveLineTextView()
        tv.delegate        = context.coordinator
        tv.isEditable      = isEditable
        tv.isSelectable    = true
        tv.isRichText      = false
        tv.usesFindBar     = false
        tv.allowsUndo      = true
        tv.drawsBackground = false
        tv.textContainerInset    = NSSize(width: 12, height: 16)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.postsFrameChangedNotifications = true

        scrollView.documentView = tv
        context.coordinator.textView = tv

        applyStyle(tv)
        tv.string = text

        // Scroll observation (gutter sync)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrolled(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        // Frame observation (wrap recalculation when window resizes)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.frameChanged(_:)),
            name: NSView.frameDidChangeNotification,
            object: tv
        )

        // Initial line-segment emission once layout has settled
        DispatchQueue.main.async {
            context.coordinator.emitLineCenters()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let tv = scrollView.documentView as? NSTextView else { return }

        let textChanged = tv.string != text
        if textChanged {
            let sel = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = sel
            tv.undoManager?.removeAllActions()
            // Layout needs to settle before line-segment counts are accurate.
            DispatchQueue.main.async {
                context.coordinator.emitLineCenters()
            }
        }

        // Skip the O(n) attribute walk when font/size/scheme/accent are unchanged.
        let newStamp = StyleStamp.make(from: self)
        let styleChanged = newStamp != context.coordinator.lastStyleStamp
        if textChanged || styleChanged {
            applyStyle(tv)
            context.coordinator.lastStyleStamp = newStamp
        }

        // Focus mode: re-apply when toggled, when the active line moved (while
        // focus is on), or when style changed (applyStyle reset foreground colors).
        let focusModeChanged = context.coordinator.lastFocusModeActive != focusMode
        let focusLineChanged = context.coordinator.activeLine != context.coordinator.lastFocusActiveLine
        let needsFocusUpdate = focusModeChanged
            || (focusMode && (styleChanged || textChanged || focusLineChanged))
        if needsFocusUpdate {
            applyFocusMode(tv, activeLine: context.coordinator.activeLine)
            context.coordinator.lastFocusModeActive = focusMode
            context.coordinator.lastFocusActiveLine = context.coordinator.activeLine
        }

        applyFindHighlights(tv, context.coordinator)

        if let f = sourceScrollFraction {
            context.coordinator.applyExternalScrollFraction(f, scrollView: scrollView)
        }
    }

    func applyFindHighlights(_ tv: NSTextView, _ coord: Coordinator) {
        guard let ts = tv.textStorage else { return }
        guard coord.lastFindMatches != findMatches
           || coord.lastFindIndex   != currentMatchIndex
           || coord.lastFindTrigger != findScrollTrigger else { return }
        coord.lastFindMatches = findMatches
        coord.lastFindIndex   = currentMatchIndex
        coord.lastFindTrigger = findScrollTrigger

        ts.beginEditing()
        ts.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: ts.length))
        for (i, range) in findMatches.enumerated() {
            guard range.location + range.length <= ts.length else { continue }
            let color: NSColor = i == currentMatchIndex
                ? .systemOrange.withAlphaComponent(0.55)
                : .systemYellow.withAlphaComponent(0.35)
            ts.addAttribute(.backgroundColor, value: color, range: range)
        }
        ts.endEditing()

        if currentMatchIndex >= 0, currentMatchIndex < findMatches.count {
            let r = findMatches[currentMatchIndex]
            if r.location + r.length <= ts.length {
                tv.scrollRangeToVisible(r)
                let notifyScroll = onScrollChange
                DispatchQueue.main.async { [weak tv] in
                    guard let tv else { return }
                    if let sv = tv.enclosingScrollView {
                        notifyScroll?(sv.contentView.bounds.origin.y)
                    }
                    tv.setSelectedRange(r)
                    tv.showFindIndicator(for: r)
                }
            }
        }
    }

    // MARK: Styling

    func applyStyle(_ tv: NSTextView) {
        let fg   = NSColor(colorScheme == .dark ? DesignTokens.fg(.dark) : DesignTokens.fg(.light))
        let font = DesignTokens.monoFont(size: fontSize, name: fontName)
        tv.font  = font
        tv.textColor = fg
        tv.insertionPointColor = NSColor(accentColor)

        let lh        = DesignTokens.lineHeight(for: fontSize,
                                                  fontName: fontName,
                                                  multiplier: lineHeightMultiplier)
        let naturalLH = NSLayoutManager().defaultLineHeight(for: font)
        // min=max=lh places extra space ABOVE the glyph (text sits at the
        // bottom of a tall cell). Raise the glyph upward by half the extra
        // space to achieve equal padding above and below.
        let baselineOff: CGFloat = (lh - naturalLH) / 2

        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = lh
        ps.maximumLineHeight = lh
        tv.defaultParagraphStyle = ps

        guard let ts = tv.textStorage else { return }
        let r = NSRange(location: 0, length: ts.length)
        ts.beginEditing()
        ts.addAttribute(.font,            value: font,        range: r)
        ts.addAttribute(.foregroundColor, value: fg,          range: r)
        ts.addAttribute(.paragraphStyle,  value: ps,          range: r)
        ts.addAttribute(.baselineOffset,  value: baselineOff, range: r)
        ts.endEditing()
        tv.setNeedsDisplay(tv.bounds)

        tv.typingAttributes = [
            .font:            font,
            .foregroundColor: fg,
            .paragraphStyle:  ps,
            .baselineOffset:  baselineOff
        ]
    }

    func applyFocusMode(_ tv: NSTextView, activeLine: Int) {
        guard let ts = tv.textStorage else { return }
        let normalFg = NSColor(colorScheme == .dark ? DesignTokens.fg(.dark) : DesignTokens.fg(.light))
        // tertiaryLabelColor is the system "noticeably-dimmed" text color
        // — automatically adapts between light/dark and produces a clear
        // contrast vs the active line. fgFaint was too subtle.
        let dimFg    = NSColor.tertiaryLabelColor

        ts.beginEditing()
        if focusMode {
            ts.addAttribute(.foregroundColor, value: dimFg,
                            range: NSRange(location: 0, length: ts.length))
            // Use the SAME splitter as updateCaretLine to avoid Unicode
            // line-break vs "\n"-only mismatches.
            let lines = (tv.string as NSString).components(separatedBy: "\n")
            if activeLine >= 0 && activeLine < lines.count {
                var loc = 0
                for i in 0..<activeLine {
                    loc += (lines[i] as NSString).length + 1
                }
                let lineLen = (lines[activeLine] as NSString).length
                let len = activeLine < lines.count - 1 ? lineLen + 1 : lineLen
                let r = NSRange(location: loc, length: len)
                if r.location + r.length <= ts.length {
                    ts.addAttribute(.foregroundColor, value: normalFg, range: r)
                }
            }
        } else {
            ts.addAttribute(.foregroundColor, value: normalFg,
                            range: NSRange(location: 0, length: ts.length))
        }
        ts.endEditing()
    }

    // MARK: Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorNSTextView
        weak var textView: NSTextView?
        var activeLine: Int = 0
        var lastFindMatches: [NSRange] = []
        var lastFindIndex:   Int       = -2
        var lastFindTrigger: Int       = -2
        var ignoreScrollUntil:   Date    = .distantPast
        var lastAppliedFraction: CGFloat = .nan
        // Style fingerprint — guards the O(n) applyStyle attribute walk.
        fileprivate var lastStyleStamp: StyleStamp? = nil
        // Focus-mode guards — avoid O(n) dim pass when nothing relevant changed.
        var lastFocusModeActive: Bool? = nil
        var lastFocusActiveLine: Int   = -2

        init(_ parent: EditorNSTextView) { self.parent = parent }

        // MARK: Delegate hooks

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string { parent.text = tv.string }
            updateCaretLine(tv)
            restoreTypingAttributes(tv)
            // SwiftUI hosts this NSTextView in a layer-backed tree, and AppKit's
            // incremental damage-rect calc mis-computes the shifted region when
            // line heights are non-uniform (e.g. inserting a Latin-height empty
            // line above a taller CJK line) — leaving glyph runs below the edit
            // unrepainted ("invisible line"). Repaint the whole visible region so
            // every on-screen glyph is redrawn at its current Y. Bounded by the
            // viewport, so cheap.
            tv.setNeedsDisplay(tv.visibleRect)
            DispatchQueue.main.async { [weak self] in self?.emitLineCenters() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            updateCaretLine(tv)
            // NSTextView resets typingAttributes on every selection change,
            // deriving them from the character at the insertion point. Re-apply
            // the full set so font, paragraph style, and baseline offset are
            // always correct — especially on empty lines with no surrounding chars.
            restoreTypingAttributes(tv)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let sel = textView.selectedRange()
            let str = textView.string as NSString

            // Markdown-only behaviours (apply before the selection guard below)
            if parent.markdownFormatting {
                if commandSelector == #selector(NSTextView.insertNewline(_:)) {
                    return handleMarkdownEnter(textView, str: str, sel: sel)
                }
                // Tab with no selection → 4 spaces
                if commandSelector == #selector(NSTextView.insertTab(_:)), sel.length == 0 {
                    textView.insertText("    ", replacementRange: sel)
                    return true
                }
            }

            // Selection indent/dedent (all modes)
            guard sel.length > 0 else { return false }
            let lineRange = str.lineRange(for: sel)

            if commandSelector == #selector(NSTextView.insertTab(_:)) {
                let block = str.substring(with: lineRange)
                let indented = block.components(separatedBy: "\n").map {
                    $0.isEmpty ? $0 : "    " + $0
                }.joined(separator: "\n")
                if textView.shouldChangeText(in: lineRange, replacementString: indented) {
                    textView.textStorage?.replaceCharacters(in: lineRange, with: indented)
                    textView.didChangeText()
                    textView.setSelectedRange(NSRange(location: lineRange.location,
                                                     length: (indented as NSString).length))
                }
                return true
            }

            if commandSelector == #selector(NSTextView.insertBacktab(_:)) {
                let block = str.substring(with: lineRange)
                let dedented = block.components(separatedBy: "\n").map { line -> String in
                    var s = line; var n = 0
                    while n < 4, s.hasPrefix(" ") { s = String(s.dropFirst()); n += 1 }
                    return s
                }.joined(separator: "\n")
                if dedented != block,
                   textView.shouldChangeText(in: lineRange, replacementString: dedented) {
                    textView.textStorage?.replaceCharacters(in: lineRange, with: dedented)
                    textView.didChangeText()
                    textView.setSelectedRange(NSRange(location: lineRange.location,
                                                     length: (dedented as NSString).length))
                }
                return true
            }

            return false
        }

        // Returns the list/blockquote prefix of a line, or nil if none.
        private func detectListPrefix(_ line: String) -> String? {
            if line.hasPrefix("> ") { return "> " }
            for marker in ["- ", "* ", "+ "] {
                if line.hasPrefix(marker) { return marker }
            }
            // Ordered: "1. ", "12. " etc.
            var i = line.startIndex
            while i < line.endIndex && line[i].isNumber { i = line.index(after: i) }
            if i > line.startIndex, i < line.endIndex {
                let rest = String(line[i...])
                if rest.hasPrefix(". ") { return String(line[..<i]) + ". " }
            }
            return nil
        }

        private func nextOrderedPrefix(from prefix: String) -> String? {
            guard prefix.hasSuffix(". ") else { return nil }
            let numPart = String(prefix.dropLast(2))
            guard let n = Int(numPart) else { return nil }
            return "\(n + 1). "
        }

        private func handleMarkdownEnter(_ tv: NSTextView, str: NSString, sel: NSRange) -> Bool {
            let cursorPos = sel.location
            let lineRange = str.lineRange(for: NSRange(location: cursorPos, length: 0))
            let lineText  = str.substring(with: lineRange)
            let line      = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

            guard let prefix = detectListPrefix(line) else { return false }

            let afterPrefix = String(line.dropFirst(prefix.count))
            let hasContent  = !afterPrefix.trimmingCharacters(in: .whitespaces).isEmpty

            if !hasContent {
                // Empty item — erase the prefix, leave cursor on the bare empty line.
                // Deferred so NSTextView finishes event processing before we mutate.
                let prefixRange = NSRange(location: lineRange.location,
                                         length: (prefix as NSString).length)
                DispatchQueue.main.async { tv.insertText("", replacementRange: prefixRange) }
                return true
            }

            // Continue list: insert newline + prefix (incremented for ordered lists).
            // Deferred for the same reason — avoids stale display below the insertion.
            let nextPrefix  = nextOrderedPrefix(from: prefix) ?? prefix
            let insertRange = NSRange(location: cursorPos, length: 0)
            DispatchQueue.main.async { tv.insertText("\n" + nextPrefix, replacementRange: insertRange) }
            return true
        }

        func textView(_ tv: NSTextView,
                      shouldChangeTextIn range: NSRange,
                      replacementString string: String?) -> Bool {
            guard parent.markdownFormatting,
                  let ch = string, ch.count == 1,
                  tv.selectedRange().length == 0 else { return true }

            let docStr   = tv.string as NSString
            let nextChar = range.location < docStr.length
                ? docStr.substring(with: NSRange(location: range.location, length: 1))
                : ""

            // Skip-over: typing a closing char when that same char is already next
            let skipSet: Set<String> = [")", "]", "`"]
            if skipSet.contains(ch) && nextChar == ch {
                DispatchQueue.main.async { tv.setSelectedRange(NSRange(location: range.location + 1, length: 0)) }
                return false
            }

            // Auto-close pairs (no " — smart-quote substitution interferes)
            let pairs: [String: String] = ["(": ")", "[": "]", "`": "`"]
            guard let closing = pairs[ch], nextChar != closing else { return true }

            // For backtick: don't auto-close when the preceding char is also a backtick.
            // This lets the user type ``` (code fence) after `` without triggering a
            // second auto-close — skip-over handles the 2nd keystroke, this handles the 3rd.
            if ch == "`" {
                let prevChar = range.location > 0
                    ? docStr.substring(with: NSRange(location: range.location - 1, length: 1))
                    : ""
                if prevChar == "`" { return true }
            }

            DispatchQueue.main.async {
                tv.insertText(ch + closing, replacementRange: range)
                tv.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            }
            return false
        }

        private func restoreTypingAttributes(_ tv: NSTextView) {
            let font      = DesignTokens.monoFont(size: parent.fontSize, name: parent.fontName)
            let fg        = NSColor(parent.colorScheme == .dark
                ? DesignTokens.fg(.dark) : DesignTokens.fg(.light))
            let lh        = DesignTokens.lineHeight(for: parent.fontSize,
                                                     fontName: parent.fontName,
                                                     multiplier: parent.lineHeightMultiplier)
            let naturalLH = NSLayoutManager().defaultLineHeight(for: font)
            let baselineOff: CGFloat = (lh - naturalLH) / 2
            let ps        = NSMutableParagraphStyle()
            ps.minimumLineHeight = lh
            ps.maximumLineHeight = lh
            tv.typingAttributes = [
                .font:            font,
                .foregroundColor: fg,
                .paragraphStyle:  ps,
                .baselineOffset:  baselineOff
            ]
        }

        @objc func scrolled(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let docView  = clipView.documentView else { return }
            let offset = clipView.bounds.origin.y
            parent.onScrollChange?(offset)

            // If we just programmatically scrolled to match an external value,
            // the resulting boundsDidChange should not bounce back out.
            if Date() < ignoreScrollUntil { return }

            let maxScroll = max(docView.frame.height - clipView.bounds.height, 1)
            let fraction  = min(max(offset / maxScroll, 0), 1)
            parent.onScrollFraction?(fraction)
        }

        // MARK: External-driven scroll (preview → source)

        func applyExternalScrollFraction(_ fraction: CGFloat,
                                          scrollView: NSScrollView) {
            // Skip if the same fraction came around the loop (own emission).
            if !lastAppliedFraction.isNaN
                && abs(lastAppliedFraction - fraction) < 0.001 { return }
            guard let docView = scrollView.documentView else { return }
            let maxScroll = max(docView.frame.height - scrollView.contentView.bounds.height, 0)
            let targetY   = fraction * maxScroll
            let currentY  = scrollView.contentView.bounds.origin.y
            // No-op if already at target — this is the common case when our
            // own emitted fraction is reflected back to us.
            if abs(targetY - currentY) < 0.5 {
                lastAppliedFraction = fraction
                return
            }
            ignoreScrollUntil   = Date().addingTimeInterval(0.15)
            lastAppliedFraction = fraction
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        @objc func frameChanged(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.emitLineCenters()
                // Refresh the active-line highlight so it tracks the new
                // line height immediately (e.g. when multiplier changes).
                if let tv = self.textView {
                    self.updateActiveLineHighlight(tv, line: self.activeLine)
                }
            }
        }

        // MARK: Caret tracking

        private func updateCaretLine(_ tv: NSTextView) {
            let src     = tv.string as NSString
            let pos     = tv.selectedRange().location
            let safeLen = min(pos, src.length)
            let prefix  = src.substring(with: NSRange(location: 0, length: safeLen))
            let line    = prefix.components(separatedBy: "\n").count - 1
            let count   = tv.string.components(separatedBy: "\n").count
            activeLine  = line
            parent.onCaretLineChange?(line, count)
            if parent.focusMode { parent.applyFocusMode(tv, activeLine: line) }
            updateActiveLineHighlight(tv, line: line)
        }

        // MARK: Line centers (layout-manager ground truth)

        func emitLineCenters() {
            guard let tv = textView else { return }
            parent.onLineCenters?(computeLineCenters(tv))
        }

        // Center Y (document space, incl. textContainerInset) of each logical
        // line's FIRST visual fragment, read straight from the layout manager.
        // The gutter draws number i at centers[i], so numbers track real text
        // regardless of per-line height (CJK/emoji taller than lineHeight) or
        // wrapping — eliminating the cumulative-estimate drift.
        private func computeLineCenters(_ tv: NSTextView) -> [CGFloat] {
            let src          = tv.string as NSString
            let inset        = tv.textContainerInset.height
            let logicalCount = max(tv.string.components(separatedBy: "\n").count, 1)

            guard let lm = tv.layoutManager, tv.textContainer != nil else {
                let lh = DesignTokens.lineHeight(for: parent.fontSize,
                                                  fontName: parent.fontName,
                                                  multiplier: parent.lineHeightMultiplier)
                return (0..<logicalCount).map { inset + (CGFloat($0) + 0.5) * lh }
            }

            var centers: [CGFloat] = []
            centers.reserveCapacity(logicalCount)
            var charIdx = 0

            while charIdx <= src.length {
                let lineRange = src.lineRange(for: NSRange(location: charIdx, length: 0))

                let rect: CGRect
                if src.length == 0 || lineRange.location >= src.length {
                    // Empty document or the phantom empty line after a trailing
                    // newline — neither has glyphs; use the extra line fragment.
                    rect = lm.extraLineFragmentRect
                } else {
                    let glyphRange = lm.glyphRange(forCharacterRange: lineRange,
                                                    actualCharacterRange: nil)
                    let gi = min(glyphRange.location, max(0, lm.numberOfGlyphs - 1))
                    rect = lm.numberOfGlyphs > 0
                        ? lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
                        : lm.extraLineFragmentRect
                }
                centers.append(rect.minY + rect.height / 2 + inset)

                if lineRange.upperBound >= src.length { break }
                charIdx = lineRange.upperBound
            }

            // String ends with a newline: the loop appended a center for the line
            // holding the final "\n" but not the phantom empty line after it.
            while centers.count < logicalCount {
                let extra = lm.extraLineFragmentRect
                centers.append(extra.minY + extra.height / 2 + inset)
            }
            return centers
        }

        // MARK: Active-line highlight (wrap-aware)

        private func updateActiveLineHighlight(_ tv: NSTextView, line: Int) {
            guard let alt = tv as? ActiveLineTextView else { return }

            let frame = activeLineRect(tv, line: line)
            let prev  = alt.activeLineRect

            alt.activeLineColor = (tv.effectiveAppearance.name == .darkAqua
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.035))
            alt.activeLineRect = frame.height > 0 ? frame : .zero
            // Repaint both the old and new highlight rows so the previous one
            // is cleared and the new one drawn.
            if prev.height > 0 { tv.setNeedsDisplay(prev) }
            if frame.height > 0 { tv.setNeedsDisplay(frame) }
        }

        private func activeLineRect(_ tv: NSTextView, line: Int) -> CGRect {
            let lh  = DesignTokens.lineHeight(for: parent.fontSize,
                                                fontName: parent.fontName,
                                                multiplier: parent.lineHeightMultiplier)
            let top = tv.textContainerInset.height

            // Compute char range for the active logical line
            let lines = (tv.string as NSString).components(separatedBy: "\n")
            guard line >= 0 && line < lines.count else { return .zero }
            var startPos = 0
            for i in 0..<line {
                startPos += (lines[i] as NSString).length + 1
            }
            let lineLen = (lines[line] as NSString).length
            let lineCharRange = NSRange(location: startPos, length: lineLen)

            // Cursor is on the phantom empty line that follows a trailing newline.
            // No glyph exists for it — lm.glyphIndexForCharacter would return the
            // preceding \n glyph (same line as the previous row), making activeLineDocY
            // point one row too high and corrupting the drift calculation. Use the
            // direct formula instead so drift = 0 for this case.
            let src = tv.string as NSString
            if startPos >= src.length {
                return CGRect(x: 0, y: top + CGFloat(line) * lh,
                              width: tv.bounds.width, height: lh)
            }

            // Try the layout manager for an accurate union rect across wrapped fragments
            if let lm = tv.layoutManager, lm.numberOfGlyphs > 0 {
                let glyphRange = lm.glyphRange(forCharacterRange: lineCharRange,
                                                actualCharacterRange: nil)
                var totalRect: CGRect = .null
                var g = glyphRange.location
                let upper = max(glyphRange.upperBound, g + 1)

                if glyphRange.length == 0 {
                    // Empty logical line — query the line fragment directly
                    let glyphIdx = lm.glyphIndexForCharacter(at: min(startPos,
                                                                      max(0, src.length - 1)))
                    if glyphIdx != NSNotFound {
                        totalRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
                    }
                } else {
                    while g < upper {
                        var eff = NSRange(location: 0, length: 0)
                        let r = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &eff)
                        totalRect = totalRect.isNull ? r : totalRect.union(r)
                        if eff.upperBound > g { g = eff.upperBound } else { break }
                    }
                }

                if !totalRect.isNull {
                    return CGRect(x: 0,
                                  y: totalRect.minY + top,
                                  width: tv.bounds.width,
                                  height: totalRect.height)
                }
            }

            // Fallback: fixed-height calculation (no wrap awareness)
            return CGRect(x: 0, y: top + CGFloat(line) * lh,
                          width: tv.bounds.width, height: lh)
        }
    }
}
