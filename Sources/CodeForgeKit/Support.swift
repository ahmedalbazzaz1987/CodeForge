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

/// Which program a command or project template needs, so CodeForge can say it's missing before anything fails.
public enum ToolRequirement {
    /// The program a shell command starts with: "npx --yes tsx a.ts" needs npx, "{ dotnet new …" needs dotnet.
    public static func tool(ofCommand command: String) -> String? {
        for word in command.split(whereSeparator: \.isWhitespace) where word != "{" && word != "(" && !word.contains("=") {
            return String(word)
        }
        return nil
    }

    /// The program a New Project template needs to be created and run.
    public static func tool(for template: ProjectTemplate) -> String? {
        if let command = template.command ?? template.runCommand { return tool(ofCommand: command) }
        return Languages.forFile(named: (template.mainFile as NSString).lastPathComponent).runCommand.flatMap(tool(ofCommand:))
    }

    /// What to tell someone who doesn't have the program.
    public static func installHint(for tool: String) -> String {
        if let language = Languages.all.first(where: { $0.runCommand.flatMap(self.tool(ofCommand:)) == tool }), let hint = language.installHint { return hint }
        return switch tool {
        case "cargo": "Install Rust with `brew install rust`."
        case "npm", "npx": "Install Node.js with `brew install node`."
        case "dotnet": "Install the .NET SDK with `brew install dotnet`."
        case "cmake": "Install CMake with `brew install cmake`."
        default: "Install \(tool) and try again."
        }
    }

    /// A readable name for messages: "the Java runtime", "Rust"…
    public static func displayName(for tool: String) -> String {
        switch tool {
        case "java", "javac": "Java (a JDK)"
        case "go": "Go"
        case "rustc", "cargo": "Rust"
        case "node", "npm", "npx": "Node.js"
        case "dotnet": "The .NET SDK"
        case "python3": "Python"
        case "kotlinc": "Kotlin"
        case "ruby": "Ruby"
        case "php": "PHP"
        case "lua": "Lua"
        case "clang", "clang++": "The C and C++ compiler"
        default: tool
        }
    }
}
