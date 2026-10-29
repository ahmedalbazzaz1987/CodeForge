import AppKit
import CodeForgeKit

/// Editor colors. Every color adapts to light and dark mode.
enum Theme {
    // Editor (Visual Studio-style light and dark palettes)
    static let background = dynamic(0xFFFFFF, 0x1E1E1E)
    static let text = dynamic(0x1E1E1E, 0xD4D4D4)
    static let currentLine = NSColor(name: nil) { $0.isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.045) }
    static let gutterText = dynamic(0x2B91AF, 0x858585)
    static let gutterCurrent = dynamic(0x0B216F, 0xC6C6C6)

    // Window chrome
    static let sidebar = dynamic(0xF5F5F5, 0x252526)
    static let chrome = dynamic(0xEEEEF2, 0x2D2D30)
    static let separator = dynamic(0xCCCEDB, 0x3F3F46)
    static let accent = rgb(0x007ACC)
    static let statusIdle = rgb(0x68217A)       // no folder open
    static let statusBusy = rgb(0xCA5100)       // a program is running
    static let errorRed = dynamic(0xE51400, 0xF14C4C)
    static let warningYellow = dynamic(0xBF8803, 0xCCA700)
    static let lens = dynamic(0x8A8A8A, 0x7A7A7A)
    static let executionLine = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.45, green: 0.42, blue: 0.0, alpha: 0.45) : NSColor(srgbRed: 1, green: 0.93, blue: 0.4, alpha: 0.7) }

    private static let comment = dynamic(0x008000, 0x6A9955)
    private static let string = dynamic(0xA31515, 0xCE9178)
    private static let keyword = dynamic(0x0000FF, 0x569CD6)
    private static let type = dynamic(0x2B91AF, 0x4EC9B0)
    private static let number = dynamic(0x098658, 0xB5CEA8)
    private static let function = dynamic(0x74531F, 0xDCDCAA)
    private static let attribute = dynamic(0x001080, 0x9CDCFE)
    private static let tag = dynamic(0x800000, 0x569CD6)
    private static let inserted = dynamic(0x22863A, 0x73C991)
    private static let deleted = dynamic(0xCB2431, 0xF14C4C)

    static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .comment: comment
        case .string: string
        case .keyword, .heading: keyword
        case .type: type
        case .number: number
        case .function: function
        case .attribute: attribute
        case .tag: tag
        case .inserted: inserted
        case .deleted: deleted
        }
    }

    static func editorFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func dynamic(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { $0.isDark ? rgb(dark) : rgb(light) }
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
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func show(_ title: String, message: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
