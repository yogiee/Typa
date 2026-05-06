import SwiftUI

struct MarkdownReadView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let file: FileItem

    private var fontSize: CGFloat { CGFloat(appState.settings.fontSize) }

    var body: some View {
        MarkdownWebView(
            source:      file.body,
            fontSize:    fontSize,
            lineLength:  Int(appState.settings.lineLength),
            accentColor: appState.accentColor,
            colorScheme: colorScheme
        )
        .background(DesignTokens.bgPane(colorScheme))
    }
}
