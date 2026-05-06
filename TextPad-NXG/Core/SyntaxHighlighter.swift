import Foundation

// MARK: - Token

struct SyntaxToken {
    let type: String
    let text: String
}

// MARK: - Language detection

enum SyntaxHighlighter {

    static func langFromName(_ name: String) -> String? {
        guard let ext = name.split(separator: ".").last?.lowercased() else { return nil }
        switch ext {
        case "js", "mjs", "cjs": return "js"
        case "ts":                return "ts"
        case "jsx":               return "jsx"
        case "tsx":               return "tsx"
        case "php":               return "php"
        case "css", "scss":       return "css"
        case "html", "htm":       return "html"
        case "json":              return "json"
        case "py":                return "py"
        case "sh", "bash", "zsh": return "sh"
        default:                  return nil
        }
    }

    static let langNames: [String: String] = [
        "js": "JavaScript", "ts": "TypeScript", "tsx": "TSX", "jsx": "JSX",
        "php": "PHP", "css": "CSS", "html": "HTML", "json": "JSON",
        "py": "Python", "sh": "Shell", "md": "Markdown"
    ]

    // MARK: - Tokenizer

    static func tokenize(_ src: String, lang: String) -> [SyntaxToken] {
        let rules = buildRules(lang: lang)
        var out: [SyntaxToken] = []
        var idx = src.startIndex

        while idx < src.endIndex {
            let slice = String(src[idx...])
            var best: SyntaxToken? = nil

            for (type, pattern) in rules {
                guard let range = slice.range(of: pattern, options: .regularExpression),
                      range.lowerBound == slice.startIndex else { continue }
                let matched = String(slice[range])
                if best == nil || matched.count > best!.text.count {
                    best = SyntaxToken(type: type, text: matched)
                }
            }

            if let tok = best {
                out.append(tok)
                idx = src.index(idx, offsetBy: tok.text.count)
                continue
            }

            // identifier-ish run
            if let range = slice.range(of: #"^[A-Za-z_$][\w$]*"#, options: .regularExpression),
               range.lowerBound == slice.startIndex {
                let text = String(slice[range])
                out.append(SyntaxToken(type: "var", text: text))
                idx = src.index(idx, offsetBy: text.count)
                continue
            }

            // single char (plain)
            out.append(SyntaxToken(type: "plain", text: String(src[idx])))
            idx = src.index(after: idx)
        }
        return out
    }

    // MARK: - Rule sets (ordered: most specific first)

    private static func buildRules(lang: String) -> [(String, String)] {
        var rules: [(String, String)] = []

        // comments
        if ["js","ts","jsx","tsx","php","css"].contains(lang) {
            rules.append(("comment", #"//[^\n]*"#))
            rules.append(("comment", #"/\*[\s\S]*?\*/"#))
        }
        if lang == "py" || lang == "sh" { rules.append(("comment", #"#[^\n]*"#)) }
        if lang == "html" { rules.append(("comment", #"<!--[\s\S]*?-->"#)) }

        // strings
        rules.append(("string", #""(?:\\.|[^"\\\n])*""#))
        rules.append(("string", #"'(?:\\.|[^'\\\n])*'"#))
        if ["js","ts","jsx","tsx"].contains(lang) {
            rules.append(("string", #"`(?:\\.|[^`\\])*`"#))
        }

        // numbers
        rules.append(("number", #"\b\d+(?:\.\d+)?\b"#))

        switch lang {
        case "js", "jsx":
            rules.append(("keyword", kwPattern(kwJS)))
            rules.append(("bool", #"\b(?:true|false|null|undefined)\b"#))
            rules.append(("fn", #"\b[A-Za-z_$][\w$]*(?=\s*\()"#))
            rules.append(("op", #"[=+\-*/%<>!&|^~?:]+"#))
            rules.append(("punc", #"[{}()\[\];,.]"#))

        case "ts", "tsx":
            rules.append(("keyword", kwPattern(kwTS)))
            rules.append(("bool", #"\b(?:true|false|null|undefined)\b"#))
            rules.append(("fn", #"\b[A-Za-z_$][\w$]*(?=\s*\()"#))
            rules.append(("op", #"[=+\-*/%<>!&|^~?:]+"#))
            rules.append(("punc", #"[{}()\[\];,.]"#))

        case "php":
            rules.append(("keyword", kwPatternI(kwPHP)))
            rules.append(("var", #"\$[A-Za-z_]\w*"#))
            rules.append(("fn", #"\b[A-Za-z_]\w*(?=\s*\()"#))
            rules.append(("op", #"->|=>|::|[=+\-*/%<>!&|^~?:.]+"#))
            rules.append(("punc", #"[{}()\[\];,]"#))
            rules.append(("tag", #"<\?php|\?>"#))

        case "py":
            rules.append(("keyword", kwPattern(kwPY)))
            rules.append(("fn", #"\b[A-Za-z_]\w*(?=\s*\()"#))
            rules.append(("op", #"[=+\-*/%<>!&|^~]+"#))
            rules.append(("punc", #"[{}()\[\]:,.]"#))

        case "css":
            rules.append(("atrule", #"@[\w-]+"#))
            rules.append(("prop", #"\b[\w-]+(?=\s*:)"#))
            rules.append(("fn", #"\b[a-z-]+(?=\()"#))
            rules.append(("punc", #"[{}();,]"#))
            rules.append(("op", #"[:>~+]"#))

        case "json":
            rules.append(("prop", #""(?:[^"\\]|\\.)*"(?=\s*:)"#))
            rules.append(("bool", #"\b(?:true|false|null)\b"#))
            rules.append(("punc", #"[{}\[\],:]"#))

        case "html":
            rules.append(("tag", #"</?[A-Za-z][\w-]*"#))
            rules.append(("attr", #"\b[a-z-]+(?==)"#))
            rules.append(("punc", #"[<>=/]"#))

        case "sh":
            rules.append(("keyword", #"\b(?:if|then|else|elif|fi|for|in|do|done|while|case|esac|function|return|export|local|read|echo)\b"#))
            rules.append(("var", #"\$\{?[A-Za-z_]\w*\}?"#))
            rules.append(("op", #"[=|&;<>]+"#))
            rules.append(("punc", #"[{}()\[\]]"#))

        default:
            break
        }
        return rules
    }

    private static func kwPattern(_ words: [String]) -> String {
        "\\b(?:\(words.joined(separator: "|")))\\b"
    }
    private static func kwPatternI(_ words: [String]) -> String {
        "(?i)\\b(?:\(words.joined(separator: "|")))\\b"
    }

    private static let kwJS = "break case catch class const continue debugger default delete do else export extends finally for from function if import in instanceof let new null of return static super switch this throw true false try typeof undefined var void while with yield async await as".split(separator: " ").map(String.init)

    private static let kwTS = kwJS + "interface type enum implements public private protected readonly abstract namespace module declare".split(separator: " ").map(String.init)

    private static let kwPHP = "abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new null or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield true false self parent".split(separator: " ").map(String.init)

    private static let kwPY = "False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield".split(separator: " ").map(String.init)
}
