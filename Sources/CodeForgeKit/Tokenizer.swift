import Foundation

public struct Token: Equatable, Sendable {
    public let range: NSRange
    public let kind: TokenKind

    public init(range: NSRange, kind: TokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// Splits source text into highlight tokens with regular expressions.
///
/// Comments, strings and the language's extra patterns are matched first by one combined expression, so whichever
/// starts first wins (a `//` inside a string stays part of the string). Keywords, types, numbers and function names
/// are then looked up only in the gaps between those matches.
public final class Tokenizer: @unchecked Sendable {   // immutable after init; NSRegularExpression is thread-safe
    public let language: Language
    let main: NSRegularExpression?   // internal so tests can check it compiled
    private let groupKinds: [TokenKind]

    private static let word = try! NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*"#)
    private static let number = try! NSRegularExpression(
        pattern: #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#
    )

    public init(language: Language) {
        self.language = language
        var parts: [String] = []
        var kinds: [TokenKind] = []
        let esc = NSRegularExpression.escapedPattern(for:)
        if let block = language.blockComment {
            parts.append(esc(block.open) + #"[\s\S]*?(?:"# + esc(block.close) + #"|\z)"#)
            kinds.append(.comment)
        }
        for marker in language.lineComments {
            parts.append(esc(marker) + #"[^\n]*"#)
            kinds.append(.comment)
        }
        for extra in language.patterns {
            parts.append(extra.pattern)
            kinds.append(extra.kind)
        }
        for delimiter in language.strings.sorted(by: { $0.count > $1.count }) {
            let d = esc(delimiter)
            if delimiter.count > 1 || delimiter == "`" {
                parts.append(d + #"[\s\S]*?(?:"# + d + #"|\z)"#)
            } else {
                parts.append(d + #"(?:\\.|[^"# + d + #"\\\n])*"# + d + "?")
            }
            kinds.append(.string)
        }
        groupKinds = kinds
        main = parts.isEmpty ? nil : try? NSRegularExpression(
            pattern: parts.map { "(\($0))" }.joined(separator: "|"),
            options: [.anchorsMatchLines]
        )
    }

    public func tokens(in text: String) -> [Token] {
        let ns = text as NSString
        var result: [Token] = []
        var covered: [NSRange] = []
        main?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            for (index, kind) in groupKinds.enumerated() {
                let range = match.range(at: index + 1)
                guard range.location != NSNotFound else { continue }
                if range.length > 0 {
                    result.append(Token(range: range, kind: kind))
                    covered.append(match.range)
                }
                break
            }
        }

        var gapStart = 0
        for range in covered + [NSRange(location: ns.length, length: 0)] {
            if range.location > gapStart {
                scanWords(ns, in: NSRange(location: gapStart, length: range.location - gapStart), into: &result)
            }
            gapStart = max(gapStart, NSMaxRange(range))
        }
        return result
    }

    private func scanWords(_ ns: NSString, in gap: NSRange, into result: inout [Token]) {
        let text = ns as String
        Self.word.enumerateMatches(in: text, range: gap) { match, _, _ in
            guard let range = match?.range else { return }
            let word = ns.substring(with: range)
            let key = language.caseInsensitiveKeywords ? word.lowercased() : word
            let kind: TokenKind?
            if language.keywords.contains(key) {
                kind = .keyword
            } else if language.types.contains(word) {
                kind = .type
            } else if language.capitalizedTypes, let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) {
                kind = .type
            } else if NSMaxRange(range) < ns.length, ns.character(at: NSMaxRange(range)) == 0x28 /* ( */ {
                kind = .function
            } else {
                kind = nil
            }
            if let kind { result.append(Token(range: range, kind: kind)) }
        }
        guard language.highlightNumbers else { return }
        Self.number.enumerateMatches(in: text, range: gap) { match, _, _ in
            if let range = match?.range { result.append(Token(range: range, kind: .number)) }
        }
    }
}
