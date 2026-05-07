import SwiftUI

struct FindBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            mainRow
            if appState.replaceMode && appState.findReplaceEnabled {
                Divider().opacity(0.5)
                replaceRow
            }
        }
        .onChange(of: appState.findReplaceEnabled) { _, enabled in
            if !enabled { appState.replaceMode = false }
        }
        .frame(width: 360)
        .background(DesignTokens.bgElev(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: DesignTokens.shadowLg, radius: 24, x: 0, y: 8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.lineStrong(colorScheme), lineWidth: 0.5))
        .padding(.top, 8)
        .padding(.trailing, 12)
        .onAppear { inputFocused = true }
        .onKeyPress(.escape) {
            appState.findOpen = false
            return .handled
        }
    }

    private var mainRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.fgMute(colorScheme))

            TextField("Find", text: Bindable(appState).findQuery)
                .font(DesignTokens.font(13))
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .frame(maxWidth: .infinity)
                .onSubmit { appState.findNext() }

            if appState.findCount > 0 || !appState.findQuery.isEmpty {
                Text(appState.findQuery.isEmpty ? "" : "\(appState.findCount) match\(appState.findCount == 1 ? "" : "es")")
                    .font(DesignTokens.font(11))
                    .foregroundStyle(DesignTokens.fgMute(colorScheme))
            }

            findBtn(systemImage: "chevron.up")   { appState.findPrev() }
            findBtn(systemImage: "chevron.down") { appState.findNext() }

            if appState.findReplaceEnabled {
                Divider().frame(height: 14).opacity(0.6)
                findBtn(systemImage: "arrow.left.arrow.right",
                        isActive: appState.replaceMode) {
                    appState.replaceMode.toggle()
                }
            }

            findBtn(systemImage: "xmark") {
                appState.findOpen = false
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private var replaceRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.fgMute(colorScheme))

            TextField("Replace with", text: Bindable(appState).replaceQuery)
                .font(DesignTokens.font(13))
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
                .onSubmit { appState.replaceAll() }

            Button("Replace all") { appState.replaceAll() }
                .font(DesignTokens.font(11))
                .foregroundStyle(appState.accentColor)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
    }

    private func findBtn(systemImage: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? appState.accentColor : DesignTokens.fgMute(colorScheme))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}
