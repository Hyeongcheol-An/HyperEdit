import Foundation

/// themes/palettes.json 한 항목. 키 이름은 JSON(snake_case)과 1:1.
public struct Palette: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var appearance: String      // "dark" | "light"
    public var origin: String?
    public var bg: String
    public var fg: String
    public var accent: String
    public var bgAlt: String?
    public var bgElev: String?
    public var fgMuted: String?
    public var fgDim: String?
    public var border: String?
    public var selection: String?
    public var cursor: String?
    public var lineHl: String?
    public var ansi: [String: String]
    public var syntax: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, name, appearance, origin, bg, fg, accent, border, selection, cursor, ansi, syntax
        case bgAlt = "bg_alt", bgElev = "bg_elev", fgMuted = "fg_muted", fgDim = "fg_dim", lineHl = "line_hl"
    }

    public var isDark: Bool { appearance == "dark" }

    /// 리소스를 못 읽었을 때의 최후 수단 (터미널 Homebrew 팔레트).
    public static let fallback = Palette(
        id: "homebrew-terminal", name: "Hyper Homebrew Terminal", appearance: "dark", origin: nil,
        bg: "#010F1E", fg: "#00F900", accent: "#2F6BFF", bgAlt: "#010A15", bgElev: "#07192C",
        fgMuted: "#00A600", fgDim: "#0F6B22", border: "#0B2A44", selection: "#0C2EEEA6", cursor: "#38FE27", lineHl: "#04172B",
        ansi: ["red": "#990000", "green": "#00A600", "yellow": "#999900", "blue": "#0000B2", "magenta": "#B200B2", "cyan": "#00A6B2", "black": "#000000", "white": "#BFBFBF",
               "bright_red": "#E50000", "bright_green": "#00D900", "bright_yellow": "#E5E500", "bright_blue": "#0000FF"],
        syntax: ["comment": "#1F9F2F", "keyword": "#00E5E5", "string": "#E5E57A", "number": "#E5E5E5", "function": "#38FE27", "type": "#5FD7FF",
                 "variable": "#00F900", "constant": "#E500E5", "operator": "#BFBFBF", "punctuation": "#7FBF7F", "tag": "#00E5E5",
                 "attribute": "#E5E500", "property": "#B3FFB3", "link": "#5F87FF", "title": "#38FE27", "special": "#E5E500"])
}

public struct PaletteFile: Codable, Sendable {
    public var family: String
    public var author: String
    public var themes: [Palette]
}

/// 팔레트에서 유도한 실제 색 세트. 유도 규칙은 themes/build_zed_theme.py 와 동일하게 유지한다.
public struct Theme: Hashable, Sendable, Identifiable {
    public let palette: Palette
    public let background: RGBA
    public let backgroundAlt: RGBA
    public let backgroundElevated: RGBA
    public let foreground: RGBA
    public let foregroundMuted: RGBA
    public let foregroundDim: RGBA
    public let border: RGBA
    public let selection: RGBA
    public let cursor: RGBA
    public let lineHighlight: RGBA
    public let accent: RGBA
    public let ansi: [String: RGBA]
    public let syntax: [String: RGBA]

    public var id: String { palette.id }
    public var name: String { palette.name }
    public var isDark: Bool { palette.isDark }

    public init(palette p: Palette) {
        let dark = p.isDark
        let bg = RGBA(hex: p.bg) ?? (dark ? .black : .white)
        let fg = RGBA(hex: p.fg) ?? (dark ? .white : .black)
        func c(_ s: String?, _ fallback: @autoclosure () -> RGBA) -> RGBA { s.flatMap { RGBA(hex: $0) } ?? fallback() }
        let acc = c(p.accent, fg)
        palette = p
        background = bg
        foreground = fg
        accent = acc
        backgroundAlt = c(p.bgAlt, dark ? bg.mix(.black, 0.18) : bg.mix(.black, 0.04))
        backgroundElevated = c(p.bgElev, bg.mix(fg, 0.08))
        foregroundMuted = c(p.fgMuted, fg.mix(bg, 0.35))
        foregroundDim = c(p.fgDim, fg.mix(bg, 0.55))
        border = c(p.border, bg.mix(fg, 0.15))
        lineHighlight = c(p.lineHl, bg.mix(fg, 0.05))
        cursor = c(p.cursor, acc)
        selection = c(p.selection, acc.with(alpha: 0.30))
        ansi = p.ansi.compactMapValues { RGBA(hex: $0) }
        syntax = p.syntax.compactMapValues { RGBA(hex: $0) }
    }

    public func syntaxColor(_ key: String) -> RGBA { syntax[key] ?? foreground }
    public func ansiColor(_ key: String) -> RGBA { ansi[key] ?? foreground }

    public var errorColor: RGBA { ansi[isDark ? "bright_red" : "red"] ?? ansi["red"] ?? foreground }
    public var warningColor: RGBA { ansi[isDark ? "bright_yellow" : "yellow"] ?? ansi["yellow"] ?? foreground }
    public var successColor: RGBA { ansi[isDark ? "bright_green" : "green"] ?? ansi["green"] ?? foreground }
    public var infoColor: RGBA { ansi[isDark ? "bright_blue" : "blue"] ?? ansi["blue"] ?? accent }
}
