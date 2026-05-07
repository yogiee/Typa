import SwiftUI
import AppKit

struct PlainTextEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let file: FileItem

    @State private var activeLine:    Int      = 0
    @State private var lineSegments:  [Int]    = [1]   // wraps per logical line
    @State private var scrollOffset:  CGFloat  = 0

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

// MARK: - Gutter view (wrap-aware)

// Each gutter row spans the full wrapped height of its logical line, so a
// logical line that wraps to N visual segments shows ONE line number followed
// by (N-1) lineHeights of empty gutter — matching the way VS Code, Sublime,
// Xcode, etc. render their gutters.
struct GutterView: View {
    let lineSegments: [Int]
    let activeLine:   Int
    let scrollOffset: CGFloat
    let lineHeight:   CGFloat
    let topInset:     CGFloat
    let fontSize:     CGFloat
    let accentColor:  Color
    let colorScheme:  ColorScheme

    var body: some View {
        // GeometryReader absorbs the proposed size without letting children's
        // intrinsic heights propagate upward — this is what was locking the
        // window minimum height to the editor's content height.
        GeometryReader { _ in
            VStack(spacing: 0) {
                ForEach(Array(lineSegments.enumerated()), id: \.offset) { i, segs in
                    Text("\(i + 1)")
                        .font(DesignTokens.font(fontSize - 2))
                        .foregroundStyle(
                            i == activeLine
                                ? accentColor
                                : DesignTokens.fgFaint(colorScheme)
                        )
                        // Line number sits in a single lineHeight cell aligned
                        // with the FIRST visual segment of the logical line.
                        .frame(width: 36, height: lineHeight, alignment: .trailing)
                        .padding(.trailing, 8)
                        // Wrapped continuation occupies the remaining height
                        // as empty gutter space.
                        .frame(height: CGFloat(max(segs, 1)) * lineHeight,
                               alignment: .top)
                }
            }
            .padding(.top, topInset)
            .offset(y: -scrollOffset)
            .allowsHitTesting(false)
        }
        .frame(width: 44)
        .clipped()
        .background(DesignTokens.bgElev(colorScheme))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignTokens.line(colorScheme))
                .frame(width: 0.5)
        }
    }
}

// MARK: - NSTextView wrapper

struct EditorNSTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize:             CGFloat
    var fontName:             String  = "JetBrains Mono"
    var lineHeightMultiplier: CGFloat = 1.0
    var isEditable:  Bool
    var focusMode:   Bool
    var accentColor: Color
    var colorScheme: ColorScheme
    /// External-driven scroll position (0..1). When set and different from
    /// the editor's current scroll fraction, the editor scrolls to it
    /// programmatically. Used by the split view to drive source-from-preview.
    var sourceScrollFraction: CGFloat? = nil

    var onCaretLineChange: ((Int, Int) -> Void)? = nil
    var onScrollChange:    ((CGFloat) -> Void)?  = nil
    var onScrollFraction:  ((CGFloat) -> Void)?  = nil
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
        tv.isEditable      = isEditable
        tv.isSelectable    = true
        tv.isRichText      = false
        tv.usesFindBar     = false
        tv.allowsUndo      = true
        tv.drawsBackground = false
        tv.textContainerInset    = NSSize(width: 20, height: 16)
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
        // Keep the coordinator's struct snapshot fresh so its delegate
        // callbacks (textDidChange, etc.) read the current bindings instead
        // of the stale ones captured at makeCoordinator time. Without this,
        // textDidChange after CMD+Z would read a stale parent.text and the
        // bulk-replace path below would resurrect the pre-undo content.
        context.coordinator.parent = self

        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = sel
            // tv.string = ... registers an undo whose target points back through
            // the SwiftUI binding setter. The undo manager dereferences a stale
            // pointer on CMD+Z → EXC_BAD_ACCESS. Drop those entries; cross-file /
            // external bulk replacements aren't user-undoable anyway.
            tv.undoManager?.removeAllActions()
        }
        applyStyle(tv)
        applyFocusMode(tv, activeLine: context.coordinator.activeLine)

        // Drive scroll position from outside (preview → source sync)
        if let f = sourceScrollFraction {
            context.coordinator.applyExternalScrollFraction(f, scrollView: scrollView)
        }

        DispatchQueue.main.async {
            context.coordinator.emitLineSegments()
        }
    }

    // MARK: Styling

    func applyStyle(_ tv: NSTextView) {
        let fg   = NSColor(colorScheme == .dark ? DesignTokens.fg(.dark) : DesignTokens.fg(.light))
        let font = DesignTokens.monoFont(size: fontSize, name: fontName)
        tv.font  = font
        tv.textColor = fg
        tv.insertionPointColor = NSColor(accentColor)

        let lh = DesignTokens.lineHeight(for: fontSize,
                                          fontName: fontName,
                                          multiplier: lineHeightMultiplier)
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = lh
        ps.maximumLineHeight = lh
        tv.defaultParagraphStyle = ps

        guard let ts = tv.textStorage else { return }
        let r = NSRange(location: 0, length: ts.length)
        ts.addAttribute(.font,            value: font, range: r)
        ts.addAttribute(.foregroundColor, value: fg,   range: r)
        ts.addAttribute(.paragraphStyle,  value: ps,   range: r)
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
        // Suppress own scroll-fraction emission for a brief window after a
        // programmatic scroll triggered by an external driver (preview → source).
        // Keeps the bidirectional sync from oscillating.
        var ignoreScrollUntil: Date = .distantPast
        // Last fraction we've already applied to the editor; used to skip
        // redundant programmatic scrolls when the same value comes around the
        // loop (e.g., source emitted X, state holds X, source receives X back).
        var lastAppliedFraction: CGFloat = .nan

        init(_ parent: EditorNSTextView) { self.parent = parent }

        // MARK: Delegate hooks

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string { parent.text = tv.string }
            updateCaretLine(tv)
            DispatchQueue.main.async { [weak self] in self?.emitLineSegments() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            updateCaretLine(tv)
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
            // Wrap may have changed; recompute segment counts.
            DispatchQueue.main.async { [weak self] in self?.emitLineSegments() }
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
