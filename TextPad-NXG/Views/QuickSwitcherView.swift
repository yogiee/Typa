import SwiftUI

struct QuickSwitcherView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var inputFocused: Bool

    private var filtered: [FileItem] {
        if query.isEmpty { return appState.allFiles }
        return appState.allFiles.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                searchRow
                Divider().opacity(0.6)
                resultsList
                Divider().opacity(0.6)
                footer
            }
            .frame(width: 540)
            .background(DesignTokens.bgElev(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: DesignTokens.shadowLg, radius: 40, x: 0, y: 16)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.lineStrong(colorScheme), lineWidth: 0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 80)
        }
        .onAppear {
            query = ""
            selectedIndex = 0
            inputFocused = true
        }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.return) {
            if let file = filtered[safe: selectedIndex] {
                appState.openFile(id: file.id)
                close()
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(filtered.count - 1, selectedIndex + 1)
            return .handled
        }
    }

    // MARK: Sub-views

    private var searchRow: some View {
        HStack(spacing: 8) {
            Text("⌘K")
                .font(DesignTokens.font(11, weight: .semibold))
                .foregroundStyle(DesignTokens.fgMute(colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DesignTokens.bgTab(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("Jump to file…", text: $query)
                .font(DesignTokens.font(14))
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filtered.isEmpty {
                    Text("No matches")
                        .font(DesignTokens.font(13))
                        .foregroundStyle(DesignTokens.fgMute(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(20)
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { idx, file in
                        qsRow(file: file, isSelected: idx == selectedIndex)
                            .onTapGesture {
                                appState.openFile(id: file.id)
                                close()
                            }
                            .onHover { _ in selectedIndex = idx }
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func qsRow(file: FileItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            kindChip(file)
            Text(file.name)
                .font(DesignTokens.font(13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? DesignTokens.fg(colorScheme) : DesignTokens.fgSoft(colorScheme))
                .lineLimit(1)
            Spacer()
            Text(file.folder)
                .font(DesignTokens.font(11))
                .foregroundStyle(DesignTokens.fgFaint(colorScheme))
            if file.starred {
                Text("★")
                    .font(.system(size: 10))
                    .foregroundStyle(appState.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(isSelected ? appState.accentColor.opacity(0.08) : Color.clear)
    }

    private func kindChip(_ file: FileItem) -> some View {
        Text(file.displayKind)
            .font(DesignTokens.font(9, weight: .semibold))
            .foregroundStyle(appState.accentColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(appState.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var footer: some View {
        HStack(spacing: 16) {
            footerHint("↑↓", label: "navigate")
            footerHint("↵", label: "open")
            footerHint("esc", label: "close")
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private func footerHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(DesignTokens.font(10, weight: .semibold))
                .foregroundStyle(DesignTokens.fgSoft(colorScheme))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(DesignTokens.bgTab(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(DesignTokens.font(11))
                .foregroundStyle(DesignTokens.fgFaint(colorScheme))
        }
    }

    private func close() { appState.qsOpen = false }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
