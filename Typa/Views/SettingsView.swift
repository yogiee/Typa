import SwiftUI
import AppKit

/// Native macOS preferences window. Hosted by the SwiftUI `Settings { }` scene
/// in `TextPadApp`. Uses `TabView` + `Form` per Apple's Human Interface
/// Guidelines for small-app preferences (System Settings.app on macOS does the
/// same when there are <6 categories).
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        TabView {
            AppearanceTab(settings: $state.settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            EditorTab(settings: $state.settings)
                .tabItem { Label("Editor", systemImage: "text.cursor") }

            MarkdownTab(settings: $state.settings)
                .tabItem { Label("Markdown", systemImage: "doc.richtext") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $settings.theme) {
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                    Text("System").tag(AppTheme.system)
                }
                .pickerStyle(.segmented)
            }

            Section("Editor font") {
                Picker("Family", selection: $settings.fontName) {
                    ForEach(MonoFonts.available, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                LabeledContent("Size") {
                    HStack {
                        Slider(value: $settings.fontSize, in: 11...22, step: 1)
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Line height") {
                    HStack {
                        Slider(value: $settings.lineHeightMultiplier, in: 1.0...1.6, step: 0.05)
                        Text(String(format: "%.2f×", settings.lineHeightMultiplier))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Line length") {
                    HStack {
                        Slider(value: $settings.lineLength, in: 50...100, step: 2)
                        Text("\(Int(settings.lineLength)) ch")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Accent color") {
                AccentSwatchRow(selected: $settings.accent)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
    }
}

private struct AccentSwatchRow: View {
    @Binding var selected: AccentName
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            ForEach(AccentName.allCases, id: \.rawValue) { accent in
                Button {
                    selected = accent
                } label: {
                    Circle()
                        .fill(accent.color(isDark: colorScheme == .dark))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(
                                selected == accent ? Color.primary : .clear,
                                lineWidth: 2
                            )
                        )
                        .padding(2)
                }
                .buttonStyle(.plain)
                .help(accent.displayName)
            }
            Spacer()
        }
    }
}

// MARK: - Editor

private struct EditorTab: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show line numbers", isOn: $settings.showLineNumbers)
                Toggle("Focus mode", isOn: $settings.focusMode)
                    .help("Dim everything except the active line")
            }

            Section("Editing") {
                Toggle("Smart paste", isOn: $settings.smartPaste)
                    .help("Auto-detect URLs and code blocks when pasting")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
    }
}

// MARK: - Markdown

private struct MarkdownTab: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Open .md files in", selection: $settings.mdDefault) {
                    Text("Read mode").tag(MdMode.read)
                    Text("Split mode").tag(MdMode.split)
                }
                .pickerStyle(.segmented)
            }

            Section("Split view") {
                Picker("Orientation", selection: $settings.splitOrientation) {
                    Text("Side by side").tag(SplitOrientation.vertical)
                    Text("Stacked").tag(SplitOrientation.horizontal)
                }
                .pickerStyle(.segmented)

                Toggle("Sync scroll between source and preview",
                       isOn: $settings.syncScroll)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
    }
}

// MARK: - About

private struct AboutTab: View {
    @State private var updater = UpdaterService.shared

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Typa"
    }
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 4)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.system(size: 20, weight: .semibold))
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("A small, focused text editor for macOS that reads Markdown beautifully.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Link(destination: URL(string: "https://github.com/yogiee/Typa")!) {
                Label("View on GitHub", systemImage: "arrow.up.right.square")
            }

            // Updates
            VStack(spacing: 8) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .controlSize(.regular)

                Picker("", selection: Binding(
                    get: { updater.updateMode },
                    set: { updater.updateMode = $0 }
                )) {
                    Text("Install updates automatically").tag(0)
                    Text("Download and ask before installing").tag(1)
                    Text("Don't check for updates").tag(2)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 280)
            }
            .padding(.top, 4)

            Spacer()

            Text("© 2026 · Built with Swift and SwiftUI")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Available monospaced fonts

/// One-time enumeration of system monospaced fonts. NSFontManager's
/// `availableFontNamesWithTraits(.monoSpaceTrait)` is filtered to PostScript
/// names that map to displayable font families. Cached after first access so
/// reopening the Settings window costs nothing.
enum MonoFonts {
    static let available: [String] = {
        let mgr = NSFontManager.shared
        let raw = mgr.availableFontNames(with: .fixedPitchFontMask) ?? []
        // PostScript names; dedupe & strip italic/bold variants for clarity.
        var seen = Set<String>()
        var fonts: [String] = []
        for name in raw {
            // Skip italic/bold variants — keep family roots only
            let lower = name.lowercased()
            if lower.contains("italic") || lower.contains("oblique") { continue }
            if lower.contains("-bold") || lower.hasSuffix("bd") { continue }
            if seen.insert(name).inserted { fonts.append(name) }
        }
        // Surface JetBrains Mono first if present
        if let i = fonts.firstIndex(of: "JetBrains Mono") {
            fonts.remove(at: i); fonts.insert("JetBrains Mono", at: 0)
        } else if let i = fonts.firstIndex(of: "JetBrainsMono-Regular") {
            fonts.remove(at: i); fonts.insert("JetBrainsMono-Regular", at: 0)
        }
        return fonts.sorted { (a, b) -> Bool in
            // Keep JetBrains Mono pinned first; otherwise alphabetical
            if a.hasPrefix("JetBrains") && !b.hasPrefix("JetBrains") { return true }
            if !a.hasPrefix("JetBrains") && b.hasPrefix("JetBrains") { return false }
            return a < b
        }
    }()
}
