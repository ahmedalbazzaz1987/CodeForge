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
/// Rust (`error: …` then `--> file:line:col`), Python tracebacks and Node.js stack traces.
public enum DiagnosticParser {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let compiler = regex(#"^((?=[^:\n]*[./])[^\s:][^:\n]*?):(\d+):(?:(\d+):)?\s*(?:(fatal error|error|warning|note)\s*(?:\[[^\]]*\])?:)?\s*(.+)$"#)
    private static let typescript = regex(#"^([^\s(][^(\n]*\.\w+)\((\d+),(\d+)\):\s*(error|warning)\s*(?:TS\d+)?:?\s*(.+)$"#)
    private static let rustHeader = regex(#"^(error|warning)(?:\[\w+\])?: (.+)$"#)
    private static let rustLocation = regex(#"^\s*--> ([^:\n]+):(\d+):(\d+)"#)
    private static let pythonFrame = regex(#"^\s*File "([^"]+)", line (\d+)"#)
    private static let nodeLocation = regex(#"^(/[^:\n]+\.[cm]?[jt]sx?):(\d+)$"#)
    private static let exceptionLine = regex(#"^([A-Za-z_][\w.]*(?:Error|Exception|Warning|Interrupt|Exit)(?::.*)?)$"#)

    public static func parse(_ output: String) -> [Diagnostic] {
        var results: [Diagnostic] = []
        var seen = Set<Diagnostic>()
        func add(_ diagnostic: Diagnostic) {
            if seen.insert(diagnostic).inserted { results.append(diagnostic) }
        }

        var pendingRust: (Diagnostic.Severity, String)?
        var pendingFrame: (file: String, line: Int)?   // last Python/Node location, waiting for its exception line

        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let ns = line as NSString
            let all = NSRange(location: 0, length: ns.length)
            func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
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
