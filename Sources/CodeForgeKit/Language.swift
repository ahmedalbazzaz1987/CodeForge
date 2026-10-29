import Foundation

/// What a highlighted piece of source text is.
public enum TokenKind: Sendable, Equatable {
    case comment, string, keyword, type, number, function, attribute, tag, heading
}

/// A language CodeForge can highlight and (optionally) run.
public struct Language: Sendable {
    public var id: String
    public var name: String
    public var extensions: [String]
    /// Exact file names that select this language (e.g. "Makefile").
    public var fileNames: [String]
    public var lineComments: [String]
    public var blockComment: (open: String, close: String)?
    /// String delimiters. Delimiters longer than one character, and the backtick, may span lines.
    public var strings: [String]
    public var keywords: Set<String>
    public var types: Set<String>
    public var caseInsensitiveKeywords: Bool
    /// Identifiers that start with an uppercase letter are shown as types.
    public var capitalizedTypes: Bool
    public var highlightNumbers: Bool
    /// Extra regular expressions, matched together with comments and strings (use non-capturing groups only).
    public var patterns: [(pattern: String, kind: TokenKind)]
    public var indentWithTabs: Bool
    public var indentAfterColon: Bool
    /// Shell command that runs a file. Placeholders: {file} {dir} {name} {out} (see `CommandTemplate`).
    public var runCommand: String?
    /// Shown when the run command's tool is missing.
    public var installHint: String?

    public init(
        id: String, name: String, extensions: [String], fileNames: [String] = [],
        lineComments: [String] = [], blockComment: (open: String, close: String)? = nil,
        strings: [String] = ["\"", "'"], keywords: String = "", types: String = "",
        caseInsensitiveKeywords: Bool = false, capitalizedTypes: Bool = true, highlightNumbers: Bool = true,
        patterns: [(pattern: String, kind: TokenKind)] = [], indentWithTabs: Bool = false, indentAfterColon: Bool = false,
        runCommand: String? = nil, installHint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.extensions = extensions
        self.fileNames = fileNames
        self.lineComments = lineComments
        self.blockComment = blockComment
        self.strings = strings
        let words = keywords.split(whereSeparator: \.isWhitespace).map(String.init)
        self.keywords = Set(caseInsensitiveKeywords ? words.map { $0.lowercased() } : words)
        self.types = Set(types.split(whereSeparator: \.isWhitespace).map(String.init))
        self.caseInsensitiveKeywords = caseInsensitiveKeywords
        self.capitalizedTypes = capitalizedTypes
        self.highlightNumbers = highlightNumbers
        self.patterns = patterns
        self.indentWithTabs = indentWithTabs
        self.indentAfterColon = indentAfterColon
        self.runCommand = runCommand
        self.installHint = installHint
    }
}
