import Foundation

/// Expands run-command templates such as `clang {file} -o {out} && {out}`.
///
/// Placeholders: `{file}` the file's path, `{dir}` its folder, `{name}` its name without extension,
/// `{out}` a build-output path for it. Every value is shell-quoted.
public enum CommandTemplate {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    public static func expand(_ template: String, file: URL, outputDirectory: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        let values = [
            "{file}": file.path,
            "{dir}": file.deletingLastPathComponent().path,
            "{name}": name,
            "{out}": outputDirectory.appendingPathComponent(name).path,
        ]
        var command = template
        for (placeholder, value) in values {
            command = command.replacingOccurrences(of: placeholder, with: shellQuote(value))
        }
        return command
    }
}

/// A dotted numeric version like "1.4.2" (a leading "v" and any "-suffix" are ignored).
public struct Version: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[..<dash]) }
        let parts = text.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// Subsequence matching for Quick Open: every query character must appear in order.
public enum FuzzyMatch {
    /// A higher score is a better match; nil means no match.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        let c = Array(candidate.lowercased())
        let nameStart = (c.lastIndex(of: "/") ?? -1) + 1
        var qi = 0, score = 0, last = -2
        for (i, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            score += 1
            if i == last + 1 { score += 5 }                                  // consecutive characters
            if i >= nameStart { score += 3 }                                 // inside the file name
            if i == 0 || i == nameStart || "/_-. ".contains(c[i - 1]) { score += 4 }  // start of a word
            last = i
            qi += 1
        }
        return qi == q.count ? score * 100 - c.count : nil
    }
}
