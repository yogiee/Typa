import SwiftUI
import AppKit

struct MarkdownSplitView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let file: FileItem
    @State private var activeLine:     Int     = 0
    @State private var lineSegments:   [Int]   = [1]
    @State private var scrollOffset:   CGFloat = 0   // raw y for gutter
    @State private var scrollFraction: CGFloat = 0   // 0..1 for preview sync

    private var fontSize:   CGFloat { CGFloat(appState.settings.fontSize) }
    private var fontName:   String  { appState.settings.fontName }
    private var lineHeightMultiplier: CGFloat { CGFloat(appState.settings.lineHeightMultiplier) }
    private var lineHeight: CGFloat {
        DesignTokens.lineHeight(for: fontSize,
                                 fontName: fontName,
                                 multiplier: lineHeightMultiplier)
    }
    private var isVertical: Bool { appState.settings.splitOrientation == .vertical }

    var body: some View {
        Group {
            if isVertical {
                HStack(spacing: 0) {
                    sourcePane
                    divider
                    previewPane
                }
            } else {
                VStack(spacing: 0) {
                    sourcePane
                    divider
                    previewPane
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if let toast = appState.smartPasteToast {
                smartPasteToast(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(16)
            }
        }
        .animation(.easeOut(duration: 0.15), value: appState.smartPasteToast != nil)
    }

    // MARK: Source pane

    private var sourcePane: some View {
        VStack(spacing: 0) {
            mdSourceToolbar
            Divider().opacity(0.5)
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
                    sourceScrollFraction: appState.settings.syncScroll ? scrollFraction : nil,
                    findMatches:       appState.findOpen ? appState.findMatches : [],
                    currentMatchIndex: appState.findOpen ? appState.currentMatchIndex : -1,
                    findScrollTrigger: appState.findScrollTrigger,
                    onCaretLineChange: { line, _ in
                        activeLine = line
                    },
                    onScrollChange: { offset in
                        scrollOffset = offset
                    },
                    onScrollFraction: { f in
                        if appState.settings.syncScroll { scrollFraction = f }
                    },
                    onLineSegments: { segs in
                        lineSegments = segs
                    }
                )
            }
        }
        .background(DesignTokens.bgPane(colorScheme))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    private var mdSourceToolbar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.accentColor)
                    .frame(width: 5, height: 5)
                Text("Source")
                    .font(DesignTokens.font(11, weight: .medium))
                    .foregroundStyle(DesignTokens.fgMute(colorScheme))
            }
            .padding(.leading, 12)

            Spacer()

            ForEach(MdEdit.toolbar, id: \.self) { edit in
                Button {
                    apply(edit)
                } label: {
                    edit.iconView
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.fgSoft(colorScheme))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(edit.help)
            }
        }
        .frame(height: 36)
        .padding(.trailing, 8)
        .background(DesignTokens.bgElev(colorScheme))
    }

    /// Apply a markdown edit to the focused NSTextView, going through the
    /// shouldChangeText / replaceCharacters / didChangeText flow so the edit
    /// is registered as a proper undoable operation by NSTextView itself.
    private func apply(_ edit: MdEdit) {
        guard let tv = focusedTextView() else { return }
        edit.perform(on: tv)
    }

    /// Walk the responder chain of the key window to find an NSTextView. The
    /// markdown source NSTextView is normally the first responder when the
    /// user clicks a toolbar button (SwiftUI Buttons don't steal focus).
    private func focusedTextView() -> NSTextView? {
        guard let win = NSApp.keyWindow else { return nil }
        var responder: NSResponder? = win.firstResponder
        while let r = responder {
            if let tv = r as? NSTextView, tv.isEditable { return tv }
            responder = r.nextResponder
        }
        return nil
    }

    // MARK: Split divider

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.lineStrong(colorScheme))
            .frame(width: isVertical ? 0.5 : nil, height: isVertical ? nil : 0.5)
    }

    // MARK: Preview pane

    private var previewPane: some View {
        VStack(spacing: 0) {
            paneHeader("Preview")
            Divider().opacity(0.5)
            MarkdownWebView(
                source:            file.body,
                fontSize:          fontSize,
                lineLength:        Int(appState.settings.lineLength),
                accentColor:       appState.accentColor,
                colorScheme:       colorScheme,
                scrollFraction:    appState.settings.syncScroll ? scrollFraction : nil,
                onScrollFraction: { f in
                    if appState.settings.syncScroll { scrollFraction = f }
                },
                anchorToJump:      appState.activeAnchor,
                anchorJumpRequest: appState.anchorJumpCounter,
                findQuery:         appState.findOpen ? appState.findQuery : "",
                findMatchIndex:    appState.findOpen ? appState.currentMatchIndex : -1,
                findScrollTrigger: appState.findScrollTrigger
            )
        }
        .background(DesignTokens.bgPane(colorScheme).opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paneHeader(_ label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DesignTokens.fgFaint(colorScheme))
                .frame(width: 5, height: 5)
            Text(label)
                .font(DesignTokens.font(11, weight: .medium))
                .foregroundStyle(DesignTokens.fgMute(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(DesignTokens.bgElev(colorScheme))
    }

    // MARK: Smart paste toast

    private func smartPasteToast(_ label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.accentColor)
                .frame(width: 6, height: 6)
            Text("Smart paste · \(label)")
                .font(DesignTokens.font(12))
                .foregroundStyle(DesignTokens.fg(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(DesignTokens.bgElev(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: DesignTokens.shadowMd, radius: 12, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.line(colorScheme), lineWidth: 0.5))
    }
}
