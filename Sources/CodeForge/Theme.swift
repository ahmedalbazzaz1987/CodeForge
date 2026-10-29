import AppKit
import CodeForgeKit

/// Editor colors. Every color adapts to light and dark mode.
enum Theme {
    static let background = dynamic(0xFFFFFF, 0x1F1F24)
    static let text = dynamic(0x1F1F24, 0xDCDCDC)
    static let currentLine = NSColor(name: nil) { $0.isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.045) }
    static let gutterText = NSColor.tertiaryLabelColor
    static let gutterCurrent = NSColor.secondaryLabelColor

    private static let comment = dynamic(0x5D6C79, 0x7F8C98)
    private static let string = dynamic(0xC41A16, 0xFC6A5D)
    private static let keyword = dynamic(0x9B2393, 0xFC5FA3)
    private static let type = dynamic(0x0B4F79, 0x5DD8FF)
    private static let number = dynamic(0x1C00CF, 0xD0BF69)
    private static let function = dynamic(0x326D74, 0x67B7A4)
    private static let attribute = dynamic(0x815F03, 0xFD8F3F)
    private static let tag = dynamic(0x0F68A0, 0x41A1C0)

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
        }
    }

    static func editorFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func dynamic(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { $0.isDark ? rgb(dark) : rgb(light) }
    }

    private static func rgb(_ hex: Int) -> NSColor {
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
