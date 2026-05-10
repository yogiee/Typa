import SwiftUI
import AppKit

struct CodeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let file: FileItem

    @State private var activeLine:    Int     = 0
    @State private var lineSegments:  [Int]   = [1]
    @State private var scrollOffset:  CGFloat = 0

    private var fontSize:   CGFloat { CGFloat(appState.settings.fontSize) }
    private var fontName:   String  { appState.settings.fontName }
    private var lineHeightMultiplier: CGFloat { CGFloat(appState.settings.lineHeightMultiplier) }
    private var lineHeight: CGFloat {
        DesignTokens.lineHeight(for: fontSize,
                                 fontName: fontName,
                                 multiplier: lineHeightMultiplier)
    }
    private var lang:       String  { file.lang ?? SyntaxHighlighter.langFromName(file.name) ?? "js" }

    var body: some View {
        HStack(spacing: 0) {
            if appState.settings.showLineNumbers {
                GutterView(
                    lineSegments: lineSegments,
                    activeLine:   activeLine,
                    scrollOffset: scrollOffset,
                    lineHeight:   lineHeight,
                    topInset:     16,
                    fontSize:     fontSize,
                    accentColor:  appState.accentColor,
                    colorScheme:  colorScheme
                )
            }
            CodeEditorNSTextView(
                text: Binding(
                    get: { file.body },
                    set: { appState.updateBody($0, for: file.id) }
                ),
                lang:        lang,
                fontSize:    fontSize,
                fontName:    fontName,
                lineHeightMultiplier: lineHeightMultiplier,
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
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.bgPane(colorScheme))
    }
}

// MARK: - Style fingerprint

private struct StyleStamp: Equatable {
    var fontSize:    CGFloat
    var fontName:    String
    var multiplier:  CGFloat
    var colorScheme: ColorScheme
    var accentColor: Color
    var lang:        String

    static func make(from p: CodeEditorNSTextView) -> StyleStamp {
        StyleStamp(fontSize: p.fontSize, fontName: p.fontName,
                   multiplier: p.lineHeightMultiplier,
                   colorScheme: p.colorScheme, accentColor: p.accentColor,
                   lang: p.lang)
    }
}

// MARK: - Code editor (NSTextView + syntax highlighting + wrap-aware gutter signals)

struct CodeEditorNSTextView: NSViewRepresentable {
    @Binding var text: String
    var lang:                 String
    var fontSize:             CGFloat
    var fontName:             String  = "JetBrains Mono"
    var lineHeightMultiplier: CGFloat = 1.0
    var accentColor: Color
    var colorScheme: ColorScheme
    var findMatches:       [NSRange] = []
    var currentMatchIndex: Int      = -1
    var findScrollTrigger: Int      = -1

    var onCaretLineChange: ((Int, Int) -> Void)? = nil
    var onScrollChange:    ((CGFloat) -> Void)?  = nil
    var onLineSegments:    (([Int]) -> Void)?    = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false

        let tv = NSTextView()
        tv.delegate        = context.coordinator
        tv.isEditable      = true
        tv.isSelectable    = true
        tv.isRichText      = false
        tv.usesFindBar     = false
        tv.allowsUndo      = true
        tv.drawsBackground = false
        tv.textContainerInset      = NSSize(width: 20, height: 16)
        tv.isVerticallyResizable   = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.postsFrameChangedNotifications = true

        scrollView.documentView = tv
        context.coordinator.textView = tv

        applyStyle(tv)
        tv.string = text
        applyHighlighting(tv)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrolled(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.frameChanged(_:)),
            name: NSView.frameDidChangeNotification,
            object: tv
        )

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
            DispatchQueue.main.async {
                context.coordinator.emitLineSegments()
            }
        }

        // Skip O(n) attribute walk + full tokenization pass when nothing changed.
        // applyHighlighting always follows applyStyle because style resets all
        // foreground colors to the base color, erasing syntax token colors.
        let newStamp = StyleStamp.make(from: self)
        let styleChanged = newStamp != context.coordinator.lastStyleStamp
        if textChanged || styleChanged {
            applyStyle(tv)
            applyHighlighting(tv)
            context.coordinator.lastStyleStamp = newStamp
        }

        applyFindHighlights(tv, context.coordinator)
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
                tv.setSelectedRange(r)
                DispatchQueue.main.async { tv.showFindIndicator(for: r) }
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

    func applyHighlighting(_ tv: NSTextView) {
        guard let ts = tv.textStorage else { return }
        let colors = SyntaxColors.forScheme(colorScheme)
        let lines  = tv.string.components(separatedBy: "\n")
        var charOffset = 0
        ts.beginEditing()
        for line in lines {
            let tokens = SyntaxHighlighter.tokenize(line, lang: lang)
            var tokenOff = charOffset
            for token in tokens {
                let len = (token.text as NSString).length
                if len > 0, let color = colors.color(for: token.type) {
                    let range = NSRange(location: tokenOff, length: len)
                    if range.location + range.length <= ts.length {
                        ts.addAttribute(.foregroundColor, value: NSColor(color), range: range)
                    }
                }
                tokenOff += len
            }
            charOffset += (line as NSString).length + 1
        }
        ts.endEditing()
    }

    // MARK: Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorNSTextView
        weak var textView: NSTextView?
        var activeLine: Int = 0
        var lastFindMatches: [NSRange] = []
        var lastFindIndex:   Int       = -2
        var lastFindTrigger: Int       = -2
        fileprivate var lastStyleStamp: StyleStamp? = nil

        init(_ parent: CodeEditorNSTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string { parent.text = tv.string }
            parent.applyHighlighting(tv)
            updateCaretLine(tv)
            restoreTypingAttributes(tv)
            DispatchQueue.main.async { [weak self] in self?.emitLineSegments() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            updateCaretLine(tv)
            // NSTextView resets typingAttributes on selection change. Re-apply
            // so font, paragraph style, and baseline offset stay correct on
            // empty lines and after cursor movement.
            restoreTypingAttributes(tv)
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
            let ps = NSMutableParagraphStyle()
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
            guard let clipView = notification.object as? NSClipView else { return }
            parent.onScrollChange?(clipView.bounds.origin.y)
        }

        @objc func frameChanged(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.emitLineSegments()
                if let tv = self.textView {
                    self.updateActiveLineHighlight(tv, line: self.activeLine)
                }
            }
        }

        private func updateCaretLine(_ tv: NSTextView) {
            let src     = tv.string as NSString
            let pos     = tv.selectedRange().location
            let safeLen = min(pos, src.length)
            let prefix  = src.substring(with: NSRange(location: 0, length: safeLen))
            let line    = prefix.components(separatedBy: "\n").count - 1
            let count   = tv.string.components(separatedBy: "\n").count
            activeLine  = line
            parent.onCaretLineChange?(line, count)
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
                    segs = 1
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
        }

        private func activeLineRect(_ tv: NSTextView, line: Int) -> CGRect {
            let lh  = DesignTokens.lineHeight(for: parent.fontSize,
                                                fontName: parent.fontName,
                                                multiplier: parent.lineHeightMultiplier)
            let top = tv.textContainerInset.height

            let lines = (tv.string as NSString).components(separatedBy: "\n")
            guard line >= 0 && line < lines.count else { return .zero }
            var startPos = 0
            for i in 0..<line {
                startPos += (lines[i] as NSString).length + 1
            }
            let lineLen = (lines[line] as NSString).length
            let lineCharRange = NSRange(location: startPos, length: lineLen)

            if let lm = tv.layoutManager, lm.numberOfGlyphs > 0 {
                let glyphRange = lm.glyphRange(forCharacterRange: lineCharRange,
                                                actualCharacterRange: nil)
                var totalRect: CGRect = .null
                if glyphRange.length == 0 {
                    let glyphIdx = lm.glyphIndexForCharacter(at: min(startPos,
                                                                      max(0, (tv.string as NSString).length - 1)))
                    if glyphIdx != NSNotFound {
                        totalRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
                    }
                } else {
                    var g = glyphRange.location
                    let upper = glyphRange.upperBound
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
            return CGRect(x: 0, y: top + CGFloat(line) * lh,
                          width: tv.bounds.width, height: lh)
        }
    }
}
