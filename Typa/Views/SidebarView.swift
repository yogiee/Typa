import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider().opacity(0.6)
            sidebarBody
        }
        .frame(width: 240)
        .background(DesignTokens.bgSide(colorScheme))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignTokens.line(colorScheme))
                .frame(width: 0.5)
        }
    }

    // MARK: Header

    private var sidebarHeader: some View {
        HStack(spacing: 0) {
            Button {
                appState.sidebarMode = .files
            } label: {
                Text("Files")
                    .font(DesignTokens.font(12, weight: appState.sidebarMode == .files ? .semibold : .regular))
                    .foregroundStyle(appState.sidebarMode == .files
                        ? DesignTokens.fg(colorScheme)
                        : DesignTokens.fgMute(colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)

            Button {
                if appState.isMd { appState.sidebarMode = .outline }
            } label: {
                Text("Outline")
                    .font(DesignTokens.font(12, weight: appState.sidebarMode == .outline ? .semibold : .regular))
                    .foregroundStyle(
                        !appState.isMd ? DesignTokens.fgFaint(colorScheme) :
                        appState.sidebarMode == .outline ? DesignTokens.fg(colorScheme) :
                        DesignTokens.fgMute(colorScheme)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!appState.isMd)

            Button {
                appState.sidebarOpen = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.fgMute(colorScheme))
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(appState.sidebarMode == .files ? appState.accentColor : Color.clear)
                    .frame(height: 2)
                Rectangle()
                    .fill(appState.sidebarMode == .outline ? appState.accentColor : Color.clear)
                    .frame(height: 2)
                Color.clear.frame(width: 28, height: 2)
            }
        }
    }

    // MARK: Body

    @ViewBuilder
    private var sidebarBody: some View {
        if appState.sidebarMode == .files {
            filesTab
        } else {
            outlineTab
        }
    }

    private var filesTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !appState.starredFiles.isEmpty {
                    sectionHeader("Starred")
                    ForEach(appState.starredFiles) { file in
                        FileRowView(file: file)
                    }
                }
                sectionHeader("Recent")
                ForEach(appState.recentFiles) { file in
                    FileRowView(file: file)
                }
            }
            .padding(.top, 4)
        }
    }

    private var outlineTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if appState.outline.isEmpty {
                    Text("No headings yet")
                        .font(DesignTokens.font(12))
                        .foregroundStyle(DesignTokens.fgFaint(colorScheme))
                        .padding(16)
                } else {
                    sectionHeader("In this document")
                    ForEach(appState.outline) { item in
                        outlineRow(item)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DesignTokens.font(9, weight: .semibold))
            .foregroundStyle(DesignTokens.fgFaint(colorScheme))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func outlineRow(_ item: OutlineItem) -> some View {
        Button {
            appState.jumpToAnchor(item.anchor)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.activeAnchor == item.anchor
                          ? appState.accentColor
                          : DesignTokens.fgFaint(colorScheme))
                    .frame(width: 4, height: 4)
                Text(item.text)
                    .font(DesignTokens.font(12, weight: item.level == 1 ? .medium : .regular))
                    .foregroundStyle(appState.activeAnchor == item.anchor
                                     ? appState.accentColor
                                     : DesignTokens.fgSoft(colorScheme))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(12 + (item.level - 1) * 12))
            .padding(.trailing, 8)
            .frame(height: 28)
            .background(appState.activeAnchor == item.anchor
                        ? appState.accentColor.opacity(0.08)
                        : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FileRowView

struct FileRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let file: FileItem

    private var isActive: Bool { file.id == appState.activeTabId }

    var body: some View {
        Button {
            appState.openFile(id: file.id)
        } label: {
            HStack(spacing: 8) {
                kindChip
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .font(DesignTokens.font(12, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? DesignTokens.fg(colorScheme) : DesignTokens.fgSoft(colorScheme))
                        .lineLimit(1)
                    Text("\(file.folder) · \(file.modified)")
                        .font(DesignTokens.font(10))
                        .foregroundStyle(DesignTokens.fgFaint(colorScheme))
                }
                Spacer()
                if file.starred {
                    Text("★")
                        .font(.system(size: 10))
                        .foregroundStyle(appState.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? appState.accentColor.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var kindChip: some View {
        Text(file.displayKind)
            .font(DesignTokens.font(9, weight: .semibold))
            .foregroundStyle(chipColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(chipColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var chipColor: Color {
        switch file.kind {
        case .markdown:  return appState.accentColor
        case .code:      return Color(hex: 0x2b5fb8)
        case .rtf:       return Color(hex: 0xa23b8a)
        case .plainText: return DesignTokens.fgMute(colorScheme)
        }
    }
}
