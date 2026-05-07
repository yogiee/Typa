import SwiftUI

private struct LangEntry: Identifiable {
    let id: String   // lang code, e.g. "js"
    let name: String // display name, e.g. "JavaScript"
}

struct StatusBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            modeChip
            divider
            statsSection
            Spacer()
            toggleSection
            divider
            Text("UTF-8 · LF")
                .font(DesignTokens.font(11))
                .foregroundStyle(DesignTokens.fgMute(colorScheme))
                .padding(.horizontal, 10)
        }
        .frame(height: 28)
        .background(DesignTokens.bgElev(colorScheme))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.line(colorScheme))
                .frame(height: 0.5)
        }
    }

    // MARK: Mode chip

    private var modeChip: some View {
        Group {
            if let file = appState.activeFile {
                fileKindMenu(file: file)
            } else {
                chipLabel("Ready")
                    .padding(.horizontal, 10)
            }
        }
    }

    private func chipLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(appState.accentColor)
                .frame(width: 5, height: 5)
            Text(text)
                .font(DesignTokens.font(11, weight: .medium))
                .foregroundStyle(DesignTokens.fgSoft(colorScheme))
        }
    }

    @ViewBuilder
    private func fileKindMenu(file: FileItem) -> some View {
        let nonEmptyLines = file.body
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        let canAutoDetect = nonEmptyLines >= 5

        Menu {
            Button("Markdown") {
                appState.setFileKind(.markdown, lang: nil, for: file.id)
            }
            Button("Plain Text") {
                appState.setFileKind(.plainText, lang: nil, for: file.id)
            }
            Button("Rich Text") {
                appState.setFileKind(.rtf, lang: nil, for: file.id)
            }
            Divider()
            ForEach(sortedLangs) { entry in
                Button(entry.name) {
                    appState.setFileKind(.code, lang: entry.id, for: file.id)
                }
            }
            Divider()
            Button("Auto-detect") {
                if let (kind, lang) = AppState.detectKindFromContent(file.body) {
                    appState.setFileKind(kind, lang: lang, for: file.id)
                }
            }
            .disabled(!canAutoDetect)
        } label: {
            chipLabel(modeLabel)
                .padding(.horizontal, 10)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sortedLangs: [LangEntry] {
        SyntaxHighlighter.langNames
            .filter { $0.key != "md" }
            .sorted { $0.value < $1.value }
            .map { LangEntry(id: $0.key, name: $0.value) }
    }

    private var modeLabel: String {
        guard let file = appState.activeFile else { return "Ready" }
        if file.kind == .markdown {
            return "Markdown · \(appState.activeMdMode.rawValue)"
        }
        return file.modeLabel
    }

    // MARK: Stats

    @ViewBuilder
    private var statsSection: some View {
        if appState.activeFile != nil {
            let s = appState.stats
            Group {
                statText("\(s.words.formatted()) words")
                divider
                statText("\(s.chars.formatted()) chars")
                divider
                statText("\(s.lines) lines")
                divider
                statText("~\(s.readMin) min")
            }
        }
    }

    private func statText(_ s: String) -> some View {
        Text(s)
            .font(DesignTokens.font(11))
            .foregroundStyle(DesignTokens.fgMute(colorScheme))
            .padding(.horizontal, 8)
    }

    // MARK: Toggles

    private var toggleSection: some View {
        HStack(spacing: 4) {
            statusToggle("focus", isOn: appState.settings.focusMode) {
                appState.settings.focusMode.toggle()
            }
        }
        .padding(.horizontal, 6)
    }

    private func statusToggle(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn ? appState.accentColor : DesignTokens.fgFaint(colorScheme))
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(DesignTokens.font(11))
                    .foregroundStyle(isOn ? DesignTokens.fg(colorScheme) : DesignTokens.fgMute(colorScheme))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isOn ? appState.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.line(colorScheme))
            .frame(width: 0.5, height: 14)
    }
}
