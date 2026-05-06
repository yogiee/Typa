import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var state = appState

        ZStack(alignment: .topLeading) {
            // Background
            DesignTokens.bg(colorScheme).ignoresSafeArea()

            VStack(spacing: 0) {
                TitleBarView()
                mainBody
                StatusBarView()
            }

            // Window-level overlays (full-screen modals)
            if appState.qsOpen {
                QuickSwitcherView()
            }


        }
        .frame(minWidth: 700, minHeight: 400)
        .ignoresSafeArea(edges: .top)
        .background(WindowConfigurator())
        .animation(.easeOut(duration: 0.15), value: appState.findOpen)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    Task { @MainActor in appState.loadFile(url: url) }
                }
            }
            return true
        }
    }

    @ViewBuilder
    private var mainBody: some View {
        HStack(spacing: 0) {
            if appState.sidebarOpen {
                SidebarView()
                    .transition(.move(edge: .leading))
            }

            ZStack(alignment: .topTrailing) {
                if let file = appState.activeFile {
                    activeFileView(file)
                        .id(file.id)
                } else {
                    EmptyStateView()
                }

                // Find bar floats over document content only
                if appState.findOpen {
                    FindBarView()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.15), value: appState.findOpen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: appState.sidebarOpen)
    }

    @ViewBuilder
    private func activeFileView(_ file: FileItem) -> some View {
        switch file.kind {
        case .markdown:
            if appState.activeMdMode == .read {
                MarkdownReadView(file: file)
            } else {
                MarkdownSplitView(file: file)
            }
        case .plainText:
            PlainTextEditorView(file: file)
        case .code:
            CodeView(file: file)
        case .rtf:
            RTFView(file: file)
        }
    }
}
