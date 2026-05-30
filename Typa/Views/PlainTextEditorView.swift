import SwiftUI
import AppKit

struct PlainTextEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let file: FileItem

    @State private var activeLine:     Int      = 0
    @State private var lineSegments:  [Int]    = [1]   // wraps per logical line
    @State private var scrollOffset:  CGFloat  = 0
    @State private var activeLineDocY: CGFloat = -1    // layout-manager Y; -1 = unset

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
                    lineSegments:   lineSegments,
                    activeLine:     activeLine,
                    scrollOffset:   scrollOffset,
                    activeLineDocY: activeLineDocY,
                    lineHeight:     lineHeight,
                    topInset:       16,
                    fontSize:       fontSize,
                    accentColor:    appState.accentColor,
                    colorScheme:    colorScheme
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
                onLineSegments: { segs in
                    lineSegments = segs
                },
                onActiveLineDocY: { y in
                    activeLineDocY = y
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
    let lineSegments:   [Int]
    let activeLine:     Int
    let scrollOffset:   CGFloat
    // Exact Y of the active line's top in NSTextView document coordinates.
    // Derived from the layout manager via the same lineFragmentRect the
    // active-line CALayer uses, so the number and highlight never drift apart
    // even when lineSegments-based cumulative heights are slightly off.
    // Negative sentinel (-1) means the value hasn't been set yet; falls back
    // to the cumulative estimate in that case.
    var activeLineDocY: CGFloat = -1   // -1 = sentinel, fall back to cumulative estimate
    let lineHeight:     CGFloat
    let topInset:       CGFloat
    let fontSize:       CGFloat
    let accentColor:    Color
    let colorScheme:    ColorScheme

    // Grows with the actual line count so numbers are never clipped.
    // Minimum 3 digits; expands to 4, 5, … as needed (log files, etc.).
    private var gutterWidth: CGFloat {
        let digits = max(String(lineSegments.count).count, 3)
        let font = NSFont(name: "JetBrains Mono", size: max(fontSize - 2, 8))
            ?? NSFont.monospacedSystemFont(ofSize: max(fontSize - 2, 8), weight: .regular)
        let charW = ("0" as NSString).size(withAttributes: [.font: font]).width
        // digit columns + 8pt leading gap + 13pt trailing gap + 0.5pt border
        return ceil(charW * CGFloat(digits)) + 21.5
    }

    var body: some View {
        Canvas { context, size in
            let textRightX = size.width - 13

            // Pre-compute the cumulative Y for the active line using the same
            // lineSegments array that the rest of the drawing loop uses. Then
            // compare it against the layout manager's exact Y (activeLineDocY)
            // to get a drift value. Applying drift uniformly to every number
            // keeps them in sequential order while shifting the whole column to
            // match actual text positions — even when lineSegments has missed
            // some wrapped lines and accumulated error.
            var activeCumY: CGFloat = topInset - scrollOffset
            let activeIdx = min(max(activeLine, 0), lineSegments.count)
            for i in 0..<activeIdx {
                activeCumY += CGFloat(max(lineSegments[i], 1)) * lineHeight
            }
            let drift: CGFloat = activeLineDocY >= 0
                ? (activeLineDocY - scrollOffset - activeCumY)
                : 0

            var cumY: CGFloat = topInset - scrollOffset

            for (i, segs) in lineSegments.enumerated() {
                let rowHeight = CGFloat(max(segs, 1)) * lineHeight
                let drawTop = cumY + drift

                // Skip rows fully above the viewport — just advance the cursor
                if drawTop + rowHeight <= 0 {
                    cumY += rowHeight
                    continue
                }
                // Stop once we've passed the bottom of the viewport
                if drawTop >= size.height { break }

                let isActive = (i == activeLine)
                let label = Text(verbatim: String(i + 1))
                    .font(DesignTokens.font(fontSize - 2))
                    .foregroundStyle(isActive ? accentColor : DesignTokens.fgFaint(colorScheme))

                let resolved = context.resolve(label)
                context.draw(resolved,
                             at: CGPoint(x: textRightX, y: drawTop + lineHeight / 2),
                             anchor: UnitPoint(x: 1.0, y: 0.5))

                cumY += rowHeight
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
    var onLineSegments:     (([Int]) -> Void)?    = nil
    // Exact Y of the active line's top in NSTextView document coordinates,
    // derived from lineFragmentRect. Used by GutterView so the active line
    // number and the CALayer highlight always draw from the same source.
    var onActiveLineDocY:   ((CGFloat) -> Void)?  = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false

        let tv = NSTextView()
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
            context.coordinator.emitLineSegments()
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
                context.coordinator.emitLineSegments()
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
            // Combine line-segment emission with scroll-to-cursor in one async
            // block so both land in the same render cycle. This ensures the new
            // last line is visible after pressing Enter at the bottom of the file.
            DispatchQueue.main.async { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.emitLineSegments()
                tv.scrollRangeToVisible(tv.selectedRange())
            }
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
                self.emitLineSegments()
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

        // MARK: Line segments (wrap-aware)

        func emitLineSegments() {
            guard let tv = textView else { return }
            let segs = computeLineSegments(tv)
            parent.onLineSegments?(segs)
        }

        private func computeLineSegments(_ tv: NSTextView) -> [Int] {
            let logical = tv.string.components(separatedBy: "\n")
            let logicalCount = max(logical.count, 1)

            guard let lm = tv.layoutManager, lm.numberOfGlyphs > 0 else {
                return Array(repeating: 1, count: logicalCount)
            }

            let src = tv.string as NSString
            var counts: [Int] = []
            counts.reserveCapacity(logicalCount)
            var charIdx = 0

            while charIdx <= src.length {
                let lineRange = src.lineRange(for: NSRange(location: charIdx, length: 0))
                let glyphRange = lm.glyphRange(forCharacterRange: lineRange,
                                                actualCharacterRange: nil)

                var segs = 0
                var g = glyphRange.location
                let upper = glyphRange.upperBound
                if upper == g {
                    segs = 1   // empty line still occupies one visual line
                } else {
                    while g < upper {
                        var eff = NSRange(location: 0, length: 0)
                        _ = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &eff)
                        segs += 1
                        if eff.upperBound > g { g = eff.upperBound } else { break }
                    }
                }
                counts.append(max(segs, 1))

                if lineRange.upperBound >= src.length { break }
                charIdx = lineRange.upperBound
            }

            // If the string ends with a trailing newline, lineRange iteration above
            // doesn't append a row for the final empty line — add it.
            if logical.count > counts.count {
                counts.append(contentsOf: Array(repeating: 1,
                                                count: logical.count - counts.count))
            }
            return counts
        }

        // MARK: Active-line highlight (wrap-aware)

        private func updateActiveLineHighlight(_ tv: NSTextView, line: Int) {
            tv.wantsLayer = true
            tv.layer?.sublayers?.removeAll(where: { $0.name == "activeLineHL" })

            let frame = activeLineRect(tv, line: line)
            guard frame.height > 0 else { return }

            let hl = CALayer()
            hl.name = "activeLineHL"
            hl.frame = frame
            hl.backgroundColor = (tv.effectiveAppearance.name == .darkAqua
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.035)).cgColor
            tv.layer?.insertSublayer(hl, at: 0)

            // Emit the exact document-space Y so GutterView can draw the active
            // line number at the identical position rather than relying on the
            // lineSegments cumulative estimate (which drifts on wrapped lines).
            parent.onActiveLineDocY?(frame.origin.y)
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
                                                                      max(0, (tv.string as NSString).length - 1)))
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
