import Foundation

/// A part of a snippet: plain text, or a field to fill in (Tab moves between fields).
public struct SnippetPart: Sendable, Equatable {
    /// The field's number: 1, 2… in Tab order; 0 is where the caret ends up. Text parts have -1.
    public let index: Int
    /// The text, or the field's placeholder.
    public let text: String

    public var isField: Bool { index >= 0 }
}

/// A field's place in the expanded snippet (UTF-16 offsets).
public struct SnippetField: Sendable, Equatable {
    public var index: Int
    public var location: Int
    public var length: Int

    public init(index: Int, location: Int, length: Int) {
        self.index = index
        self.location = location
        self.length = length
    }

    public var range: NSRange { NSRange(location: location, length: length) }
}

/// Snippets with fields to fill in, in the syntax Visual Studio Code and language servers use: `$1`, `${1:name}`,
/// `${1|a,b|}` (the first choice) and `$0` for where the caret ends up. A number used twice is the same field: typing in the
/// first copy changes the others. Snippets with only `$0` (the older syntax) work as before, and a `$` that isn't followed by
/// a number (PHP variables, JavaScript `${name}`) stays as it is.
public enum SnippetTemplate {
    public static func parse(_ body: String) -> [SnippetPart] {
        let ns = body as NSString
        var parts: [SnippetPart] = []
        var text = ""
        func flush() {
            if !text.isEmpty { parts.append(SnippetPart(index: -1, text: text)) }
            text = ""
        }
        func isDigit(_ i: Int) -> Bool { i < ns.length && (0x30...0x39).contains(ns.character(at: i)) }
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 0x5C, i + 1 < ns.length, [0x24, 0x7D].contains(ns.character(at: i + 1)) {   // \$ and \}
                text += ns.substring(with: NSRange(location: i + 1, length: 1))
                i += 2
                continue
            }
            if c == 0x24, isDigit(i + 1) {   // $1
                var j = i + 1
                while isDigit(j) { j += 1 }
                flush()
                parts.append(SnippetPart(index: Int(ns.substring(with: NSRange(location: i + 1, length: j - i - 1))) ?? 0, text: ""))
                i = j
                continue
            }
            if c == 0x24, i + 2 < ns.length, ns.character(at: i + 1) == 0x7B, isDigit(i + 2) {   // ${1…}
                var j = i + 2
                while isDigit(j) { j += 1 }
                let index = Int(ns.substring(with: NSRange(location: i + 2, length: j - i - 2))) ?? 0
                if j < ns.length, ns.character(at: j) == 0x7D {
                    flush()
                    parts.append(SnippetPart(index: index, text: ""))
                    i = j + 1
                    continue
                }
                if j < ns.length, [0x3A, 0x7C].contains(ns.character(at: j)), let end = closing(ns, from: j + 1) {
                    let inner = ns.substring(with: NSRange(location: j + 1, length: end - j - 1))
                    let placeholder: String
                    if ns.character(at: j) == 0x7C {
                        placeholder = String(inner.trimmingCharacters(in: CharacterSet(charactersIn: "|")).split(separator: ",", omittingEmptySubsequences: false).first ?? "")
                    } else {
                        // A placeholder with fields inside becomes plain text: ${1:foo(${2:x})} → foo(x).
                        placeholder = parse(inner).map(\.text).joined()
                    }
                    flush()
                    parts.append(SnippetPart(index: index, text: placeholder))
                    i = end + 1
                    continue
                }
            }
            text += ns.substring(with: NSRange(location: i, length: 1))
            i += 1
        }
        flush()
        // Copies of a field show the same placeholder: ${1:i} … $1 is i … i.
        var placeholders: [Int: String] = [:]
        for part in parts where part.isField && !part.text.isEmpty && placeholders[part.index] == nil { placeholders[part.index] = part.text }
        return parts.map { $0.isField && $0.text.isEmpty ? SnippetPart(index: $0.index, text: placeholders[$0.index] ?? "") : $0 }
    }

    /// The `}` that closes a placeholder starting at `from` (braces inside are counted).
    private static func closing(_ ns: NSString, from: Int) -> Int? {
        var depth = 1
        var i = from
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 0x5C, i + 1 < ns.length { i += 2; continue }
            if c == 0x7B { depth += 1 }
            if c == 0x7D { depth -= 1; if depth == 0 { return i } }
            i += 1
        }
        return nil
    }

    /// The snippet's text as inserted at a line indented with `indent`, and where its fields are.
    public static func expand(_ body: String, indent: String = "") -> (text: String, fields: [SnippetField]) {
        var text = ""
        var length = 0
        var fields: [SnippetField] = []
        for part in parse(body) {
            let piece = part.text.replacingOccurrences(of: "\n", with: "\n" + indent)
            let pieceLength = (piece as NSString).length
            if part.isField { fields.append(SnippetField(index: part.index, location: length, length: pieceLength)) }
            text += piece
            length += pieceLength
        }
        return (text, fields)
    }

    /// Whether the snippet has fields to Tab through (more than a caret position).
    public static func hasFields(_ body: String) -> Bool { parse(body).contains { $0.index > 0 } }

    /// The plain text, as inserted when the snippet isn't expanded (fields keep their placeholders).
    public static func plainText(_ body: String) -> String { expand(body).text }
}

/// A snippet being filled in: which field Tab is on, where the fields are as the text around them changes, and the edits that
/// keep copies of a field the same as the field.
public struct SnippetSession: Sendable {
    public private(set) var fields: [SnippetField]
    /// The field numbers in Tab order: 1, 2, 3…, then 0 (the final caret) if the snippet has it.
    private let order: [Int]
    public private(set) var position = 0

    /// A session for a snippet inserted at `base`; nil when it has nothing to Tab through.
    public init?(fields: [SnippetField], base: Int) {
        guard fields.contains(where: { $0.index > 0 }) else { return nil }
        self.fields = fields.map { SnippetField(index: $0.index, location: $0.location + base, length: $0.length) }
        let numbers = Set(fields.map(\.index))
        order = numbers.filter { $0 > 0 }.sorted() + (numbers.contains(0) ? [0] : [])
    }

    public var currentIndex: Int { order[position] }

    /// The field Tab is on (its first copy).
    public var current: NSRange { primary(currentIndex)?.range ?? NSRange(location: 0, length: 0) }

    private func primary(_ index: Int) -> SnippetField? { fields.first { $0.index == index } }

    /// Whether the session is on its last stop (the final caret, or the last field when there's no `$0`).
    public var isAtEnd: Bool { position == order.count - 1 }

    /// Moves to the next field; false when there's none left (the snippet is done).
    public mutating func next() -> Bool {
        guard position + 1 < order.count else { return false }
        position += 1
        return true
    }

    public mutating func previous() -> Bool {
        guard position > 0 else { return false }
        position -= 1
        return true
    }

    /// The text changed: `range` was replaced by `length` characters. Fields after it move; the field it's in grows or
    /// shrinks. Returns false when the edit crosses a field's edge, which ends the session.
    public mutating func edit(_ range: NSRange, replacementLength length: Int) -> Bool {
        let delta = length - range.length
        // The field the edit is in: the current field's copy first (typing into an empty field at its edge).
        let inside = fields.indices.filter { fields[$0].location <= range.location && NSMaxRange(range) <= fields[$0].location + fields[$0].length }
        let owner = inside.first { fields[$0].index == currentIndex } ?? inside.first
        for i in fields.indices {
            if i == owner {
                fields[i].length += delta
            } else if fields[i].location >= NSMaxRange(range), !(fields[i].location == range.location && range.length == 0 && owner == nil && fields[i].length > 0) {
                fields[i].location += delta
            } else if fields[i].location + fields[i].length <= range.location {
                continue
            } else if owner != nil, fields[i].location == range.location, range.length == 0 {
                fields[i].location += delta   // an empty field right where the owner's text was inserted
            } else {
                return false
            }
        }
        return true
    }

    /// The replacements that make the copies of the current field read like the field itself (last first).
    public func mirrorEdits(in text: NSString) -> [(range: NSRange, text: String)] {
        guard let field = primary(currentIndex), NSMaxRange(field.range) <= text.length else { return [] }
        let value = text.substring(with: field.range)
        return fields.filter { $0.index == currentIndex && $0.location != field.location }
            .filter { NSMaxRange($0.range) <= text.length && text.substring(with: $0.range) != value }
            .sorted { $0.location > $1.location }
            .map { ($0.range, value) }
    }
}
