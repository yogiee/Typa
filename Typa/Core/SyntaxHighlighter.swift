import Foundation

// MARK: - Token

struct SyntaxToken {
    let type: String
    let text: String
}

// MARK: - Language detection

enum SyntaxHighlighter {

    static func langFromName(_ name: String) -> String? {
        let lower = name.lowercased()
        // Dockerfile has no extension
        if lower == "dockerfile" || lower.hasSuffix(".dockerfile") { return "dockerfile" }
        guard let ext = name.split(separator: ".").last?.lowercased() else { return nil }
        switch ext {
        case "js", "mjs", "cjs":        return "js"
        case "ts":                       return "ts"
        case "jsx":                      return "jsx"
        case "tsx":                      return "tsx"
        case "php":                      return "php"
        case "css", "scss":              return "css"
        case "html", "htm":              return "html"
        case "json":                     return "json"
        case "py":                       return "py"
        case "sh", "bash", "zsh":        return "sh"
        case "yml", "yaml":              return "yaml"
        case "toml":                     return "toml"
        case "xml", "svg", "plist":      return "xml"
        case "swift":                    return "swift"
        case "rb", "gemspec":            return "rb"
        case "sql":                      return "sql"
        case "rs":                       return "rs"
        case "go":                       return "go"
        case "ini", "conf", "cfg", "env": return "ini"
        default:                         return nil
        }
    }

    static let langNames: [String: String] = [
        "js": "JavaScript", "ts": "TypeScript", "tsx": "TSX", "jsx": "JSX",
        "php": "PHP", "css": "CSS", "html": "HTML", "json": "JSON",
        "py": "Python", "sh": "Shell", "md": "Markdown",
        "yaml": "YAML", "toml": "TOML", "xml": "XML",
        "swift": "Swift", "rb": "Ruby", "sql": "SQL",
        "rs": "Rust", "go": "Go", "ini": "Config", "dockerfile": "Dockerfile"
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

        case "yaml":
            rules.append(("comment", #"#[^\n]*"#))
            rules.append(("atrule", #"^---"#))
            rules.append(("tag", #"!!\w+"#))
            rules.append(("var", #"&\w+|\*\w+"#))
            rules.append(("bool", #"\b(?:true|false|yes|no|null|~)\b"#))
            rules.append(("prop", #"^\s*[\w.-]+(?=\s*:)"#))
            rules.append(("punc", #"[:\[\]{}|>,-]"#))

        case "toml":
            rules.append(("comment", #"#[^\n]*"#))
            rules.append(("atrule", #"\[\[?[^\]]+\]\]?"#))
            rules.append(("bool", #"\b(?:true|false)\b"#))
            rules.append(("prop", #"\b[\w.-]+(?=\s*=)"#))
            rules.append(("op", #"="#))
            rules.append(("punc", #"[{}\[\],]"#))

        case "xml":
            rules.append(("comment", #"<!--[\s\S]*?-->"#))
            rules.append(("string", #""[^"]*""#))
            rules.append(("atrule", #"<!\[CDATA\[[\s\S]*?\]\]>"#))
            rules.append(("atrule", #"<!DOCTYPE[^>]*>"#))
            rules.append(("atrule", #"<\?[\s\S]*?\?>"#))
            rules.append(("tag", #"</?[A-Za-z][\w:.]*"#))
            rules.append(("attr", #"\b[A-Za-z_:][\w:.-]*(?==)"#))
            rules.append(("punc", #"[<>/=]"#))

        case "swift":
            rules.append(("comment", #"///[^\n]*"#))
            rules.append(("comment", #"//[^\n]*"#))
            rules.append(("comment", #"/\*[\s\S]*?\*/"#))
            rules.append(("string", #""""[\s\S]*?""""#))
            rules.append(("atrule", #"@[A-Za-z_]\w*"#))
            rules.append(("keyword", kwPattern(kwSwift)))
            rules.append(("bool", #"\b(?:true|false|nil)\b"#))
            rules.append(("fn", #"\b[A-Za-z_]\w*(?=\s*\()"#))
            rules.append(("op", #"[=+\-*/%<>!&|^~?.:]+"#))
            rules.append(("punc", #"[{}()\[\];,]"#))

        case "rb":
            rules.append(("comment", #"#[^\n]*"#))
            rules.append(("string", #":[A-Za-z_]\w*"#))
            rules.append(("var", #"@@?[A-Za-z_]\w*|\$[A-Za-z_]\w*"#))
            rules.append(("keyword", kwPattern(kwRuby)))
            rules.append(("bool", #"\b(?:true|false|nil)\b"#))
            rules.append(("fn", #"\b[a-z_]\w*(?=\s*[\(!])"#))
            rules.append(("op", #"[=+\-*/%<>!&|^~?.:]+"#))
            rules.append(("punc", #"[{}()\[\];,]"#))

        case "sql":
            rules.append(("comment", #"--[^\n]*"#))
            rules.append(("comment", #"/\*[\s\S]*?\*/"#))
            rules.append(("keyword", kwPatternI(kwSQL)))
            rules.append(("bool", #"(?i)\b(?:true|false|null)\b"#))
            rules.append(("fn", #"(?i)\b[A-Za-z_]\w*(?=\s*\()"#))
            rules.append(("op", #"[=<>!]+"#))
            rules.append(("punc", #"[(),;]"#))

        case "rs":
            rules.append(("comment", #"///[^\n]*"#))
            rules.append(("comment", #"//[^\n]*"#))
            rules.append(("comment", #"/\*[\s\S]*?\*/"#))
            rules.append(("atrule", #"#!\??\[[^\]]*\]"#))
            rules.append(("fn", #"\b[a-z_]\w*!(?=\s*[(\[{])"#))
            rules.append(("keyword", kwPattern(kwRust)))
            rules.append(("bool", #"\b(?:true|false)\b"#))
            rules.append(("var", #"'[a-z_]+\b"#))
            rules.append(("fn", #"\b[A-Za-z_]\w*(?=\s*\()"#))
            rules.append(("op", #"[=+\-*/%<>!&|^~?.:]+|->|=>"#))
            rules.append(("punc", #"[{}()\[\];,]"#))

        case "go":
            rules.append(("comment", #"//[^\n]*"#))
            rules.append(("comment", #"/\*[\s\S]*?\*/"#))
            rules.append(("string", #"`[^`]*`"#))
            rules.append(("keyword", kwPattern(kwGo)))
            rules.append(("bool", #"\b(?:true|false|nil)\b"#))
            rules.append(("fn", #"\b[A-Za-z_]\w*(?=\s*\()"#))
            rules.append(("op", #"[=+\-*/%<>!&|^~?.:]+|<-|:="#))
            rules.append(("punc", #"[{}()\[\];,]"#))

        case "ini":
            rules.append(("comment", #"[#;][^\n]*"#))
            rules.append(("atrule", #"\[[^\]]+\]"#))
            rules.append(("prop", #"^[\s]*[\w.-]+(?=\s*[=:])"#))
            rules.append(("op", #"[=:]"#))

        case "dockerfile":
            rules.append(("comment", #"#[^\n]*"#))
            rules.append(("keyword", #"(?i)(?:^|\n)\s*(?:FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b"#))
            rules.append(("var", #"\$\{?[A-Za-z_]\w*\}?"#))
            rules.append(("op", #"[=]"#))

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

    private static let kwSwift = "actor any as associatedtype async await borrowing break case catch class consuming continue convenience default defer deinit didSet do else enum extension fallthrough false fileprivate final for func get guard if import in indirect infix init inout internal is isolated lazy let mutating nil nonisolated open operator override package postfix precedencegroup prefix private protocol public repeat required rethrows return self Self sending set some static struct subscript super switch throw throws true try type typealias unowned var where while willSet".split(separator: " ").map(String.init)

    private static let kwRuby = "alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield".split(separator: " ").map(String.init)

    private static let kwSQL = "add all alter and any as asc between by case cast check column constraint create cross database default delete desc distinct drop else end except exists false fetch foreign from full group having identity if in index inner insert intersect into is join key left like limit not null of on or order outer primary references rename replace return right rollback row rows select set some table then top true truncate union unique update use values view when where with".split(separator: " ").map(String.init)

    private static let kwRust = "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type union unsafe use where while".split(separator: " ").map(String.init)

    private static let kwGo = "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr append cap close copy delete len make new panic print println real recover".split(separator: " ").map(String.init)
}
