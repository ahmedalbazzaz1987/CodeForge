import Foundation

/// Splits a Language Server Protocol byte stream (`Content-Length: N\r\n\r\n{json}`) into messages.
public struct LSPMessageBuffer {
    private var buffer = Data()
    private static let separator = Data("\r\n\r\n".utf8)

    public init() {}

    /// Adds bytes and returns every complete JSON message body now available.
    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var messages: [Data] = []
        while let headerEnd = buffer.range(of: Self.separator) {
            let header = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
            let length = header.split(separator: "\r\n").compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }.first
            guard let length else {
                buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)   // malformed header: skip it
                continue
            }
            let bodyStart = headerEnd.upperBound
            guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { break }
            let bodyEnd = buffer.index(bodyStart, offsetBy: length)
            messages.append(Data(buffer[bodyStart..<bodyEnd]))
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        }
        return messages
    }

    public static func frame(_ body: Data) -> Data {
        Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
    }
}

/// Converts between UTF-16 offsets (NSString) and LSP positions (0-based line, UTF-16 character).
public struct TextLines {
    public let lineStarts: [Int]
    public let length: Int

    public init(_ text: String) {
        var starts = [0]
        var index = 0
        for unit in text.utf16 {
            index += 1
            if unit == 10 { starts.append(index) }
        }
        lineStarts = starts
        length = index
    }

    public func position(of offset: Int) -> (line: Int, character: Int) {
        let clamped = min(max(offset, 0), length)
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= clamped { low = mid } else { high = mid - 1 }
        }
        return (low, clamped - lineStarts[low])
    }

    public func offset(line: Int, character: Int) -> Int {
        guard line < lineStarts.count else { return length }
        let start = lineStarts[max(line, 0)]
        let end = line + 1 < lineStarts.count ? lineStarts[line + 1] - 1 : length
        return min(start + max(character, 0), end)
    }
}

/// A language server CodeForge knows how to start.
public struct LanguageServerSpec: Sendable {
    public let id: String
    public let name: String
    /// CodeForge language ids this server handles.
    public let languages: [String]
    /// Executable names to look for, in order.
    public let executables: [String]
    public let arguments: [String]
    /// Look the executable up with `xcrun --find` (Xcode's toolchain).
    public let viaXcrun: Bool
    /// Only use the copy CodeForge installed (another copy on the Mac may be too old).
    public let installedCopyOnly: Bool
    /// npm packages CodeForge can install for this server (empty when it has to be installed another way).
    public let npmPackages: [String]
    /// A .NET tool CodeForge can install for this server (`dotnet tool install`).
    public let dotnetTool: String?
    public let installHint: String

    public init(id: String, name: String, languages: [String], executables: [String], arguments: [String] = [],
                viaXcrun: Bool = false, installedCopyOnly: Bool = false, npmPackages: [String] = [], dotnetTool: String? = nil,
                installHint: String) {
        self.id = id
        self.name = name
        self.languages = languages
        self.executables = executables
        self.arguments = arguments
        self.viaXcrun = viaXcrun
        self.installedCopyOnly = installedCopyOnly
        self.npmPackages = npmPackages
        self.dotnetTool = dotnetTool
        self.installHint = installHint
    }
}

public enum LanguageServerSpecs {
    public static let all: [LanguageServerSpec] = [
        LanguageServerSpec(id: "sourcekit-lsp", name: "SourceKit-LSP", languages: ["swift"], executables: ["sourcekit-lsp"],
                           viaXcrun: true, installHint: "Install Xcode from the App Store."),
        LanguageServerSpec(id: "clangd", name: "clangd", languages: ["c", "cpp", "objc"], executables: ["clangd"],
                           arguments: ["--background-index=false"], viaXcrun: true, installHint: "Install Xcode from the App Store."),
        LanguageServerSpec(id: "pyright", name: "Pyright", languages: ["python"], executables: ["pyright-langserver"],
                           arguments: ["--stdio"], npmPackages: ["pyright"],
                           installHint: "CodeForge can install it for you (needs Node.js: brew install node)."),
        // TypeScript 7 has a built-in language server for JavaScript and TypeScript.
        LanguageServerSpec(id: "typescript", name: "TypeScript", languages: ["javascript", "typescript"], executables: ["tsc"],
                           arguments: ["--lsp", "--stdio"], installedCopyOnly: true, npmPackages: ["typescript@7"],
                           installHint: "CodeForge can install it for you (needs Node.js: brew install node)."),
        LanguageServerSpec(id: "csharp-ls", name: "csharp-ls", languages: ["csharp"], executables: ["csharp-ls"], dotnetTool: "csharp-ls",
                           installHint: "CodeForge can install it for you (needs the .NET SDK: brew install dotnet)."),
        LanguageServerSpec(id: "gopls", name: "gopls", languages: ["go"], executables: ["gopls"],
                           installHint: "Install it with: go install golang.org/x/tools/gopls@latest"),
        LanguageServerSpec(id: "rust-analyzer", name: "rust-analyzer", languages: ["rust"], executables: ["rust-analyzer"],
                           installHint: "Install it with: rustup component add rust-analyzer"),
    ]

    public static func spec(forLanguage id: String) -> LanguageServerSpec? {
        all.first { $0.languages.contains(id) }
    }

    /// The LSP `languageId` for a file.
    public static func languageId(forLanguage id: String, fileExtension: String) -> String {
        switch (id, fileExtension.lowercased()) {
        case ("typescript", "tsx"): "typescriptreact"
        case ("javascript", "jsx"): "javascriptreact"
        case ("objc", "mm"): "objective-cpp"
        case ("objc", _): "objective-c"
        default: id
        }
    }
}

/// Turns hover Markdown into plain text: code fences and emphasis markers are removed.
public enum HoverText {
    public static func plain(_ markdown: String) -> String {
        var lines: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("```") { continue }
            lines.append(line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: ""))
        }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return text
    }
}
