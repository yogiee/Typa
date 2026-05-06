import SwiftUI
import AppKit

struct RTFView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let file: FileItem

    var body: some View {
        VStack(spacing: 0) {
            if appState.rtfToolbarOpen {
                RTFToolbarView()
                Divider().opacity(0.6)
            }
            ScrollView {
                VStack {
                    RTFDocPage(file: file, colorScheme: colorScheme)
                        .frame(maxWidth: 720)
                        .padding(.vertical, 48)
                }
                .frame(maxWidth: .infinity)
            }
            .background(DesignTokens.bg(colorScheme))
        }
    }
}

// MARK: - RTF page

struct RTFDocPage: View {
    let file: FileItem
    let colorScheme: ColorScheme

    var body: some View {
        RTFTextView(content: file.body)
            .padding(.horizontal, 56)
            .padding(.vertical, 72)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .frame(maxWidth: 720)
            .frame(minHeight: 960)
    }
}

// MARK: - RTF NSTextView

struct RTFTextView: NSViewRepresentable {
    let content: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.drawsBackground = false
        sv.hasVerticalScroller = false

        let tv = NSTextView()
        tv.isEditable = true
        tv.isRichText = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true

        let font = NSFont(name: "Helvetica Neue", size: 14)
            ?? NSFont.systemFont(ofSize: 14)
        tv.font = font
        tv.textColor = .black

        if let data = content.data(using: .utf8),
           let attr = try? NSAttributedString(data: data,
               options: [.documentType: NSAttributedString.DocumentType.html],
               documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attr)
        } else {
            tv.string = content
        }

        sv.documentView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {}

    class Coordinator: NSObject {}
}

// MARK: - RTF Toolbar

struct RTFToolbarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                toolGroup {
                    toolBtn("B", help: "Bold", bold: true)
                    toolBtn("I", help: "Italic", italic: true)
                    toolBtn("U", help: "Underline")
                    toolBtn("S̶", help: "Strikethrough")
                }
                toolDivider
                toolGroup {
                    toolBtn("≡", help: "Align Left")
                    toolBtn("≡", help: "Align Center")
                    toolBtn("≡", help: "Align Right")
                }
                toolDivider
                toolGroup {
                    toolBtn("•", help: "Bullet List")
                    toolBtn("1.", help: "Numbered List")
                }
                toolDivider
                toolGroup {
                    toolBtn("🔗", help: "Insert Link")
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 38)
        .background(DesignTokens.bgElev(colorScheme))
    }

    private func toolGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
    }

    private var toolDivider: some View {
        Rectangle()
            .fill(DesignTokens.line(colorScheme))
            .frame(width: 0.5, height: 18)
            .padding(.horizontal, 6)
    }

    private func toolBtn(_ label: String, help: String, bold: Bool = false, italic: Bool = false) -> some View {
        Button {
            // formatting action placeholder
        } label: {
            Text(label)
                .font(.system(size: 12, weight: bold ? .bold : .regular))
                .italic(italic)
                .foregroundStyle(DesignTokens.fgSoft(colorScheme))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
