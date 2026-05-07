import SwiftUI
import AppKit

struct TitleBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings

    // Measured at runtime to match the actual traffic-light center Y
    @State private var rowHeight: CGFloat = 30

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            topRow
            Divider().opacity(0.5)
            tabRow
            Divider().opacity(0.7)
        }
        .background(DesignTokens.bgElev(colorScheme))
        .onAppear {
            // Defer one run-loop cycle so WindowConfigurator's fullSizeContentView
            // is applied before we read the button position.
            DispatchQueue.main.async { measureRowHeight() }
        }
    }

    private func measureRowHeight() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let close = window.standardWindowButton(.closeButton),
              let content = window.contentView else { return }
        let btnInContent = close.convert(close.bounds, to: content)
        // NSHostingView (SwiftUI root) is flipped — Y is already top-down.
        let centerYFromTop = content.isFlipped
            ? btnInContent.midY
            : content.frame.height - btnInContent.midY
        // clamp to sane range so a bad reading can't break the layout
        let measured = min(max(ceil(centerYFromTop * 2), 26), 52)
        if abs(rowHeight - measured) > 0.5 { rowHeight = measured }
    }

    // MARK: Top row

    private var topRow: some View {
        HStack(alignment: .center, spacing: 0) {
            // Traffic lights space (window controls live here via NSWindow)
            Color.clear.frame(width: 80, height: rowHeight)

            // Sidebar toggle
            Button {
                appState.toggleSidebar()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(appState.sidebarOpen
                        ? appState.accentColor
                        : DesignTokens.fgMute(colorScheme))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: rowHeight)
            .help("Toggle Sidebar ⌘1")

            Spacer()

            // Centered title
            if let file = appState.activeFile {
                HStack(spacing: 4) {
                    Text(file.name)
                        .font(DesignTokens.font(13, weight: .medium))
                        .foregroundStyle(DesignTokens.fg(colorScheme))
                    if file.isDirty {
                        Text("• Edited")
                            .font(DesignTokens.font(11))
                            .foregroundStyle(DesignTokens.fgMute(colorScheme))
                    } else {
                        Text("— \(file.folder)")
                            .font(DesignTokens.font(13))
                            .foregroundStyle(DesignTokens.fgMute(colorScheme))
                    }
                }
            } else {
                Text("TextPad-NXG")
                    .font(DesignTokens.font(13, weight: .medium))
                    .foregroundStyle(DesignTokens.fgMute(colorScheme))
            }

            Spacer()

            // Right actions
            HStack(spacing: 2) {
                if appState.isMd {
                    mdModeControl
                }
                if appState.isRtf {
                    rtfToolbarToggle
                }
                toolbarBtn(systemImage: "magnifyingglass", help: "Find ⌘F") {
                    appState.findOpen = true
                    appState.replaceMode = false
                }
                themeToggleBtn
                toolbarBtn(systemImage: "gearshape", help: "Preferences ⌘,") {
                    openSettings()
                }
            }
            .frame(height: rowHeight)
            .padding(.trailing, 12)
        }
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: Tab row

    private var tabRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(appState.openTabIds, id: \.self) { id in
                        if let file = appState.files[id] {
                            tabView(file: file, isActive: id == appState.activeTabId) {
                                appState.openFile(id: id)
                            }
                        }
                    }
                    // + new tab button
                    Button {
                        appState.newFile()
                    } label: {
                        Text("+")
                            .font(DesignTokens.font(16))
                            .foregroundStyle(DesignTokens.fgMute(colorScheme))
                            .frame(width: 32, height: 34)
                    }
                    .buttonStyle(.plain)
                    .help("New File")
                }
            }
            .frame(height: 34)

            if appState.settings.smartPaste {
                smartPasteChip
            }
        }
        .background(DesignTokens.bgTab(colorScheme))
    }

    private func tabView(file: FileItem, isActive: Bool, onSelect: @escaping () -> Void) -> some View {
        ZStack(alignment: .trailing) {
            // Full-area tap target for tab switching
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    kindChip(file.displayKind, kind: file.kind)
                    Text(file.name)
                        .font(DesignTokens.font(12, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? DesignTokens.fg(colorScheme) : DesignTokens.fgMute(colorScheme))
                        .lineLimit(1)
                    Color.clear.frame(width: 18)  // reserved for close button / dirty dot
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(isActive ? DesignTokens.bgPane(colorScheme) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Close / dirty indicator. Single button, same 14×14 hit area;
            // shows a filled dot when the file has unsaved changes, × otherwise
            // (VS Code / Sublime convention — no layout shift between states).
            Button {
                appState.closeTabConfirmingSave(id: file.id)
            } label: {
                Group {
                    if file.isDirty {
                        Circle()
                            .fill(DesignTokens.fgMute(colorScheme))
                            .frame(width: 8, height: 8)
                    } else {
                        Text("×")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.fgMute(colorScheme))
                    }
                }
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(appState.accentColor)
                    .frame(height: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func kindChip(_ label: String, kind: FileKind) -> some View {
        Text(label)
            .font(DesignTokens.font(9, weight: .semibold))
            .foregroundStyle(chipColor(kind))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(chipColor(kind).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func chipColor(_ kind: FileKind) -> Color {
        switch kind {
        case .markdown:  return appState.accentColor
        case .code:      return Color(hex: 0x2b5fb8)
        case .rtf:       return Color(hex: 0xa23b8a)
        case .plainText: return DesignTokens.fgMute(colorScheme == .dark ? .dark : .light)
        }
    }

    // MARK: Controls

    private var mdModeControl: some View {
        HStack(spacing: 0) {
            modeBtn(label: "◧ Read", isActive: appState.activeMdMode == .read) {
                appState.activeMdMode = .read
            }
            modeBtn(label: "⛶ Edit", isActive: appState.activeMdMode == .split) {
                appState.activeMdMode = .split
            }
        }
        .background(DesignTokens.bgTab(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.line(colorScheme), lineWidth: 0.5))
        .padding(.trailing, 4)
    }

    private func modeBtn(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DesignTokens.font(11, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? appState.accentColor : DesignTokens.fgMute(colorScheme))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(isActive ? appState.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var rtfToolbarToggle: some View {
        toolbarBtn(systemImage: "textformat", help: "Toggle Formatting Toolbar",
                   isActive: appState.rtfToolbarOpen) {
            appState.rtfToolbarOpen.toggle()
        }
    }

    private var themeToggleBtn: some View {
        Button {
            appState.settings.theme = appState.settings.theme == .dark ? .light : .dark
        } label: {
            Image(systemName: appState.settings.theme == .dark ? "sun.max" : "moon")
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.fgMute(colorScheme))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Toggle Theme")
    }

    private func toolbarBtn(systemImage: String, help: String,
                            isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? appState.accentColor : DesignTokens.fgMute(colorScheme))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var smartPasteChip: some View {
        Button {
            appState.showSmartPasteToast("URL → markdown link")
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.accentColor)
                    .frame(width: 5, height: 5)
                Text("smart paste")
                    .font(DesignTokens.font(10))
                    .foregroundStyle(DesignTokens.fgSoft(colorScheme))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DesignTokens.bg(colorScheme))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DesignTokens.line(colorScheme), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
    }
}
