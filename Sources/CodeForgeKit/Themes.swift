import Foundation

/// A color theme for the editor and the window chrome (Tools ▸ Options ▸ Color theme). Colors are 0xRRGGBB.
public struct ColorTheme: Sendable, Equatable {
    public let id: String
    public let name: String
    public let isDark: Bool
    public let background, text, gutterText, gutterCurrent: Int
    public let sidebar, chrome, separator, accent: Int
    public let comment, string, keyword, type, number, function, attribute, tag: Int

    public func color(for kind: TokenKind) -> Int {
        switch kind {
        case .comment: comment
        case .string: string
        case .keyword, .heading: keyword
        case .type: type
        case .number: number
        case .function: function
        case .attribute: attribute
        case .tag: tag
        case .inserted: isDark ? 0x73C991 : 0x22863A
        case .deleted: isDark ? 0xF14C4C : 0xCB2431
        }
    }
}

public enum ColorThemes {
    public static let light = ColorTheme(
        id: "light", name: "Light", isDark: false,
        background: 0xFFFFFF, text: 0x1E1E1E, gutterText: 0x2B91AF, gutterCurrent: 0x0B216F,
        sidebar: 0xF5F5F5, chrome: 0xEEEEF2, separator: 0xCCCEDB, accent: 0x007ACC,
        comment: 0x008000, string: 0xA31515, keyword: 0x0000FF, type: 0x2B91AF, number: 0x098658, function: 0x74531F, attribute: 0x001080, tag: 0x800000)

    public static let dark = ColorTheme(
        id: "dark", name: "Dark", isDark: true,
        background: 0x1E1E1E, text: 0xD4D4D4, gutterText: 0x858585, gutterCurrent: 0xC6C6C6,
        sidebar: 0x252526, chrome: 0x2D2D30, separator: 0x3F3F46, accent: 0x007ACC,
        comment: 0x6A9955, string: 0xCE9178, keyword: 0x569CD6, type: 0x4EC9B0, number: 0xB5CEA8, function: 0xDCDCAA, attribute: 0x9CDCFE, tag: 0x569CD6)

    public static let blue = ColorTheme(
        id: "blue", name: "Blue", isDark: false,
        background: 0xFFFFFF, text: 0x1E1E1E, gutterText: 0x2B91AF, gutterCurrent: 0x0B216F,
        sidebar: 0xF0F3FA, chrome: 0xCCD5F0, separator: 0x8E9BBC, accent: 0x0E639C,
        comment: 0x008000, string: 0xA31515, keyword: 0x0000FF, type: 0x2B91AF, number: 0x098658, function: 0x74531F, attribute: 0x001080, tag: 0x800000)

    public static let highContrast = ColorTheme(
        id: "high-contrast", name: "High Contrast", isDark: true,
        background: 0x000000, text: 0xFFFFFF, gutterText: 0xFFFFFF, gutterCurrent: 0xFFFF00,
        sidebar: 0x000000, chrome: 0x000000, separator: 0x6FC3DF, accent: 0x1AEBFF,
        comment: 0x7CA668, string: 0xFFD68F, keyword: 0x569CD6, type: 0x4EC9B0, number: 0xB5CEA8, function: 0xDCDCAA, attribute: 0x9CDCFE, tag: 0x569CD6)

    public static let monokai = ColorTheme(
        id: "monokai", name: "Monokai", isDark: true,
        background: 0x272822, text: 0xF8F8F2, gutterText: 0x90908A, gutterCurrent: 0xF8F8F2,
        sidebar: 0x22231F, chrome: 0x1E1F1C, separator: 0x3E3D32, accent: 0xA6E22E,
        comment: 0x75715E, string: 0xE6DB74, keyword: 0xF92672, type: 0x66D9EF, number: 0xAE81FF, function: 0xA6E22E, attribute: 0xFD971F, tag: 0xF92672)

    public static let dracula = ColorTheme(
        id: "dracula", name: "Dracula", isDark: true,
        background: 0x282A36, text: 0xF8F8F2, gutterText: 0x6272A4, gutterCurrent: 0xF8F8F2,
        sidebar: 0x21222C, chrome: 0x191A21, separator: 0x44475A, accent: 0xBD93F9,
        comment: 0x6272A4, string: 0xF1FA8C, keyword: 0xFF79C6, type: 0x8BE9FD, number: 0xBD93F9, function: 0x50FA7B, attribute: 0xFFB86C, tag: 0xFF79C6)

    public static let solarizedDark = ColorTheme(
        id: "solarized-dark", name: "Solarized Dark", isDark: true,
        background: 0x002B36, text: 0x93A1A1, gutterText: 0x586E75, gutterCurrent: 0x93A1A1,
        sidebar: 0x073642, chrome: 0x073642, separator: 0x0F4B5A, accent: 0x268BD2,
        comment: 0x586E75, string: 0x2AA198, keyword: 0x859900, type: 0xB58900, number: 0xD33682, function: 0x268BD2, attribute: 0xCB4B16, tag: 0x268BD2)

    public static let solarizedLight = ColorTheme(
        id: "solarized-light", name: "Solarized Light", isDark: false,
        background: 0xFDF6E3, text: 0x586E75, gutterText: 0x93A1A1, gutterCurrent: 0x586E75,
        sidebar: 0xEEE8D5, chrome: 0xEEE8D5, separator: 0xD3CBB7, accent: 0x268BD2,
        comment: 0x93A1A1, string: 0x2AA198, keyword: 0x859900, type: 0xB58900, number: 0xD33682, function: 0x268BD2, attribute: 0xCB4B16, tag: 0x268BD2)

    /// In the order shown in Options. "system" (Light or Dark, following macOS) comes first and isn't a theme of its own.
    public static let all: [ColorTheme] = [light, dark, blue, highContrast, monokai, dracula, solarizedDark, solarizedLight]

    public static func theme(id: String?) -> ColorTheme? { all.first { $0.id == id } }
}
