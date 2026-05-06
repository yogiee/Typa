import Foundation

// MARK: - Block types

enum MdBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case code(lang: String, body: String)
    case quote(body: String)
    case list(lines: [String])
    case table(headers: [String], rows: [[String]], aligns: [MdTableAlign])
    case hr
}

enum MdTableAlign: String {
    case none, left, right, center
}

// MARK: - Inline elements

indirect enum MdInline {
    case text(String)
    case bold([MdInline])
    case italic(String)
    case strike(String)        // ~~text~~
    case highlight(String)     // ==text==
    case superscript(String)   // ^text^
    case code(String)
    case link(text: [MdInline], url: String)
    case autolink(String)      // bare URL → link
}

// MARK: - Outline item

struct OutlineItem: Identifiable {
    let id = UUID()
    let level: Int
    let text: String
    let anchor: String
}

// MARK: - Document stats

struct DocStats {
    let words: Int
    let chars: Int
    let lines: Int
    let readMin: Int
}

// MARK: - List structures

struct MdListItem {
    var text: String
    var task: Bool?
    var children: [(text: String, ordered: Bool)]
}

struct MdListBlock {
    let ordered: Bool
    let items: [MdListItem]
}

// MARK: - Regex helpers

private extension String {
    func captureGroups(pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard Range(m.range, in: self) != nil else { return nil }
        // check it matches the whole string
        if m.range.location != 0 || m.range.length != ns.length { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            let r = m.range(at: i)
            groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return groups
    }

    func hasMatch(pattern: String, options: NSRegularExpression.Options = []) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(self.startIndex..., in: self)
        return re.firstMatch(in: self, range: range) != nil
    }
}

// MARK: - Parser

enum MarkdownEngine {

    // MARK: Block parser

    static func parseBlocks(_ src: String) -> [MdBlock] {
        let lines = src.components(separatedBy: "\n")
        var blocks: [MdBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var buf: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    buf.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.code(lang: lang, body: buf.joined(separator: "\n")))
                continue
            }

            // horizontal rule
            if line.hasMatch(pattern: "^---+\\s*$") {
                blocks.append(.hr)
                i += 1
                continue
            }

            // heading: leading # characters
            if let groups = headingMatch(line) {
                blocks.append(.heading(level: groups.0, text: groups.1))
                i += 1
                continue
            }

            // blockquote
            if line.hasPrefix(">") {
                var buf: [String] = []
                while i < lines.count && lines[i].hasPrefix(">") {
                    let stripped = lines[i].hasPrefix("> ")
                        ? String(lines[i].dropFirst(2))
                        : String(lines[i].dropFirst(1))
                    buf.append(stripped)
                    i += 1
                }
                blocks.append(.quote(body: buf.joined(separator: "\n")))
                continue
            }

            // list
            if line.hasMatch(pattern: "^\\s*([-*]|\\d+\\.)\\s+") {
                var buf: [String] = [line]
                i += 1
                while i < lines.count &&
                      (lines[i].hasMatch(pattern: "^\\s*([-*]|\\d+\\.)\\s+")
                       || lines[i].hasMatch(pattern: "^\\s+\\S")) {
                    buf.append(lines[i])
                    i += 1
                }
                blocks.append(.list(lines: buf))
                continue
            }

            // GFM table — header row + separator row + N data rows
            if isTableLine(line),
               i + 1 < lines.count,
               isTableSeparator(lines[i + 1]) {
                let headers = parseTableRow(line)
                let aligns  = parseTableAligns(lines[i + 1])
                var rows: [[String]] = []
                i += 2
                while i < lines.count && isTableLine(lines[i]) {
                    rows.append(parseTableRow(lines[i]))
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows, aligns: aligns))
                continue
            }

            // blank line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // paragraph
            var buf: [String] = []
            while i < lines.count
                && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty
                && (headingMatch(lines[i]) == nil)
                && !lines[i].hasMatch(pattern: "^---+\\s*$")
                && !lines[i].hasPrefix("```")
                && !lines[i].hasPrefix(">")
                && !lines[i].hasMatch(pattern: "^\\s*([-*]|\\d+\\.)\\s+") {
                buf.append(lines[i])
                i += 1
            }
            if !buf.isEmpty {
                blocks.append(.paragraph(text: buf.joined(separator: " ")))
            }
        }
        return blocks
    }

    // MARK: Table helpers

    private static func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Must contain a "|" outside leading/trailing whitespace and at least one
        // pipe in the middle. We accept rows that start with "|" or have an
        // unescaped pipe in the body.
        guard trimmed.contains("|") else { return false }
        // Reject horizontal rule
        if trimmed.hasMatch(pattern: "^---+\\s*$") { return false }
        // Reject pure separator (handled separately)
        if isTableSeparator(line) { return true }  // separator IS a table line
        return trimmed.hasPrefix("|") || trimmed.contains(" | ") || trimmed.contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") && trimmed.contains("|") else { return false }
        // Each cell in a separator row matches :?-+:?  with optional surrounding spaces
        // The full row matches pipe-delimited cells of that form.
        return trimmed.hasMatch(pattern: "^\\|?\\s*:?-{3,}:?\\s*(\\|\\s*:?-{3,}:?\\s*)+\\|?$")
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTableAligns(_ line: String) -> [MdTableAlign] {
        parseTableRow(line).map { cell -> MdTableAlign in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let leftColon  = trimmed.hasPrefix(":")
            let rightColon = trimmed.hasSuffix(":")
            switch (leftColon, rightColon) {
            case (true,  true):  return .center
            case (true,  false): return .left
            case (false, true):  return .right
            case (false, false): return .none
            }
        }
    }

    private static func headingMatch(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        let rest = String(line.dropFirst(level))
        guard rest.hasPrefix(" ") || rest.hasPrefix("\t") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    // MARK: Inline parser

    static func parseInline(_ text: String) -> [MdInline] {
        var out: [MdInline] = []
        // Smartypants pass FIRST so quote/dash/ellipsis substitutions happen
        // before tokenization. Code spans/links carry their literal text
        // through unchanged because we only run the substitutions on plain
        // text fragments below.
        var rest = text

        let patterns: [(NSRegularExpression, String)] = [
            // Order matters when matches start at the same offset: more
            // specific (longer) delimiters first, so e.g. `~~strike~~` wins
            // over a hypothetical underscore run. Code is highest priority
            // so its contents are never re-parsed.
            (try! NSRegularExpression(pattern: "`([^`]+)`"),                   "code"),
            (try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#),    "link"),
            (try! NSRegularExpression(pattern: #"~~([^~\n]+)~~"#),              "strike"),
            (try! NSRegularExpression(pattern: #"==([^=\n]+)=="#),              "highlight"),
            (try! NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#),            "bold"),
            (try! NSRegularExpression(pattern: #"_([^_\n]+)_"#),                "italic"),
            (try! NSRegularExpression(pattern: #"\^([^\^\s]+)\^"#),             "superscript"),
            // Autolink: bare http/https URL, terminating on whitespace or
            // common trailing punctuation.
            (try! NSRegularExpression(pattern: #"https?://[^\s<>\)\]]+[^\s<>\)\]\.,;:!?]"#), "autolink"),
        ]

        while !rest.isEmpty {
            var earliest: (nsRange: NSRange, kind: String, match: NSTextCheckingResult)? = nil

            for (re, kind) in patterns {
                let nsRange = NSRange(rest.startIndex..., in: rest)
                if let m = re.firstMatch(in: rest, range: nsRange) {
                    if earliest == nil || m.range.location < earliest!.nsRange.location {
                        earliest = (m.range, kind, m)
                    }
                }
            }

            guard let hit = earliest else {
                out.append(.text(smartyPants(rest)))
                break
            }

            if hit.nsRange.location > 0,
               let r = Range(NSRange(location: 0, length: hit.nsRange.location), in: rest) {
                out.append(.text(smartyPants(String(rest[r]))))
            }

            let ns = rest as NSString
            switch hit.kind {
            case "code":
                if hit.match.numberOfRanges > 1 {
                    let g = hit.match.range(at: 1)
                    if g.location != NSNotFound {
                        out.append(.code(ns.substring(with: g)))
                    }
                }
            case "link":
                if hit.match.numberOfRanges > 2 {
                    let g1 = hit.match.range(at: 1)
                    let g2 = hit.match.range(at: 2)
                    if g1.location != NSNotFound && g2.location != NSNotFound {
                        out.append(.link(text: parseInline(ns.substring(with: g1)),
                                         url: ns.substring(with: g2)))
                    }
                }
            case "autolink":
                out.append(.autolink(ns.substring(with: hit.nsRange)))
            case "bold":
                if hit.match.numberOfRanges > 1 {
                    let g = hit.match.range(at: 1)
                    if g.location != NSNotFound {
                        out.append(.bold(parseInline(ns.substring(with: g))))
                    }
                }
            case "italic":
                if hit.match.numberOfRanges > 1 {
                    let g = hit.match.range(at: 1)
                    if g.location != NSNotFound {
                        out.append(.italic(ns.substring(with: g)))
                    }
                }
            case "strike":
                if hit.match.numberOfRanges > 1 {
                    let g = hit.match.range(at: 1)
                    if g.location != NSNotFound {
                        out.append(.strike(ns.substring(with: g)))
                    }
                }
            case "highlight":
                if hit.match.numberOfRanges > 1 {
                    let g = hit.match.range(at: 1)
                    if g.location != NSNotFound {
                        out.append(.highlight(ns.substring(with: g)))
                    }
                }
            case "superscript":
                if hit.match.numberOfRanges > 1 {
                    let g = hit.match.range(at: 1)
                    if g.location != NSNotFound {
                        out.append(.superscript(ns.substring(with: g)))
                    }
                }
            default: break
            }

            if let endIdx = Range(hit.nsRange, in: rest)?.upperBound {
                rest = String(rest[endIdx...])
            } else {
                break
            }
        }
        return out
    }

    // MARK: List parser

    static func parseList(_ lineArr: [String]) -> MdListBlock {
        var ordered = false
        var items: [MdListItem] = []
        var curr: MdListItem? = nil
        let listRe = try! NSRegularExpression(pattern: "^(\\s*)([-*]|\\d+\\.)\\s+(.*)")
        let taskRe = try! NSRegularExpression(pattern: "^\\[([ xX])\\]\\s+(.*)")

        for raw in lineArr {
            let ns = raw as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            if let m = listRe.firstMatch(in: raw, range: fullRange) {
                let indent = m.range(at: 1).length
                let marker = ns.substring(with: m.range(at: 2))
                let text = ns.substring(with: m.range(at: 3))
                let isOrdered = marker.first?.isNumber ?? false

                if items.isEmpty { ordered = isOrdered }

                if indent == 0 {
                    if let c = curr { items.append(c) }
                    var item = MdListItem(text: text, task: nil, children: [])
                    if let tm = taskRe.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                        let tn = text as NSString
                        let checked = tn.substring(with: tm.range(at: 1)).lowercased() == "x"
                        item.task = checked
                        item.text = tn.substring(with: tm.range(at: 2))
                    }
                    curr = item
                } else if curr != nil {
                    curr!.children.append((text: text, ordered: isOrdered))
                }
            } else if curr != nil {
                curr!.text += " " + raw.trimmingCharacters(in: .whitespaces)
            }
        }
        if let c = curr { items.append(c) }
        return MdListBlock(ordered: ordered, items: items)
    }

    // MARK: Outline

    static func extractOutline(_ src: String) -> [OutlineItem] {
        src.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("#"),
                  let (level, text) = headingMatch(line),
                  level <= 4
            else { return nil }
            return OutlineItem(level: level, text: text, anchor: slug(text))
        }
    }

    // MARK: Stats

    static func countStats(_ src: String) -> DocStats {
        let noFences = src.hasMatch(pattern: "```[\\s\\S]*?```")
            ? (try? NSRegularExpression(pattern: "```[\\s\\S]*?```"))
                .map { re -> String in
                    let ns = src as NSString
                    let result = re.stringByReplacingMatches(
                        in: src, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                    return result
                } ?? src
            : src
        let wordRe = try! NSRegularExpression(pattern: "\\b[\\w'-]+\\b")
        let words = wordRe.numberOfMatches(in: noFences, range: NSRange(noFences.startIndex..., in: noFences))
        let chars = src.count
        let lines = src.components(separatedBy: "\n").count
        let readMin = max(1, Int(round(Double(words) / 220.0)))
        return DocStats(words: words, chars: chars, lines: lines, readMin: readMin)
    }

    // MARK: SmartyPants
    //
    // Typographic substitutions applied to plain-text fragments only. Code
    // spans/blocks bypass this because they're tokenized first and their
    // substring is taken verbatim from `range(at: 1)`.
    private static func smartyPants(_ s: String) -> String {
        var t = s
        // Triple/double dashes — must run before single substitutions.
        t = t.replacingOccurrences(of: "---", with: "—")
        t = t.replacingOccurrences(of: "--",  with: "–")
        // Ellipsis
        t = t.replacingOccurrences(of: "...", with: "…")
        // Curly quotes — context-aware via simple before-character lookup.
        t = curlyQuotes(t)
        return t
    }

    /// Replace straight quotes with curly equivalents. Opening quote is used
    /// at start of string or after whitespace/open-paren; closing quote
    /// otherwise. Apostrophes follow the same single-quote rule.
    private static func curlyQuotes(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var prev: Character = " "
        for ch in s {
            switch ch {
            case "\"":
                let isOpener = prev.isWhitespace || prev == "(" || prev == "[" || prev == "{"
                out.append(isOpener ? "“" : "”")
            case "'":
                let isOpener = prev.isWhitespace || prev == "(" || prev == "[" || prev == "{"
                out.append(isOpener ? "‘" : "’")
            default:
                out.append(ch)
            }
            prev = ch
        }
        return out
    }

    static func slug(_ text: String) -> String {
        let re = try! NSRegularExpression(pattern: "[^a-z0-9]+")
        let lower = text.lowercased()
        let ns = lower as NSString
        let result = re.stringByReplacingMatches(
            in: lower, range: NSRange(location: 0, length: ns.length), withTemplate: "-")
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
