import Foundation

/// One changed file from `git status --porcelain=v1 --branch`.
public struct GitChange: Equatable, Sendable {
    /// Index (staged) and work-tree status letters, e.g. "M", "A", "D", "R", "?".
    public let staged: Character
    public let unstaged: Character
    public let path: String
    public let originalPath: String?

    public init(staged: Character, unstaged: Character, path: String, originalPath: String?) {
        self.staged = staged
        self.unstaged = unstaged
        self.path = path
        self.originalPath = originalPath
    }

    public var isStaged: Bool { staged != " " && staged != "?" }
    public var isUntracked: Bool { staged == "?" }
    public var isConflicted: Bool { staged == "U" || unstaged == "U" || (staged == "A" && unstaged == "A") || (staged == "D" && unstaged == "D") }

    /// The letter shown in the list: the staged change if any, otherwise the work-tree one.
    public var letter: String {
        if isUntracked { return "U" }
        if isConflicted { return "!" }
        return String(staged != " " ? staged : unstaged)
    }
}

public struct GitStatus: Equatable, Sendable {
    public var branch: String
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var changes: [GitChange] = []

    public init(branch: String, upstream: String? = nil, ahead: Int = 0, behind: Int = 0, changes: [GitChange] = []) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
    }

    /// Parses `git status --porcelain=v1 --branch` output.
    public static func parse(_ output: String) -> GitStatus {
        var status = GitStatus(branch: "")
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            if line.hasPrefix("## ") {
                var header = String(line.dropFirst(3))
                if let bracket = header.range(of: " [") {
                    let counts = header[bracket.upperBound...].dropLast()
                    for part in counts.components(separatedBy: ", ") {
                        let words = part.split(separator: " ")
                        if words.count == 2, let number = Int(words[1]) {
                            if words[0] == "ahead" { status.ahead = number } else if words[0] == "behind" { status.behind = number }
                        }
                    }
                    header = String(header[..<bracket.lowerBound])
                }
                if header.hasPrefix("No commits yet on ") { header = String(header.dropFirst("No commits yet on ".count)) }
                let parts = header.components(separatedBy: "...")
                status.branch = parts[0]
                status.upstream = parts.count > 1 ? parts[1] : nil
                continue
            }
            guard line.count > 3 else { continue }
            let characters = Array(line)
            var path = String(characters[3...])
            var original: String?
            if let arrow = path.range(of: " -> ") {
                original = unquote(String(path[..<arrow.lowerBound]))
                path = String(path[arrow.upperBound...])
            }
            status.changes.append(GitChange(staged: characters[0], unstaged: characters[1], path: unquote(path), originalPath: original))
        }
        return status
    }

    /// Git quotes paths with spaces or special characters: "my file.txt".
    static func unquote(_ path: String) -> String {
        guard path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 else { return path }
        return String(path.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
}

/// Who last changed each line, from `git blame --line-porcelain`.
public struct GitBlameLine: Equatable, Sendable {
    public let commit: String
    public let author: String
    public let time: Date
    public let summary: String

    /// Lines that aren't committed yet have an all-zero commit hash.
    public var isUncommitted: Bool { commit.allSatisfy { $0 == "0" } }
}

public enum GitBlame {
    /// Returns blame information by 1-based line number.
    public static func parse(_ output: String) -> [Int: GitBlameLine] {
        var result: [Int: GitBlameLine] = [:]
        var commit = "", author = "", summary = "", time = Date(timeIntervalSince1970: 0), line = 0
        for raw in output.components(separatedBy: "\n") {
            if raw.hasPrefix("\t") {
                if line > 0 { result[line] = GitBlameLine(commit: commit, author: author, time: time, summary: summary) }
                continue
            }
            let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
            guard let key = parts.first else { continue }
            let value = parts.count > 1 ? parts[1] : ""
            if key.count == 40, key.allSatisfy(\.isHexDigit) {
                commit = key
                let numbers = value.split(separator: " ")
                line = numbers.count >= 2 ? Int(numbers[1]) ?? 0 : 0
            } else if key == "author" {
                author = value
            } else if key == "author-time", let seconds = TimeInterval(value) {
                time = Date(timeIntervalSince1970: seconds)
            } else if key == "summary" {
                summary = value
            }
        }
        return result
    }

    /// The most recent change among lines `start...end`, for CodeLens on a function.
    public static func latest(in blame: [Int: GitBlameLine], lines: ClosedRange<Int>) -> GitBlameLine? {
        lines.compactMap { blame[$0] }.max { $0.time < $1.time }
    }
}

public enum RelativeTime {
    /// "just now", "5 minutes ago", "yesterday", "3 weeks ago"…
    public static func describe(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        func plural(_ value: Int, _ unit: String) -> String { "\(value) \(unit)\(value == 1 ? "" : "s") ago" }
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return plural(seconds / 60, "minute")
        case ..<86_400: return plural(seconds / 3600, "hour")
        case ..<172_800: return "yesterday"
        case ..<1_209_600: return plural(seconds / 86_400, "day")
        case ..<2_592_000: return plural(seconds / 604_800, "week")
        case ..<31_557_600: return plural(max(seconds / 2_629_800, 1), "month")
        default: return plural(seconds / 31_557_600, "year")
        }
    }
}
