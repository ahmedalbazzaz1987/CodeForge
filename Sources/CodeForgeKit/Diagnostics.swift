import Foundation

/// An error or warning found in a tool's output, for the Error List.
public struct Diagnostic: Equatable, Hashable, Sendable {
    public enum Severity: String, Sendable { case error, warning }

    public let severity: Severity
    public let message: String
    /// The path as the tool printed it (absolute, or relative to the folder it ran in).
    public let file: String
    public let line: Int
    public let column: Int?
    /// Where the problem ends, when the tool reports it (1-based, end exclusive).
    public let endLine: Int?
    public let endColumn: Int?

    public init(severity: Severity, message: String, file: String, line: Int, column: Int? = nil, endLine: Int? = nil, endColumn: Int? = nil) {
        self.severity = severity
        self.message = message
        self.file = file
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }

    public func url(relativeTo folder: URL) -> URL {
        file.hasPrefix("/") ? URL(fileURLWithPath: file) : folder.appendingPathComponent(file).standardizedFileURL
    }
}

/// Reads compiler and runtime error formats from plain output:
/// clang/gcc/swiftc/go/javac/ruby (`file:line:col: error: message`), TypeScript (`file(line,col): error …`),
/// Rust (`error: …` then `--> file:line:col`), Python tracebacks, Node.js stack traces, and .NET unhandled exceptions and
/// failed tests (at the first stack frame that has a file and line: your code, not the framework's).
public enum DiagnosticParser {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let compiler = regex(#"^((?!\[)(?=[^:\n]*[./])[^\s:][^:\n]*?):(\d+):(?:(\d+):)?\s*(?:(fatal error|error|warning|note)\s*(?:\[[^\]]*\])?:)?\s*(.+)$"#)
    /// TypeScript and MSBuild (.NET): `file(line,col): error CODE: message [project]`
    private static let typescript = regex(#"^\s*([^\s(][^(\n]*\.\w+)\((\d+),(\d+)\):\s*(error|warning)\s*(?:[A-Z]+\d+)?:?\s*(.+?)(?:\s+\[[^\]\n]+\])?$"#)
    private static let rustHeader = regex(#"^(error|warning)(?:\[\w+\])?: (.+)$"#)
    private static let rustLocation = regex(#"^\s*--> ([^:\n]+):(\d+):(\d+)"#)
    private static let pythonFrame = regex(#"^\s*File "([^"]+)", line (\d+)"#)
    private static let nodeLocation = regex(#"^(/[^:\n]+\.[cm]?[jt]sx?):(\d+)$"#)
    private static let exceptionLine = regex(#"^([A-Za-z_][\w.]*(?:Error|Exception|Warning|Interrupt|Exit)(?::.*)?)$"#)
    private static let dotnetUnhandled = regex(#"^Unhandled exception\. (.+)$"#)
    private static let dotnetFailedTest = regex(#"^\s*Failed (\S+) \["#)
    private static let dotnetFrame = regex(#"^\s+at .+ in (.+):line (\d+)\s*$"#)

    public static func parse(_ output: String) -> [Diagnostic] {
        var results: [Diagnostic] = []
        var seen = Set<Diagnostic>()
        func add(_ diagnostic: Diagnostic) {
            if seen.insert(diagnostic).inserted { results.append(diagnostic) }
        }

        var pendingRust: (Diagnostic.Severity, String)?
        var pendingFrame: (file: String, line: Int)?   // last Python/Node location, waiting for its exception line
        var pendingDotNet: String?                     // a .NET exception or failed test, waiting for its first frame with a file
        var testMessageNext = false

        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let ns = line as NSString
            let all = NSRange(location: 0, length: ns.length)
            func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }

            if let match = dotnetUnhandled.firstMatch(in: line, range: all) {
                pendingDotNet = group(match, 1)
                continue
            }
            if let match = dotnetFailedTest.firstMatch(in: line, range: all) {
                pendingDotNet = "Test failed: " + group(match, 1)!
                continue
            }
            if pendingDotNet != nil, line.trimmingCharacters(in: .whitespaces) == "Error Message:" {
                testMessageNext = true
                continue
            }
            if testMessageNext, let failed = pendingDotNet, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                pendingDotNet = failed + " — " + line.trimmingCharacters(in: .whitespaces)
                testMessageNext = false
                continue
            }
            if let message = pendingDotNet, let match = dotnetFrame.firstMatch(in: line, range: all) {
                add(Diagnostic(severity: .error, message: message, file: group(match, 1)!, line: Int(group(match, 2)!)!))
                pendingDotNet = nil
                continue
            }
            if let match = rustHeader.firstMatch(in: line, range: all) {
                pendingRust = (group(match, 1) == "warning" ? .warning : .error, group(match, 2) ?? "")
                continue
            }
            if let match = rustLocation.firstMatch(in: line, range: all), let (severity, message) = pendingRust {
                add(Diagnostic(severity: severity, message: message, file: group(match, 1)!,
                               line: Int(group(match, 2)!)!, column: Int(group(match, 3)!)))
                pendingRust = nil
                continue
            }
            if let match = pythonFrame.firstMatch(in: line, range: all) {
                pendingFrame = (group(match, 1)!, Int(group(match, 2)!)!)
                continue
            }
            if let match = nodeLocation.firstMatch(in: line, range: all) {
                pendingFrame = (group(match, 1)!, Int(group(match, 2)!)!)
                continue
            }
            if let frame = pendingFrame, let match = exceptionLine.firstMatch(in: line, range: all) {
                add(Diagnostic(severity: .error, message: group(match, 1)!, file: frame.file, line: frame.line))
                pendingFrame = nil
                continue
            }
            if let match = typescript.firstMatch(in: line, range: all) {
                add(Diagnostic(severity: group(match, 4) == "warning" ? .warning : .error, message: group(match, 5)!,
                               file: group(match, 1)!, line: Int(group(match, 2)!)!, column: Int(group(match, 3)!)))
                continue
            }
            if let match = compiler.firstMatch(in: line, range: all) {
                let kind = group(match, 4)
                if kind == "note" { continue }
                add(Diagnostic(severity: kind == "warning" ? .warning : .error, message: group(match, 5)!,
                               file: group(match, 1)!, line: Int(group(match, 2)!)!, column: group(match, 3).flatMap { Int($0) }))
            }
        }
        return results
    }
}

/// The same problem can come from the build and from the language server, in slightly different words.
public enum DiagnosticMerge {
    /// The build's problems plus the language server's, without listing one problem twice. The two can disagree by a
    /// line: for a missing ';' the compiler names the line that lacks it, and clangd the line after. The build's wins.
    public static func merged(run: [Diagnostic], live: [Diagnostic], folder: URL) -> [Diagnostic] {
        func same(_ a: Diagnostic, _ b: Diagnostic, within lines: Int) -> Bool {
            guard abs(a.line - b.line) <= lines, path(of: a, in: folder) == path(of: b, in: folder) else { return false }
            let first = normalized(a.message), second = normalized(b.message)
            return first == second || first.contains(second) || second.contains(first)
        }
        var result: [Diagnostic] = []
        for diagnostic in run where !result.contains(where: { same($0, diagnostic, within: 0) }) { result.append(diagnostic) }
        let fromRun = result
        for diagnostic in live where !fromRun.contains(where: { same($0, diagnostic, within: 1) }) && !result.contains(where: { same($0, diagnostic, within: 0) }) {
            result.append(diagnostic)
        }
        return result
    }

    /// A problem's file, with symlinks resolved (the same place can be /tmp or /private/tmp).
    public static func path(of diagnostic: Diagnostic, in folder: URL) -> String {
        diagnostic.url(relativeTo: folder).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// "Expected ';' after expression (fix available)" and "expected ';' after expression [-Wfoo]" say the same thing.
    static func normalized(_ message: String) -> String {
        message.lowercased()
            .replacingOccurrences(of: #"\s*\((?:fix available|fixes available)\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[[^\]]*\]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
