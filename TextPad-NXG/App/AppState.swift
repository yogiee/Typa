import SwiftUI
import AppKit

// MARK: - File model

struct FileItem: Identifiable {
    let id: String
    let name: String
    let folder: String
    var kind: FileKind
    var lang: String?
    var body: String
    var modified: String
    var starred: Bool = false
    var url: URL?

    var displayKind: String {
        switch kind {
        case .markdown:  return "M↓"
        case .plainText: return "TXT"
        case .rtf:       return "RTF"
        case .code:      return (lang ?? "•").uppercased()
        }
    }

    var modeLabel: String {
        switch kind {
        case .markdown:  return "Markdown"
        case .plainText: return "Plain text"
        case .rtf:       return "Rich text"
        case .code:      return SyntaxHighlighter.langNames[lang ?? ""] ?? (lang?.uppercased() ?? "Code")
        }
    }
}

enum FileKind: Equatable {
    case markdown
    case plainText
    case code
    case rtf
}

// MARK: - Settings

enum MdMode: String { case read, split }
enum SplitOrientation: String { case vertical, horizontal }
enum SidebarMode { case files, outline }

struct AppSettings {
    var theme: AppTheme = .light
    var fontName: String = "JetBrains Mono"
    var fontSize: Double = 14
    var lineHeightMultiplier: Double = 1.0   // multiplies natural line height
    var lineLength: Double = 72
    var splitOrientation: SplitOrientation = .vertical
    var focusMode: Bool = false
    var showLineNumbers: Bool = true
    var smartPaste: Bool = true
    var mdDefault: MdMode = .read
    var syncScroll: Bool = true
    var accent: AccentName = .teal
}

// MARK: - App state

@Observable
@MainActor
final class AppState {

    // MARK: Data
    var files: [String: FileItem] = [:]
    var openTabIds: [String] = []
    var activeTabId: String? = nil
    var mdModes: [String: MdMode] = [:]

    // MARK: UI
    var sidebarOpen: Bool = false
    var sidebarMode: SidebarMode = .files
    var findOpen: Bool = false
    var findQuery: String = ""
    var replaceMode: Bool = false
    var replaceQuery: String = ""
    var qsOpen: Bool = false
    var rtfToolbarOpen: Bool = true
    var activeAnchor: String? = nil
    var smartPasteToast: String? = nil

    // MARK: Settings
    var settings: AppSettings = AppSettings()

    // MARK: Computed

    var activeFile: FileItem? {
        guard let id = activeTabId else { return nil }
        return files[id]
    }

    var isMd: Bool { activeFile?.kind == .markdown }
    var isCode: Bool { activeFile?.kind == .code }
    var isRtf: Bool { activeFile?.kind == .rtf }

    var activeMdMode: MdMode {
        get { activeTabId.flatMap { mdModes[$0] } ?? settings.mdDefault }
        set { if let id = activeTabId { mdModes[id] = newValue } }
    }

    var outline: [OutlineItem] {
        guard let f = activeFile, f.kind == .markdown else { return [] }
        return MarkdownEngine.extractOutline(f.body)
    }

    var stats: DocStats {
        guard let f = activeFile else { return DocStats(words: 0, chars: 0, lines: 0, readMin: 0) }
        return MarkdownEngine.countStats(f.body)
    }

    var findCount: Int {
        guard !findQuery.isEmpty, let f = activeFile else { return 0 }
        let escaped = NSRegularExpression.escapedPattern(for: findQuery)
        guard let re = try? NSRegularExpression(pattern: escaped, options: .caseInsensitive) else { return 0 }
        return re.numberOfMatches(in: f.body, range: NSRange(f.body.startIndex..., in: f.body))
    }

    var accentColor: Color {
        settings.accent.color(isDark: settings.theme == .dark)
    }

    var allFiles: [FileItem] { Array(files.values) }
    var starredFiles: [FileItem] { allFiles.filter { $0.starred } }
    var recentFiles: [FileItem] { allFiles }

    // MARK: Tab management

    func openFile(id: String) {
        activeTabId = id
        if !openTabIds.contains(id) { openTabIds.append(id) }
        qsOpen = false
        if files[id]?.kind == .markdown && mdModes[id] == nil {
            mdModes[id] = settings.mdDefault
        }
    }

    func closeTab(id: String) {
        openTabIds.removeAll { $0 == id }
        if activeTabId == id {
            activeTabId = openTabIds.last
        }
    }

    func updateBody(_ body: String, for id: String) {
        files[id]?.body = body
    }

    // MARK: File operations

    func newFile() {
        let id = UUID().uuidString
        files[id] = FileItem(id: id, name: "Untitled.txt", folder: "~",
                              kind: .plainText, body: "", modified: "now")
        openFile(id: id)
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.loadFile(url: url) }
        }
    }

    func loadFile(url: URL) {
        let id = url.absoluteString
        if files[id] != nil { openFile(id: id); return }
        guard let body = try? String(contentsOf: url, encoding: .utf8) else { return }
        let ext = url.pathExtension.lowercased()
        let kind: FileKind
        var lang: String? = nil
        switch ext {
        case "md", "markdown": kind = .markdown
        case "rtf":            kind = .rtf
        case "js","ts","jsx","tsx","php","css","html","htm","json","py","sh":
            kind = .code
            lang = SyntaxHighlighter.langFromName(url.lastPathComponent)
        default: kind = .plainText
        }
        files[id] = FileItem(id: id, name: url.lastPathComponent,
                              folder: url.deletingLastPathComponent().lastPathComponent,
                              kind: kind, lang: lang, body: body, modified: "now", url: url)
        openFile(id: id)
    }

    func toggleSidebar() { sidebarOpen.toggle() }

    func toggleMdMode() {
        guard isMd else { return }
        activeMdMode = activeMdMode == .read ? .split : .read
    }

    func showSmartPasteToast(_ label: String) {
        smartPasteToast = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.smartPasteToast = nil
        }
    }

    // MARK: Sample data

    func loadSampleFiles() {
        let readme = FileItem(id: "readme", name: "README.md", folder: "textpad-nxg",
                              kind: .markdown, body: sampleReadme, modified: "today", starred: true)
        let notes  = FileItem(id: "notes",  name: "notes.md",  folder: "Documents",
                              kind: .markdown, body: sampleNotes,  modified: "2h ago")
        let mainJS = FileItem(id: "main-js", name: "main.js", folder: "src",
                              kind: .code, lang: "js", body: sampleJS, modified: "yesterday")
        let config = FileItem(id: "config",  name: "config.json", folder: "project",
                              kind: .code, lang: "json", body: sampleJSON, modified: "3d ago")
        let todo   = FileItem(id: "todo",    name: "todo.txt", folder: "Desktop",
                              kind: .plainText, body: sampleTxt, modified: "just now")
        files = ["readme": readme, "notes": notes, "main-js": mainJS, "config": config, "todo": todo]
        openTabIds = ["readme", "notes", "main-js"]
        activeTabId = "readme"
        mdModes["readme"] = .read
    }
}

// MARK: - Sample content

private let sampleReadme = """
# TextPad-NXG

A small, focused text editor for macOS that reads Markdown beautifully.

## Features

- **Markdown-first** — opens `.md` files in rendered read mode by default
- **Split edit** — toggle to source + live preview side by side
- **Syntax highlighting** — lightweight code viewing for JS, TS, PHP, CSS and more
- **Clean chrome** — sidebar, tabs, and statusbar that stay out of the way

## Quick start

1. Drop a file onto the window to open it
2. Press `⌘K` to jump between open files
3. Use `⌘E` to toggle between read and edit mode for Markdown files
4. Press `⌘1` to show the file sidebar

## Keyboard shortcuts

| Action | Key |
|--------|-----|
| Sidebar | `⌘1` |
| Quick switcher | `⌘K` |
| Find | `⌘F` |
| Find & Replace | `⌘⌥F` |
| Read ↔ Edit | `⌘E` |
| New file | `⌘N` |
| Open | `⌘O` |
| Preferences | `⌘,` |

---

> Built with Swift and SwiftUI. No Electron, no subscriptions, no nonsense.
"""

private let sampleNotes = """
# Meeting Notes — May 2026

## Agenda

- Product roadmap review
- Q2 metrics discussion
- Team announcements

## Notes

The team agreed to **ship the sidebar outline feature** before the end of the sprint.

Key decisions:

- Typewriter mode is a _keeper_ — user research confirmed it
- Smart paste will default to **on** for new installs
- RTF toolbar collapses by default on small screens

## Action items

- [ ] Finalize sync-scroll implementation
- [ ] Write release notes for 0.2.0
- [x] Ship dark mode accent palette
- [ ] Add drag-to-reorder for sidebar items

---

Next sync: Friday at 10am.
"""

private let sampleJS = """
// main.js — app entry point

import { createApp } from './core/app.js';
import { loadConfig } from './utils/config.js';

const DEFAULT_PORT = 3000;

async function main() {
  const config = await loadConfig('./config.json');
  const port = config.port ?? DEFAULT_PORT;

  const app = createApp({
    port,
    debug: process.env.NODE_ENV !== 'production',
  });

  app.listen(port, () => {
    console.log(`Server running on port ${port}`);
  });
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
"""

private let sampleJSON = """
{
  "name": "textpad-nxg",
  "version": "0.1.0",
  "description": "A focused text editor for macOS",
  "scripts": {
    "build": "swift build -c release",
    "test": "swift test"
  },
  "license": "MIT"
}
"""

private let sampleTxt = """
Today
-----
- Write release notes for 0.2.0
- Review PR #47 (sidebar outline)
- Sync with design on RTF toolbar

Tomorrow
--------
- Ship 0.2.0
- Update documentation

Backlog
-------
- Typewriter mode refinements
- Find bar animation polish
- Performance profiling for large files
"""
