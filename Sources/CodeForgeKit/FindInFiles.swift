import Foundation

/// Edit ▸ Find and Replace ▸ Find in Files: searches every text file in a folder.
public struct SearchOptions: Sendable, Equatable {
    public var matchCase = false
    public var wholeWord = false
    public var regularExpression = false
    /// File name patterns separated by `;` or `,`, like Visual Studio's "File types" box ("*.vb; *.cs"). Empty means all files.
    public var fileTypes = ""

    public init(matchCase: Bool = false, wholeWord: Bool = false, regularExpression: Bool = false, fileTypes: String = "") {
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.regularExpression = regularExpression
        self.fileTypes = fileTypes
    }
}

public struct SearchMatch: Sendable, Equatable {
    public let url: URL
    public let line: Int          // 1-based
    public let column: Int        // 1-based, UTF-16
    public let length: Int        // UTF-16
    /// The whole line, without its line break.
    public let preview: String
}

public enum FileSearch {
    /// Folders that hold build output, dependencies or tool data rather than the project's own code.
    public static let skippedFolders: Set<String> = [".git", ".svn", ".hg", "node_modules", "bin", "obj", ".build", "build", "dist",
                                                      "DerivedData", ".vs", ".idea", "__pycache__", ".venv", "venv", "target", "Pods"]

    /// The regular expression for a query, or nil when the query is empty or the pattern is invalid.
    public static func expression(for query: String, options: SearchOptions) -> NSRegularExpression? {
        guard !query.isEmpty else { return nil }
        var pattern = options.regularExpression ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = #"(?<![\p{L}\p{N}_])(?:"# + pattern + #")(?![\p{L}\p{N}_])"# }
        return try? NSRegularExpression(pattern: pattern, options: options.matchCase ? [] : [.caseInsensitive])
    }

    /// The files a search looks at, in a stable order.
    public static func files(in root: URL, fileTypes: String = "") -> [URL] {
        let patterns = fileTypes.split(whereSeparator: { $0 == ";" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if skippedFolders.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard (values?.fileSize ?? 0) < 5_000_000 else { continue }
            if !patterns.isEmpty, !patterns.contains(where: { matches(url.lastPathComponent.lowercased(), pattern: $0) }) { continue }
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }

    /// `*.vb`, `Program.*`, `*.cs*` style wildcards.
    static func matches(_ name: String, pattern: String) -> Bool {
        let regex = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
        return name.range(of: regex, options: .regularExpression) != nil
    }

    /// Reads a file as text; nil for binary files.
    public static func text(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.prefix(8000).contains(0) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Every match in one text.
    public static func matches(in text: String, url: URL, expression: NSRegularExpression) -> [SearchMatch] {
        let ns = text as NSString
        var result: [SearchMatch] = []
        var lineNumber = 1
        var lineStart = 0
        var scanned = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) where match.range.length > 0 {
            // Count the lines between the previous match and this one.
            while scanned < match.range.location {
                if ns.character(at: scanned) == 0x0A {
                    lineNumber += 1
                    lineStart = scanned + 1
                }
                scanned += 1
            }
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            var preview = ns.substring(with: lineRange)
            while preview.hasSuffix("\n") || preview.hasSuffix("\r") { preview.removeLast() }
            result.append(SearchMatch(url: url, line: lineNumber, column: match.range.location - lineStart + 1,
                                      length: match.range.length, preview: preview))
        }
        return result
    }

    /// Searches a folder. `limit` stops runaway searches (like a single letter in a big project).
    public static func search(_ query: String, in root: URL, options: SearchOptions, limit: Int = 5000) -> [SearchMatch] {
        guard let expression = expression(for: query, options: options) else { return [] }
        var result: [SearchMatch] = []
        for url in files(in: root, fileTypes: options.fileTypes) {
            guard let text = text(of: url) else { continue }
            result += matches(in: text, url: url, expression: expression)
            if result.count >= limit { return Array(result.prefix(limit)) }
        }
        return result
    }

    /// Replaces every match in a text. With a regular expression, `$1` in the replacement is the first group.
    public static func replace(in text: String, expression: NSRegularExpression, with replacement: String, regularExpression: Bool) -> (text: String, count: Int) {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let count = expression.numberOfMatches(in: text, range: range)
        let template = regularExpression ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
        return (expression.stringByReplacingMatches(in: text, range: range, withTemplate: template), count)
    }
}
