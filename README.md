# TextPad-NXG

A small, focused text editor for **macOS** that reads Markdown beautifully.

It deliberately avoids becoming an IDE — no plugin marketplace, no language
servers, no AI assistants. The chrome stays out of the way, and editing stays a
deliberate action.

[![Latest release](https://img.shields.io/github/v/release/yogiee/TextPad-NXG?style=flat-square)](https://github.com/yogiee/TextPad-NXG/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)](https://github.com/yogiee/TextPad-NXG/releases/latest)
[![SwiftUI · AppKit](https://img.shields.io/badge/SwiftUI-AppKit-orange?style=flat-square)](#architecture)

---

## What it does

- **Markdown is first-class.** `.md` files open in **rendered read mode** by
  default. One click toggles to **split: source + live preview**.
- **Plain text editor** with line numbers, focus mode, smart paste, and a
  monospace type stack.
- **Code viewer** for `.js`, `.ts`, `.tsx`, `.jsx`, `.php`, `.css`, `.html`,
  `.json`, `.py`, `.sh`, `.md` with syntax highlighting. Read-friendly with
  quick-edit affordances — not an IDE.
- **RTF** files open in a paged document view with a togglable formatting
  toolbar.

## Install

### Pre-built (recommended)

Grab `TextPad-NXG-x.y.z.dmg` from the
**[latest release](https://github.com/yogiee/TextPad-NXG/releases/latest)**,
mount it, and drag **TextPad-NXG** into your **Applications** folder.

> The build is not yet code-signed or notarized. On first launch, right-click
> the app icon → **Open**, then confirm the dialog. macOS only asks once.

### From source

```bash
git clone https://github.com/yogiee/TextPad-NXG.git
cd TextPad-NXG
./scripts/build-app.sh         # → build/TextPad-NXG.app
./scripts/make-dmg.sh          # → build/TextPad-NXG-x.y.z.dmg (optional)
```

Or open `TextPad-NXG.xcodeproj` in Xcode 15+ and run.

## Features

### Editor

- NSTextView-backed plain-text and code editors with **wrap-aware gutter**
  (line numbers stay aligned even with long wrapped lines)
- **Active-line highlight** that respects wrapped fragments
- **Focus mode**: dims everything except the active logical line
- User-selectable **monospace font** (filtered to fixed-pitch families) and
  **line-height multiplier**
- Theme: **light / dark / system**, plus four accent colors (teal · amber ·
  violet · rose)

### Markdown

- WKWebView-rendered preview with native **cross-block text selection**
- **Bidirectional source ↔ preview scroll sync** with feedback suppression
- Live preview that **preserves your reading position** across edits
- Markdown features supported:
  - Headings, paragraphs, blockquotes, fenced code, lists, task lists, HR
  - **Tables** with `:---` alignment syntax
  - **Strikethrough** (`~~text~~`), **highlight** (`==text==`),
    **superscript** (`^text^`)
  - **Autolink** for bare URLs
  - **SmartyPants**: `'` `"` → curly · `--` → en-dash · `---` → em-dash ·
    `...` → ellipsis
  - **Code blocks render with the same syntax highlighting as the editor**
- Markdown source toolbar: H, B, I, S, link, inline code, code block,
  bullet/numbered/task list, quote, HR — operates on selection or current
  line, with proper undo registration

### Chrome

- **Custom title bar** with traffic lights, sidebar toggle, file title,
  Read/Edit toggle (markdown), find / theme / settings on the right
- **Tabs** with kind chips (`M↓` `JS` `TXT` `RTF`) and close buttons
- **Sidebar** (`⌘1`): Files (Starred + Recent) and Outline (markdown headings)
- **Status bar**: file kind, words/chars/lines/read time, focus toggle,
  encoding
- **Find bar** (`⌘F` / `⌘⌥F`) floats over the document
- **Quick Switcher** (`⌘K`): fuzzy file picker

## Keyboard shortcuts

| Action            | Shortcut |
|-------------------|----------|
| Toggle sidebar    | `⌘1`     |
| Quick switcher    | `⌘K`     |
| Find              | `⌘F`     |
| Find & Replace    | `⌘⌥F`    |
| Preferences       | `⌘,`     |
| Toggle Read/Edit  | `⌘E`     |
| New file          | `⌘N`     |
| Open…             | `⌘O`     |

## Settings

Native macOS preferences window (`⌘,`) with four tabs:

- **Appearance** — theme · monospace font family · font size · line-height
  multiplier · line length · accent color
- **Editor** — show line numbers · focus mode · smart paste
- **Markdown** — default `.md` open mode · split orientation · sync scroll
- **About** — app info, version, GitHub link

## Code-block syntax highlighting

The editor and the markdown-preview code blocks share the same Swift
tokenizer — no JS dependency, no asset bundles. Supported languages:

| Token type | Light | Dark |
|---|---|---|
| keyword  | #a23b8a | #d289c9 |
| string   | #1f7a4d | #88c69b |
| number   | #9a4d00 | #e0a572 |
| comment  | #8a8780 | #6a6862 |
| fn       | #2b5fb8 | #7eb1f0 |
| tag      | #a23b8a | #d289c9 |

…plus `attr`, `prop`, `punc`, `op`, `builtin`, `var`, `selector`, `atrule`,
`bool`. Languages our tokenizer doesn't recognize render as plain monospace —
no error, just no colors.

## Architecture

- **SwiftUI** for the app shell, settings, sidebar, title bar
- **AppKit** (`NSViewRepresentable`) for the text editor (NSTextView,
  NSScrollView) and the markdown preview (WKWebView)
- **Pure-Swift markdown parser** — block + inline tokenizer, HTML emitter
  with themed CSS injection
- **No external dependencies** — no Swift Package or CocoaPods

```
TextPad-NXG/
  App/         — TextPadApp, AppState, AppCommands, Info.plist
  Core/        — DesignTokens, MarkdownEngine, MarkdownHTML, MdEdit,
                 SyntaxHighlighter
  Views/       — ContentView, TitleBarView, SidebarView, StatusBarView,
                 PlainTextEditorView, CodeView, MarkdownReadView,
                 MarkdownSplitView, MarkdownWebView, RTFView, FindBarView,
                 QuickSwitcherView, SettingsView, EmptyStateView
  Utilities/   — WindowConfigurator
  Resources/   — Assets.xcassets (app icon)
scripts/
  build-app.sh — release build → build/TextPad-NXG.app
  make-dmg.sh  — DMG packaging with drag-to-Applications layout
```

## Design tokens

Sourced from `TextPad-NXG/Core/DesignTokens.swift`. Highlights:

- **Type stack**: JetBrains Mono throughout (with system monospaced fallback)
- **Editor line height**: matches the layout manager's natural line height —
  the user can loosen with the line-height multiplier
- **Animations**: 150–220ms ease-out everywhere. No spring, no bounce.

## Roadmap

The product is intentionally feature-complete for v0.1. Likely follow-ups:

- Code signing + notarization (so first launch doesn't need right-click → Open)
- Sparkle auto-update
- Theme system for the markdown preview and editor

I'm not planning a plugin system, a language-server integration, or any
AI-assistant features. If that's what you're looking for, an IDE will serve
you better.

## Credits

- **JetBrains Mono** — the type stack, bundled in the repo for the runtime
- **MacDown** — referenced for its preferences taxonomy and the editor →
  WKWebView pipeline pattern. TextPad-NXG is a Swift/SwiftUI rewrite, not a
  fork.

## License

[MIT](LICENSE) © 2026 yogiee.

JetBrains Mono is bundled in the app under the
[SIL Open Font License 1.1](https://github.com/JetBrains/JetBrainsMono/blob/master/OFL.txt).
