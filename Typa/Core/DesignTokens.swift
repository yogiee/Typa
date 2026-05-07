import SwiftUI
import AppKit

// MARK: - Color init from hex

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Design tokens

enum DesignTokens {

    // MARK: Background colors

    static func bg(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x15171a) : Color(hex: 0xf7f6f2)
    }
    static func bgElev(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x1b1d20) : Color(hex: 0xfbfaf6)
    }
    static func bgPane(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x1d1f22) : Color(hex: 0xfefdfa)
    }
    static func bgSide(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x131517) : Color(hex: 0xefece5)
    }
    static func bgTab(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x232629) : Color(hex: 0xe9e6df)
    }
    static func codeBg(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x232629) : Color(hex: 0xece9e2)
    }
    static func quoteBg(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x1f2124) : Color(hex: 0xf0ede5)
    }

    // MARK: Foreground colors

    static func fg(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0xe6e4df) : Color(hex: 0x1f1d1a)
    }
    static func fgSoft(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0xc2bfb8) : Color(hex: 0x4a4742)
    }
    static func fgMute(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x888680) : Color(hex: 0x8a8780)
    }
    static func fgFaint(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x555350) : Color(hex: 0xb5b1a9)
    }

    // MARK: Line/border colors

    static func line(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 30/255, green: 28/255, blue: 25/255).opacity(0.10)
    }
    static func lineStrong(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color(red: 30/255, green: 28/255, blue: 25/255).opacity(0.18)
    }

    // MARK: Typography

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "JetBrains Mono", size: size) != nil {
            return Font.custom("JetBrains Mono", size: size).weight(weight)
        }
        return Font.system(size: size, weight: weight, design: .monospaced)
    }
    /// Monospaced font for the editor. Resolves the user's selection by name,
    /// falls back to JetBrains Mono, then to the system monospaced font.
    static func monoFont(size: CGFloat,
                          name: String? = nil,
                          weight: NSFont.Weight = .regular) -> NSFont {
        if let name = name, !name.isEmpty,
           let f = NSFont(name: name, size: size) { return f }
        return NSFont(name: "JetBrains Mono", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Editor line height. Defaults to the layout manager's natural line
    /// height for the configured font; the optional `multiplier` lets the
    /// user loosen line spacing without breaking gutter/highlight alignment.
    static func lineHeight(for fontSize: CGFloat,
                            fontName: String? = nil,
                            multiplier: CGFloat = 1.0) -> CGFloat {
        let font = monoFont(size: fontSize, name: fontName)
        return ceil(NSLayoutManager().defaultLineHeight(for: font) * multiplier)
    }

    // MARK: Shadows

    static let shadowSm = Color.black.opacity(0.04)
    static let shadowMd = Color.black.opacity(0.08)
    static let shadowLg = Color.black.opacity(0.18)
}

// MARK: - Accent colors

enum AccentName: String, CaseIterable, Codable {
    case teal, amber, violet, rose

    func color(isDark: Bool) -> Color {
        switch self {
        case .teal:
            return isDark
                ? Color(.sRGB, red: 0.344, green: 0.690, blue: 0.668)
                : Color(.sRGB, red: 0.316, green: 0.547, blue: 0.548)
        case .amber:
            return isDark
                ? Color(.sRGB, red: 0.872, green: 0.652, blue: 0.345)
                : Color(.sRGB, red: 0.708, green: 0.499, blue: 0.242)
        case .violet:
            return isDark
                ? Color(.sRGB, red: 0.612, green: 0.573, blue: 0.864)
                : Color(.sRGB, red: 0.404, green: 0.356, blue: 0.630)
        case .rose:
            return isDark
                ? Color(.sRGB, red: 0.902, green: 0.521, blue: 0.552)
                : Color(.sRGB, red: 0.685, green: 0.355, blue: 0.390)
        }
    }

    var displayName: String { rawValue.capitalized }
}

// MARK: - Syntax colors

struct SyntaxColors {
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let fn: Color
    let tag: Color
    let attr: Color
    let prop: Color
    let punc: Color
    let op: Color
    let builtin: Color
    let varColor: Color
    let selector: Color
    let atrule: Color
    let bool: Color

    static func forScheme(_ colorScheme: ColorScheme) -> SyntaxColors {
        let dark = colorScheme == .dark
        return SyntaxColors(
            keyword:  dark ? Color(hex: 0xd289c9) : Color(hex: 0xa23b8a),
            string:   dark ? Color(hex: 0x88c69b) : Color(hex: 0x1f7a4d),
            number:   dark ? Color(hex: 0xe0a572) : Color(hex: 0x9a4d00),
            comment:  dark ? Color(hex: 0x6a6862) : Color(hex: 0x8a8780),
            fn:       dark ? Color(hex: 0x7eb1f0) : Color(hex: 0x2b5fb8),
            tag:      dark ? Color(hex: 0xd289c9) : Color(hex: 0xa23b8a),
            attr:     dark ? Color(hex: 0x7eb1f0) : Color(hex: 0x2b5fb8),
            prop:     dark ? Color(hex: 0x7eb1f0) : Color(hex: 0x2b5fb8),
            punc:     dark ? Color(hex: 0x888680) : Color(hex: 0x6a6862),
            op:       dark ? Color(hex: 0x9a9892) : Color(hex: 0x6a6862),
            builtin:  dark ? Color(hex: 0xd289c9) : Color(hex: 0xa23b8a),
            varColor: dark ? Color(hex: 0xe6e4df) : Color(hex: 0x1f1d1a),
            selector: dark ? Color(hex: 0xd289c9) : Color(hex: 0xa23b8a),
            atrule:   dark ? Color(hex: 0xe0a572) : Color(hex: 0x9a4d00),
            bool:     dark ? Color(hex: 0xe0a572) : Color(hex: 0x9a4d00)
        )
    }

    func color(for type: String) -> Color? {
        switch type {
        case "keyword":  return keyword
        case "string":   return string
        case "number":   return number
        case "comment":  return comment
        case "fn":       return fn
        case "tag":      return tag
        case "attr":     return attr
        case "prop":     return prop
        case "punc":     return punc
        case "op":       return op
        case "builtin":  return builtin
        case "var":      return varColor
        case "selector": return selector
        case "atrule":   return atrule
        case "bool":     return bool
        default:         return nil
        }
    }
}

// MARK: - App theme

enum AppTheme: String, CaseIterable, Codable {
    case light, dark, system

    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

// MARK: - Spacing constants

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
