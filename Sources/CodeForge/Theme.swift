import AppKit
import CodeForgeKit

/// Editor and window colors from the chosen color theme (Tools ▸ Options). Every color adapts to light and dark mode.
enum Theme {
    /// The theme picked in Options; nil follows macOS with Light or Dark.
    static var active: ColorTheme? = ColorThemes.theme(id: UserDefaults.standard.string(forKey: "appearance"))

    static func palette(for appearance: NSAppearance) -> ColorTheme {
        active ?? (appearance.isDark ? ColorThemes.dark : ColorThemes.light)
    }

    // Editor
    static let background = themed(\.background)
    static let text = themed(\.text)
    static let currentLine = NSColor(name: nil) { palette(for: $0).isDark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.045) }
    static let gutterText = themed(\.gutterText)
    static let gutterCurrent = themed(\.gutterCurrent)

    // Window chrome
    static let sidebar = themed(\.sidebar)
    static let chrome = themed(\.chrome)
    static let separator = themed(\.separator)
    static let accent = themed(\.accent)
    /// The status bar's color: the accent, darkened when it's too light for white text (Monokai's green).
    static let statusAccent = NSColor(name: nil) { appearance in
        let hex = palette(for: appearance).accent
        let luminance = 0.2126 * Double((hex >> 16) & 0xFF) + 0.7152 * Double((hex >> 8) & 0xFF) + 0.0722 * Double(hex & 0xFF)
        return luminance > 140 ? rgb(hex).blended(withFraction: 0.45, of: .black) ?? rgb(hex) : rgb(hex)
    }
    static let statusIdle = rgb(0x68217A)       // no folder open
    static let statusBusy = rgb(0xCA5100)       // a program is running
    static let errorRed = dynamic(0xE51400, 0xF14C4C)
    static let warningYellow = dynamic(0xBF8803, 0xCCA700)
    static let lens = dynamic(0x8A8A8A, 0x7A7A7A)
    static let executionLine = NSColor(name: nil) { palette(for: $0).isDark ? NSColor(srgbRed: 0.45, green: 0.42, blue: 0.0, alpha: 0.45) : NSColor(srgbRed: 1, green: 0.93, blue: 0.4, alpha: 0.7) }
    static let searchMatch = NSColor(name: nil) { palette(for: $0).isDark ? NSColor(srgbRed: 0.38, green: 0.30, blue: 0.10, alpha: 1) : NSColor(srgbRed: 1, green: 0.85, blue: 0.45, alpha: 1) }

    private static var tokenColors: [TokenKind: NSColor] = [:]

    static func color(for kind: TokenKind) -> NSColor {
        if let color = tokenColors[kind] { return color }
        let color = NSColor(name: nil) { rgb(palette(for: $0).color(for: kind)) }
        tokenColors[kind] = color
        return color
    }

    static func editorFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func themed(_ key: KeyPath<ColorTheme, Int>) -> NSColor {
        NSColor(name: nil) { rgb(palette(for: $0)[keyPath: key]) }
    }

    private static func dynamic(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { palette(for: $0).isDark ? rgb(dark) : rgb(light) }
    }

    static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Small modal dialogs.
enum Prompt {
    static func ask(_ title: String, message: String = "", defaultValue: String = "", confirm: String = "OK") -> String? {
        #if DEBUG
        if let answer = ProcessInfo.processInfo.environment["CF_ANSWER"] { return answer.isEmpty ? defaultValue : answer }
        #endif
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    static func confirm(_ title: String, message: String, button: String) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CF_ANSWER"] != nil { return true }
        #endif
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func show(_ title: String, message: String, style: NSAlert.Style = .warning) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CF_ANSWER"] != nil { return print("ALERT:", title, "—", message) }
        #endif
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
