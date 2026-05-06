import SwiftUI

struct EmptyStateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            DesignTokens.bg(colorScheme).ignoresSafeArea()

            VStack(spacing: 24) {
                card
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            // Mark icon
            markIcon
                .padding(.bottom, 16)

            Text("TextPad-NXG")
                .font(DesignTokens.font(18, weight: .semibold))
                .foregroundStyle(DesignTokens.fg(colorScheme))
                .padding(.bottom, 4)

            Text("A small text editor that reads markdown.")
                .font(DesignTokens.font(13))
                .foregroundStyle(DesignTokens.fgMute(colorScheme))
                .padding(.bottom, 24)

            // Primary actions
            HStack(spacing: 10) {
                actionBtn(label: "New file", kbd: "⌘N", isPrimary: true) {
                    appState.newFile()
                }
                actionBtn(label: "Open…", kbd: "⌘O", isPrimary: false) {
                    appState.openFilePanel()
                }
            }
            .padding(.bottom, 28)

            // Recent files
            if !appState.recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent")
                        .font(DesignTokens.font(10, weight: .semibold))
                        .foregroundStyle(DesignTokens.fgFaint(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    ForEach(appState.recentFiles.prefix(5)) { file in
                        Button {
                            appState.openFile(id: file.id)
                        } label: {
                            HStack(spacing: 10) {
                                kindBadge(file)
                                Text(file.name)
                                    .font(DesignTokens.font(12))
                                    .foregroundStyle(DesignTokens.fgSoft(colorScheme))
                                    .lineLimit(1)
                                Spacer()
                                Text(file.folder)
                                    .font(DesignTokens.font(11))
                                    .foregroundStyle(DesignTokens.fgFaint(colorScheme))
                                Text(file.modified)
                                    .font(DesignTokens.font(11))
                                    .foregroundStyle(DesignTokens.fgFaint(colorScheme))
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(DesignTokens.bg(colorScheme))
                        if file.id != appState.recentFiles.prefix(5).last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .padding(12)
                .background(DesignTokens.bgElev(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.line(colorScheme), lineWidth: 0.5))
            }

            Text("tip — drop a file anywhere on this window to open it")
                .font(DesignTokens.font(11))
                .foregroundStyle(DesignTokens.fgFaint(colorScheme))
                .padding(.top, 20)
        }
        .padding(32)
        .frame(width: 440)
        .background(DesignTokens.bgPane(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: DesignTokens.shadowMd, radius: 24, x: 0, y: 6)
    }

    private var markIcon: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.opacity = 0.45
            ctx.stroke(
                Path { p in
                    p.addRoundedRect(in: CGRect(x: 6, y: 6, width: 28, height: 34),
                                     cornerSize: CGSize(width: 2, height: 2))
                },
                with: .foreground,
                lineWidth: 1.25
            )
            ctx.opacity = 1
            ctx.fill(
                Path { p in
                    p.addRoundedRect(in: CGRect(x: 12, y: 12, width: 28, height: 34),
                                     cornerSize: CGSize(width: 2, height: 2))
                },
                with: .color(DesignTokens.bgPane(colorScheme))
            )
            ctx.stroke(
                Path { p in
                    p.addRoundedRect(in: CGRect(x: 12, y: 12, width: 28, height: 34),
                                     cornerSize: CGSize(width: 2, height: 2))
                },
                with: .foreground,
                lineWidth: 1.25
            )
            let lineColor = GraphicsContext.Shading.color(DesignTokens.fg(colorScheme))
            let lw: CGFloat = 1.25
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 17, y: 20)); p.addLine(to: CGPoint(x: 35, y: 20)) }, with: lineColor, lineWidth: lw)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 17, y: 26)); p.addLine(to: CGPoint(x: 35, y: 26)) }, with: lineColor, lineWidth: lw)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 17, y: 32)); p.addLine(to: CGPoint(x: 29, y: 32)) }, with: lineColor, lineWidth: lw)
        }
        .foregroundStyle(DesignTokens.fg(colorScheme))
        .frame(width: 46, height: 46)
    }

    private func actionBtn(label: String, kbd: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(kbd)
                    .font(DesignTokens.font(11))
                    .foregroundStyle(isPrimary ? appState.accentColor.opacity(0.7) : DesignTokens.fgMute(colorScheme))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isPrimary ? appState.accentColor.opacity(0.1) : DesignTokens.bgTab(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(label)
                    .font(DesignTokens.font(13, weight: .medium))
                    .foregroundStyle(isPrimary ? appState.accentColor : DesignTokens.fg(colorScheme))
            }
            .frame(height: 36)
            .padding(.horizontal, 16)
            .background(isPrimary
                        ? appState.accentColor.opacity(0.08)
                        : DesignTokens.bgTab(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(isPrimary ? appState.accentColor.opacity(0.3) : DesignTokens.line(colorScheme),
                        lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func kindBadge(_ file: FileItem) -> some View {
        Text(file.displayKind)
            .font(DesignTokens.font(9, weight: .semibold))
            .foregroundStyle(appState.accentColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(appState.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
