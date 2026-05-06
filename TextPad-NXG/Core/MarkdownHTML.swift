import SwiftUI

// Renders markdown source into a complete HTML document, suitable for
// loading into a WKWebView. Modeled after MacDown's MPRenderer pipeline:
// parse → emit HTML → apply themed CSS → load.
extension MarkdownEngine {

    static func renderHTML(
        _ source: String,
        colorScheme: ColorScheme,
        fontSize: CGFloat,
        lineLength: Int,
        accentHex: String,
        themeName: String = "default"
    ) -> String {
        let blocks  = parseBlocks(source)
        let bodyHTML = blocks.map { renderBlockHTML($0) }.joined(separator: "\n")
        let css     = stylesheet(colorScheme: colorScheme,
                                  fontSize: fontSize,
                                  lineLength: lineLength,
                                  accentHex: accentHex,
                                  themeName: themeName)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width">
        <style>\(css)</style>
        </head>
        <body>
        <article class="markdown-body">
        \(bodyHTML)
        </article>
        <script>
        // Two-way scroll-sync helper. Source → preview drives scrollTop;
        // preview → source posts a 0..1 fraction back via webkit handler.
        window.tpSetScrollFraction = function(f) {
            const max = Math.max(document.documentElement.scrollHeight - window.innerHeight, 0);
            window.scrollTo(0, f * max);
        };
        let __tpSyncing = false;
        window.addEventListener('scroll', function() {
            if (__tpSyncing) return;
            const max = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
            const f = Math.min(Math.max(window.scrollY / max, 0), 1);
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tpScroll) {
                window.webkit.messageHandlers.tpScroll.postMessage(f);
            }
        }, { passive: true });
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Block rendering

    private static func renderBlockHTML(_ block: MdBlock) -> String {
        switch block {
        case .heading(let level, let text):
            let lvl = max(1, min(level, 6))
            let id  = slug(text)
            return "<h\(lvl) id=\"\(escapeHTMLAttr(id))\">\(renderInlineHTML(parseInline(text)))</h\(lvl)>"

        case .paragraph(let text):
            return "<p>\(renderInlineHTML(parseInline(text)))</p>"

        case .code(let lang, let body):
            let langClass = lang.isEmpty ? "" : " class=\"language-\(escapeHTMLAttr(lang))\""
            // If our tokenizer recognizes the language, emit per-token spans
            // so the preview gets the same syntax highlighting as the editor.
            // Languages we don't tokenize fall through to plain escaped text.
            let resolved = SyntaxHighlighter.langFromName("file.\(lang)") ?? lang
            let inner: String
            if !resolved.isEmpty, isKnownLang(resolved) {
                inner = highlightedCodeHTML(body: body, lang: resolved)
            } else {
                inner = escapeHTML(body)
            }
            return "<pre><code\(langClass)>\(inner)</code></pre>"

        case .quote(let body):
            let inner = parseBlocks(body).map { renderBlockHTML($0) }.joined(separator: "\n")
            return "<blockquote>\(inner)</blockquote>"

        case .list(let lines):
            return renderListHTML(lines)

        case .table(let headers, let rows, let aligns):
            return renderTableHTML(headers: headers, rows: rows, aligns: aligns)

        case .hr:
            return "<hr>"
        }
    }

    // MARK: Code-block syntax highlighting
    //
    // Re-uses the editor's `SyntaxHighlighter` tokenizer so the preview shows
    // the same colors as the editor without bundling a JS highlighter.

    private static func isKnownLang(_ lang: String) -> Bool {
        SyntaxHighlighter.langNames.keys.contains(lang)
    }

    private static func highlightedCodeHTML(body: String, lang: String) -> String {
        var html = ""
        let lines = body.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            let tokens = SyntaxHighlighter.tokenize(line, lang: lang)
            for token in tokens {
                let safe = escapeHTML(token.text)
                if token.type == "text" || token.type.isEmpty {
                    html += safe
                } else {
                    html += "<span class=\"tok-\(token.type)\">\(safe)</span>"
                }
            }
            if idx < lines.count - 1 { html += "\n" }
        }
        return html
    }

    private static func renderTableHTML(headers: [String],
                                         rows: [[String]],
                                         aligns: [MdTableAlign]) -> String {
        func styleAttr(_ a: MdTableAlign) -> String {
            switch a {
            case .none:   return ""
            case .left:   return " style=\"text-align:left\""
            case .right:  return " style=\"text-align:right\""
            case .center: return " style=\"text-align:center\""
            }
        }
        var html = "<table><thead><tr>"
        for (i, h) in headers.enumerated() {
            let a = i < aligns.count ? aligns[i] : .none
            html += "<th\(styleAttr(a))>\(renderInlineHTML(parseInline(h)))</th>"
        }
        html += "</tr></thead><tbody>"
        for row in rows {
            html += "<tr>"
            for (i, cell) in row.enumerated() {
                let a = i < aligns.count ? aligns[i] : .none
                html += "<td\(styleAttr(a))>\(renderInlineHTML(parseInline(cell)))</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return html
    }

    private static func renderListHTML(_ lines: [String]) -> String {
        let parsed = parseList(lines)
        let tag = parsed.ordered ? "ol" : "ul"
        var html = "<\(tag)>"
        for item in parsed.items {
            html += "<li>"
            if let task = item.task {
                let checked = task ? " checked" : ""
                html += "<input type=\"checkbox\" disabled\(checked)> "
            }
            html += renderInlineHTML(parseInline(item.text))
            if !item.children.isEmpty {
                html += "<ul>"
                for c in item.children {
                    html += "<li>\(renderInlineHTML(parseInline(c.text)))</li>"
                }
                html += "</ul>"
            }
            html += "</li>"
        }
        html += "</\(tag)>"
        return html
    }

    // MARK: - Inline rendering

    private static func renderInlineHTML(_ parts: [MdInline]) -> String {
        parts.map { renderInlinePartHTML($0) }.joined()
    }

    private static func renderInlinePartHTML(_ part: MdInline) -> String {
        switch part {
        case .text(let s):       return escapeHTML(s)
        case .bold(let xs):      return "<strong>\(renderInlineHTML(xs))</strong>"
        case .italic(let s):     return "<em>\(escapeHTML(s))</em>"
        case .strike(let s):     return "<del>\(escapeHTML(s))</del>"
        case .highlight(let s):  return "<mark>\(escapeHTML(s))</mark>"
        case .superscript(let s):return "<sup>\(escapeHTML(s))</sup>"
        case .code(let s):       return "<code>\(escapeHTML(s))</code>"
        case .link(let xs, let url):
            return "<a href=\"\(escapeHTMLAttr(url))\">\(renderInlineHTML(xs))</a>"
        case .autolink(let url):
            return "<a href=\"\(escapeHTMLAttr(url))\">\(escapeHTML(url))</a>"
        }
    }

    // MARK: - HTML escaping

    private static func escapeHTML(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "&",  with: "&amp;")
        r = r.replacingOccurrences(of: "<",  with: "&lt;")
        r = r.replacingOccurrences(of: ">",  with: "&gt;")
        r = r.replacingOccurrences(of: "\"", with: "&quot;")
        r = r.replacingOccurrences(of: "'",  with: "&#39;")
        return r
    }

    private static func escapeHTMLAttr(_ s: String) -> String {
        escapeHTML(s)
    }

    // MARK: - Stylesheet

    private static func stylesheet(
        colorScheme: ColorScheme,
        fontSize: CGFloat,
        lineLength: Int,
        accentHex: String,
        themeName: String
    ) -> String {
        let dark = colorScheme == .dark
        let bg, fg, fgSoft, fgMute, line, codeBg, quoteBg, lineStrong: String
        if dark {
            bg         = "#1d1f22"
            fg         = "#e6e4df"
            fgSoft     = "#c2bfb8"
            fgMute     = "#888680"
            line       = "rgba(255,255,255,0.08)"
            lineStrong = "rgba(255,255,255,0.16)"
            codeBg     = "#232629"
            quoteBg    = "#1f2124"
        } else {
            bg         = "#fefdfa"
            fg         = "#1f1d1a"
            fgSoft     = "#4a4742"
            fgMute     = "#8a8780"
            line       = "rgba(30,28,25,0.10)"
            lineStrong = "rgba(30,28,25,0.18)"
            codeBg     = "#ece9e2"
            quoteBg    = "#f0ede5"
        }

        // Syntax token palette — same colors as the editor's gutter, mapped
        // by token type. SyntaxColors is the single source of truth.
        let sc = SyntaxColors.forScheme(colorScheme)
        let tk = sc.hexMap()

        let maxW = max(CGFloat(lineLength) * fontSize * 0.55, 320)

        return """
        :root {
            --bg: \(bg);
            --fg: \(fg);
            --fg-soft: \(fgSoft);
            --fg-mute: \(fgMute);
            --line: \(line);
            --line-strong: \(lineStrong);
            --code-bg: \(codeBg);
            --quote-bg: \(quoteBg);
            --accent: \(accentHex);
            --fs: \(Int(fontSize))px;
        }
        * { box-sizing: border-box; }
        html, body {
            margin: 0;
            padding: 0;
            background: var(--bg);
            color: var(--fg);
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            font-size: var(--fs);
            line-height: 1.65;
            -webkit-font-smoothing: antialiased;
        }
        .markdown-body {
            max-width: \(Int(maxW))px;
            margin: 48px auto;
            padding: 0 32px 64px;
        }
        h1, h2, h3, h4, h5, h6 {
            font-weight: 600;
            line-height: 1.25;
            margin: 1.6em 0 0.5em;
        }
        h1 {
            font-size: 2em;
            font-weight: 700;
            padding-bottom: 0.3em;
            border-bottom: 0.5px solid var(--line);
            margin-top: 2.2em;
        }
        h2 { font-size: 1.55em; font-weight: 700; }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1.1em; }
        h5 { font-size: 1.0em; color: var(--fg-soft); }
        h6 { font-size: 0.92em; color: var(--fg-mute); }
        p { margin: 0 0 1em; }
        a { color: var(--accent); text-decoration: none; border-bottom: 0.5px solid color-mix(in srgb, var(--accent) 40%, transparent); }
        a:hover { border-bottom-color: var(--accent); }
        strong { font-weight: 700; color: var(--fg); }
        em { font-style: italic; }
        code {
            font-family: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 0.92em;
            background: var(--code-bg);
            padding: 0.15em 0.35em;
            border-radius: 3px;
        }
        pre {
            background: var(--code-bg);
            padding: 14px 16px;
            border-radius: 6px;
            overflow-x: auto;
            margin: 0 0 1.2em;
            font-size: 0.92em;
            line-height: 1.55;
        }
        pre code {
            background: transparent;
            padding: 0;
            border-radius: 0;
            font-size: 1em;
        }
        blockquote {
            margin: 0 0 1em;
            padding: 12px 16px;
            background: var(--quote-bg);
            border-left: 2px solid var(--accent);
            border-radius: 0 4px 4px 0;
            color: var(--fg-soft);
        }
        blockquote p:last-child { margin-bottom: 0; }
        ul, ol { margin: 0 0 1em; padding-left: 1.6em; }
        ul ul, ol ol, ul ol, ol ul { margin-bottom: 0; }
        li { margin: 0.15em 0; }
        li > input[type="checkbox"] {
            margin-right: 0.4em;
            transform: translateY(1px);
            accent-color: var(--accent);
        }
        hr {
            border: none;
            border-top: 0.5px solid var(--line);
            margin: 2em 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 0 0 1.2em;
        }
        th, td {
            border: 0.5px solid var(--line);
            padding: 8px 12px;
            text-align: left;
        }
        th { background: var(--code-bg); font-weight: 600; }
        mark {
            background: color-mix(in srgb, var(--accent) 25%, transparent);
            color: inherit;
            padding: 0 0.15em;
            border-radius: 2px;
        }
        sup {
            font-size: 0.75em;
            line-height: 0;
            vertical-align: super;
        }
        /* Code-block syntax highlighting (matches editor) */
        .tok-keyword  { color: \(tk["keyword"] ?? fg); }
        .tok-string   { color: \(tk["string"]  ?? fg); }
        .tok-number   { color: \(tk["number"]  ?? fg); }
        .tok-comment  { color: \(tk["comment"] ?? fgMute); font-style: italic; }
        .tok-fn       { color: \(tk["fn"]      ?? fg); }
        .tok-tag      { color: \(tk["tag"]     ?? fg); }
        .tok-attr     { color: \(tk["attr"]    ?? fg); }
        .tok-prop     { color: \(tk["prop"]    ?? fg); }
        .tok-punc     { color: \(tk["punc"]    ?? fgMute); }
        .tok-op       { color: \(tk["op"]      ?? fgMute); }
        .tok-builtin  { color: \(tk["builtin"] ?? fg); }
        .tok-var      { color: \(tk["var"]     ?? fg); }
        .tok-selector { color: \(tk["selector"] ?? fg); }
        .tok-atrule   { color: \(tk["atrule"]  ?? fg); }
        .tok-bool     { color: \(tk["bool"]    ?? fg); }
        ::selection { background: color-mix(in srgb, var(--accent) 30%, transparent); }
        """
    }
}

// MARK: - Color helper for HTML

extension Color {
    var hexString: String {
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(rgb.redComponent   * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent  * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

extension SyntaxColors {
    /// Flatten the token-color set to a [tokenType: hex] map for CSS injection.
    func hexMap() -> [String: String] {
        [
            "keyword":  keyword.hexString,
            "string":   string.hexString,
            "number":   number.hexString,
            "comment":  comment.hexString,
            "fn":       fn.hexString,
            "tag":      tag.hexString,
            "attr":     attr.hexString,
            "prop":     prop.hexString,
            "punc":     punc.hexString,
            "op":       op.hexString,
            "builtin":  builtin.hexString,
            "var":      varColor.hexString,
            "selector": selector.hexString,
            "atrule":   atrule.hexString,
            "bool":     bool.hexString,
        ]
    }
}
