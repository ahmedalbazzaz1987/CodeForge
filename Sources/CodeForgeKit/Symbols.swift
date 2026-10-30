import Foundation

/// A declaration found in source code: a namespace, type or member. Used by Class View, the Object Browser and
/// IntelliSense for languages without a language server (VB.NET above all).
public struct CodeSymbol: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case namespace, module, `class`, structure, interface, enumeration, method, constructor, property, field, constant, event, enumMember, function, variable

        public var isType: Bool { [.module, .class, .structure, .interface, .enumeration].contains(self) }

        /// The LSP CompletionItemKind number, so the completion list shows the right badge.
        public var completionKind: Int {
            switch self {
            case .namespace: 9
            case .module: 9
            case .class: 7
            case .structure: 22
            case .interface: 8
            case .enumeration: 13
            case .method, .function: 2
            case .constructor: 4
            case .property: 10
            case .field, .variable: 5
            case .constant: 21
            case .event: 23
            case .enumMember: 20
            }
        }

        public var title: String {
            switch self {
            case .enumeration: "Enum"
            case .enumMember: "Enum member"
            case .structure: "Structure"
            default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
            }
        }
    }

    public let name: String
    public let kind: Kind
    /// The enclosing type, if any ("Program" for `Sub Main` in `Module Program`).
    public let container: String?
    public let namespace: String?
    /// The declaration, trimmed: `Public Function Add(a As Integer, b As Integer) As Integer`.
    public let signature: String
    /// The declared type or return type, when it's written down.
    public let type: String?
    public let isShared: Bool
    public let line: Int          // 1-based
    public let url: URL?

    public init(name: String, kind: Kind, container: String?, namespace: String?, signature: String, type: String?, isShared: Bool, line: Int, url: URL?) {
        self.name = name
        self.kind = kind
        self.container = container
        self.namespace = namespace
        self.signature = signature
        self.type = type
        self.isShared = isShared
        self.line = line
        self.url = url
    }

    /// "MyApp.Calculator.Add"
    public var qualifiedName: String { [namespace, container, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ".") }
}

public enum SymbolParser {
    public static func supports(languageId: String) -> Bool {
        ["vb", "csharp", "python", "javascript", "typescript", "swift", "java", "kotlin", "go", "rust", "cpp", "c", "objc", "php", "fsharp"].contains(languageId)
    }

    public static func symbols(in text: String, languageId: String, url: URL? = nil) -> [CodeSymbol] {
        guard let language = Languages.language(id: languageId) else { return [] }
        let masked = ExtractMethod.mask(text, language: language).components(separatedBy: "\n")
        let original = text.components(separatedBy: "\n")
        switch languageId {
        case "vb": return VBParser(lines: masked, original: original, url: url).parse()
        case "python": return PythonParser(lines: masked, original: original, url: url).parse()
        default: return BraceParser(languageId: languageId, lines: masked, original: original, url: url).parse()
        }
    }

    /// The symbols of every supported file under a folder.
    public static func index(folder: URL, limit: Int = 3000) -> [CodeSymbol] {
        var result: [CodeSymbol] = []
        for (count, url) in FileSearch.files(in: folder).enumerated() where count < limit {
            let language = Languages.forFile(named: url.lastPathComponent)
            guard supports(languageId: language.id), let text = FileSearch.text(of: url), text.utf16.count < 1_000_000 else { continue }
            result += symbols(in: text, languageId: language.id, url: url)
        }
        return result
    }

    static func trimmed(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("{") { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }

    static func indent(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }
}

// MARK: VB.NET

private struct VBParser {
    let lines: [String]
    let original: [String]
    let url: URL?

    private static let modifiers = #"(?:(?:Public|Private|Protected|Friend|Shared|Overrides|Overridable|Overloads|MustOverride|MustInherit|NotInheritable|NotOverridable|Partial|ReadOnly|WriteOnly|Shadows|Async|Iterator|Static|Default|WithEvents|Widening|Narrowing)\s+)*"#
    private static let options: NSString.CompareOptions = [.regularExpression, .caseInsensitive]

    func parse() -> [CodeSymbol] {
        var result: [CodeSymbol] = []
        var namespaces: [String] = []
        var types: [(name: String, kind: CodeSymbol.Kind)] = []
        var inMember = false        // inside a Sub, Function or Property body
        for (index, line) in lines.enumerated() {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if inMember {
                if text.range(of: #"^End\s+(?:Sub|Function|Property|Operator|Get|Set|Event)\b"#, options: Self.options) != nil,
                   text.range(of: #"^End\s+(?:Get|Set)\b"#, options: Self.options) == nil {
                    inMember = false
                }
                continue
            }
            if let name = capture(text, #"^Namespace\s+([\w.]+)"#) { namespaces.append(name); continue }
            if text.range(of: #"^End\s+Namespace\b"#, options: Self.options) != nil { _ = namespaces.popLast(); continue }
            if text.range(of: #"^End\s+(?:Class|Module|Structure|Interface|Enum)\b"#, options: Self.options) != nil { _ = types.popLast(); continue }

            func add(_ name: String, _ kind: CodeSymbol.Kind, type: String? = nil, isShared: Bool = false) {
                result.append(CodeSymbol(name: name, kind: kind, container: types.last?.name, namespace: namespaces.isEmpty ? nil : namespaces.joined(separator: "."),
                                         signature: SymbolParser.trimmed(original[index]), type: type, isShared: isShared, line: index + 1, url: url))
            }
            let isShared = text.range(of: #"\bShared\b"#, options: Self.options) != nil || types.last?.kind == .module
            if let match = captures(text, "^" + Self.modifiers + #"(Class|Module|Structure|Interface|Enum)\s+(\w+)"#) {
                let kind: CodeSymbol.Kind = switch match[0].lowercased() {
                case "module": .module
                case "structure": .structure
                case "interface": .interface
                case "enum": .enumeration
                default: .class
                }
                add(match[1], kind)
                types.append((match[1], kind))
                continue
            }
            if types.last?.kind == .enumeration, let name = capture(text, #"^(\w+)\s*(?:=.*)?$"#) {
                add(name, .enumMember, type: types.last?.name, isShared: true)
                continue
            }
            let abstract = text.range(of: #"\bMustOverride\b|\bDeclare\b"#, options: Self.options) != nil || types.last?.kind == .interface
            if let match = captures(text, "^" + Self.modifiers + #"(Sub|Function|Operator)\s+(\w+)"#) {
                let returns = capture(text, #"\)\s+As\s+([\w.]+(?:\(Of[^)]*\))?)\s*(?:Implements\b.*|Handles\b.*)?$"#)
                if match[1].lowercased() == "new" {
                    add(types.last?.name ?? "New", .constructor)
                } else {
                    add(match[1], .method, type: match[0].lowercased() == "sub" ? nil : returns, isShared: isShared)
                }
                if !abstract { inMember = true }
                continue
            }
            if let name = capture(text, "^" + Self.modifiers + #"Property\s+(\w+)"#) {
                let type = capture(text, #"\bAs\s+(?:New\s+)?([\w.]+(?:\(Of[^)]*\))?)"#)
                add(name, .property, type: type, isShared: isShared)
                // Auto-implemented properties (`Property Name As String`) have no body.
                let hasBody = text.range(of: #"\b(?:ReadOnly|WriteOnly)\b"#, options: Self.options) != nil
                    || (index + 1 < lines.count && lines[index + 1].trimmingCharacters(in: .whitespaces).range(of: #"^(?:Get|Set)\b"#, options: Self.options) != nil)
                if hasBody, !abstract { inMember = true }
                continue
            }
            if let name = capture(text, "^" + Self.modifiers + #"Event\s+(\w+)"#) { add(name, .event, isShared: isShared); continue }
            if !types.isEmpty, let match = captures(text, #"^(?:(?:Public|Private|Protected|Friend|Dim|Shared|ReadOnly|Const|Shadows|WithEvents)\s+)+(\w+)(?:\(\))?\s+As\s+(?:New\s+)?([\w.]+(?:\(Of[^)]*\))?)"#) {
                let isConstant = text.range(of: #"\bConst\b"#, options: Self.options) != nil
                add(match[0], isConstant ? .constant : .field, type: match[1], isShared: isShared || isConstant)
                continue
            }
        }
        return result
    }

    private func capture(_ text: String, _ pattern: String) -> String? { captures(text, pattern)?.last }

    private func captures(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { match.range(at: $0).location == NSNotFound ? nil : (text as NSString).substring(with: match.range(at: $0)) }
    }
}

// MARK: Python

private struct PythonParser {
    let lines: [String]
    let original: [String]
    let url: URL?

    func parse() -> [CodeSymbol] {
        var result: [CodeSymbol] = []
        var stack: [(indent: Int, name: String, isClass: Bool)] = []
        for (index, line) in lines.enumerated() {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let indent = SymbolParser.indent(line)
            while let last = stack.last, last.indent >= indent { stack.removeLast() }
            let container = stack.last { $0.isClass }?.name
            let inFunction = stack.last.map { !$0.isClass } ?? false
            func add(_ name: String, _ kind: CodeSymbol.Kind, type: String? = nil, isShared: Bool = false) {
                result.append(CodeSymbol(name: name, kind: kind, container: container, namespace: nil, signature: SymbolParser.trimmed(original[index]),
                                         type: type, isShared: isShared, line: index + 1, url: url))
            }
            if let match = text.range(of: #"^class\s+(\w+)"#, options: .regularExpression) {
                let name = String(text[match].dropFirst(6)).trimmingCharacters(in: .whitespaces)
                add(name, .class)
                stack.append((indent, name, true))
            } else if let match = text.range(of: #"^(?:async\s+)?def\s+\w+"#, options: .regularExpression) {
                let name = String(text[match].split(separator: " ").last ?? "")
                let returns = text.range(of: #"->\s*([^:]+):"#, options: .regularExpression).map { String(text[$0]).dropFirst(2).dropLast().trimmingCharacters(in: .whitespaces) }
                if !inFunction {
                    let isStatic = index > 0 && ["@staticmethod", "@classmethod"].contains(lines[index - 1].trimmingCharacters(in: .whitespaces))
                    add(name, container == nil ? .function : (name == "__init__" ? .constructor : .method), type: returns, isShared: isStatic)
                }
                stack.append((indent, name, false))
            } else if !inFunction, let match = text.range(of: #"^[A-Za-z_]\w*(?=\s*(?::[^=]+)?=(?!=))"#, options: .regularExpression) {
                let name = String(text[match])
                add(name, container == nil ? (name == name.uppercased() ? .constant : .variable) : .field, isShared: container != nil)
            } else if let container, inFunction, stack.last?.name == "__init__",
                      let match = text.range(of: #"^self\.(\w+)(?=\s*(?::[^=]+)?=(?!=))"#, options: .regularExpression) {
                let name = String(text[match].dropFirst(5))
                if !result.contains(where: { $0.container == container && $0.name == name }) { add(name, .field) }
            }
        }
        return result
    }
}

// MARK: C#, Java, Kotlin, Swift, JavaScript, TypeScript, Go, Rust, C/C++, PHP

private struct BraceParser {
    let languageId: String
    let lines: [String]
    let original: [String]
    let url: URL?

    private var typePattern: String {
        switch languageId {
        case "swift": #"^(?:(?:@\w+(?:\([^)]*\))?|public|private|fileprivate|internal|open|final|indirect)\s+)*(class|struct|enum|protocol|extension|actor)\s+([\w.]+)"#
        case "go": #"^type\s+(\w+)\s+(struct|interface)\b"#
        case "rust": #"^(?:pub(?:\([^)]*\))?\s+)?(struct|enum|trait|impl|mod)\s+(?:<[^>]*>\s*)?(?:[\w:]+\s+for\s+)?(\w+)"#
        case "kotlin": #"^(?:(?:public|private|internal|protected|open|abstract|data|sealed|enum|inner|annotation)\s+)*(class|interface|object)\s+(\w+)"#
        case "javascript", "typescript": #"^(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:abstract\s+)?(class|interface|enum|namespace)\s+(\w+)"#
        case "php": #"^(?:(?:abstract|final)\s+)?(class|interface|trait|enum)\s+(\w+)"#
        case "cpp", "c", "objc": #"^(?:typedef\s+)?(class|struct|enum|union|namespace|@interface|@implementation|@protocol)\s+(\w+)(?!\s*;)"#
        default: #"^(?:(?:public|private|protected|internal|static|abstract|sealed|partial|readonly|ref|unsafe|file|final|new)\s+)*(class|struct|interface|enum|record(?:\s+struct|\s+class)?|namespace)\s+([\w.]+)"#
        }
    }

    private var methodPattern: String {
        switch languageId {
        case "swift": #"^(?:(?:@\w+(?:\([^)]*\))?|public|private|fileprivate|internal|open|static|class|override|mutating|final|nonisolated|convenience|required)\s+)*(func\s+(\w+)|init)\b"#
        case "go": #"^func\s+(?:\([^)]*\)\s*)?(\w+)"#
        case "rust": #"^(?:pub(?:\([^)]*\))?\s+)?(?:const\s+|async\s+|unsafe\s+|extern\s+"C"\s+)*fn\s+(\w+)"#
        case "kotlin": #"^(?:(?:public|private|internal|protected|open|override|abstract|suspend|inline|operator)\s+)*fun\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?(\w+)"#
        case "php": #"^(?:(?:public|private|protected|static|abstract|final)\s+)*function\s+(\w+)"#
        case "javascript", "typescript":
            #"^(?:export\s+)?(?:default\s+)?(?:async\s+)?(?:function\s*\*?\s*(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::[^=]+)?=>|\w+\s*=>)|(?:(?:public|private|protected|static|readonly|async|get|set|override)\s+)*(?!(?:if|for|while|switch|catch|return|function|new|else)\b)(\w+)\s*\([^)]*\)\s*(?::\s*[^{;]+)?\{)"#
        default:
            #"^(?:(?:public|private|protected|internal|static|async|override|virtual|sealed|abstract|partial|unsafe|extern|new|final|synchronized|native|default|inline|constexpr|explicit)\s+)*(?!(?:if|for|foreach|while|switch|catch|using|lock|return|new|else|throw|await|yield|case|delete|sizeof|typeof)\b)(?:[\w<>\[\],.?:*&~]+\s+)+?[*&]?(~?\w+)\s*\(.*$"#
        }
    }

    func parse() -> [CodeSymbol] {
        var result: [CodeSymbol] = []
        var depth = 0
        // Open blocks: namespaces and types (with the depth inside them), and member bodies to skip.
        var scopes: [(name: String, kind: CodeSymbol.Kind, depth: Int)] = []
        var pending: (name: String, kind: CodeSymbol.Kind)?
        var bodyDepth: Int?       // inside a method body: skip everything until depth drops back
        var awaitingBody = 0      // lines left to find the `{` of a header that didn't have one
        let typeRegex = try! NSRegularExpression(pattern: typePattern)
        let methodRegex = try! NSRegularExpression(pattern: methodPattern)

        for (index, line) in lines.enumerated() {
            let text = line.trimmingCharacters(in: .whitespaces)
            let opens = text.filter { $0 == "{" }.count
            let closes = text.filter { $0 == "}" }.count
            defer {
                depth += opens - closes
                if let body = bodyDepth, depth <= body { bodyDepth = nil }
                while let last = scopes.last, depth < last.depth { scopes.removeLast() }
                if let type = pending, opens > 0 {
                    scopes.append((type.name, type.kind, depth))
                    pending = nil
                }
            }
            if awaitingBody > 0, !text.isEmpty {
                awaitingBody -= 1
                if opens > 0 {
                    bodyDepth = depth
                    awaitingBody = 0
                    continue
                }
                if text.hasSuffix(";") { awaitingBody = 0; continue }
                if text.hasPrefix(")") || text.hasPrefix(":") || text.hasPrefix("where") || text.hasPrefix("throws") || text.hasSuffix(",") { continue }
                awaitingBody = 0   // not a continuation: the header had no body (a protocol or interface member)
            }
            guard bodyDepth == nil, !text.isEmpty else { continue }
            let typeScope = scopes.last { $0.kind != .namespace }
            let namespace = scopes.filter { $0.kind == .namespace }.map(\.name).joined(separator: ".")
            let atTypeLevel = depth == (scopes.last?.depth ?? 0)
            func add(_ name: String, _ kind: CodeSymbol.Kind, type: String? = nil) {
                let isShared = text.range(of: #"\bstatic\b|\bconst\b|\bclass\s+func\b"#, options: .regularExpression) != nil || kind == .enumMember
                result.append(CodeSymbol(name: name, kind: kind, container: typeScope?.name, namespace: namespace.isEmpty ? nil : namespace,
                                         signature: SymbolParser.trimmed(original[index]), type: type, isShared: isShared, line: index + 1, url: url))
            }
            let range = NSRange(location: 0, length: (text as NSString).length)
            if atTypeLevel, let match = typeRegex.firstMatch(in: text, range: range) {
                var keyword = (text as NSString).substring(with: match.range(at: 1))
                var name = (text as NSString).substring(with: match.range(at: 2))
                if languageId == "go" { swap(&keyword, &name) }
                let kind: CodeSymbol.Kind = switch keyword.lowercased() {
                case "namespace", "mod": .namespace
                case "struct", "record struct", "union": .structure
                case "interface", "protocol", "trait", "@protocol": .interface
                case "enum": .enumeration
                case "object": .module
                default: .class
                }
                if kind == .namespace, text.hasSuffix(";") {     // C# file-scoped namespace
                    scopes.append((name, .namespace, depth))
                    continue
                }
                if !["extension", "impl", "@implementation"].contains(keyword) || typeScope == nil { add(name, kind) }
                if languageId == "go" { continue }
                if opens > closes || opens == 0 { pending = (name, kind) }
                if opens > 0, opens > closes { scopes.append((name, kind, depth + opens - closes)); pending = nil }
                continue
            }
            if typeScope?.kind == .enumeration, atTypeLevel, languageId != "swift", languageId != "rust",
               let name = text.range(of: #"^\w+(?=\s*(?:=[^,]*)?,?\s*$)"#, options: .regularExpression) {
                add(String(text[name]), .enumMember, type: typeScope?.name)
                continue
            }
            if languageId == "swift", typeScope?.kind == .enumeration, let match = text.range(of: #"^(?:indirect\s+)?case\s+(\w+)"#, options: .regularExpression) {
                add(String(text[match].split(separator: " ").last ?? ""), .enumMember, type: typeScope?.name)
                continue
            }
            if atTypeLevel || typeScope == nil, let match = methodRegex.firstMatch(in: text, range: range) {
                let groups = (1..<match.numberOfRanges).filter { match.range(at: $0).location != NSNotFound }.map { (text as NSString).substring(with: match.range(at: $0)) }
                var name = groups.last ?? ""
                if languageId == "swift", groups.first == "init" { name = "init" }
                if name.hasPrefix("func ") { name = String(name.dropFirst(5)) }
                let isConstructor = name == typeScope?.name || name == "init" || name == "constructor" || name == "__construct"
                let kind: CodeSymbol.Kind = isConstructor ? .constructor : (typeScope == nil ? .function : .method)
                add(name, kind, type: returnType(text, name: name))
                if opens > closes { bodyDepth = depth } else if opens == 0, !text.hasSuffix(";"), !text.contains("=>"),
                          typeScope?.kind != .interface, !text.contains("abstract") { awaitingBody = 3 }
                continue
            }
            guard atTypeLevel, let typeScope, typeScope.kind != .enumeration else { continue }
            if let (name, type, isProperty) = member(text) {
                add(name, isProperty ? .property : (text.range(of: #"\bconst\b"#, options: .regularExpression) != nil ? .constant : .field), type: type)
                if opens > closes { bodyDepth = depth }
            }
        }
        return result
    }

    /// Fields and properties declared directly in a type.
    private func member(_ text: String) -> (String, String?, Bool)? {
        func first(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
            return (1..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : (text as NSString).substring(with: match.range(at: $0)) }
        }
        switch languageId {
        case "swift", "kotlin":
            guard let m = first(#"^(?:(?:@\w+(?:\([^)]*\))?|public|private|fileprivate|internal|open|static|class|lazy|weak|unowned|final|override|nonisolated|const|lateinit)\s+)*(?:let|var|val)\s+(\w+)(?:\s*:\s*([^={]+))?"#) else { return nil }
            return (m[0], m[1].isEmpty ? nil : m[1].trimmingCharacters(in: .whitespaces), text.contains("{"))
        case "javascript", "typescript":
            guard let m = first(#"^(?:(?:public|private|protected|static|readonly|declare|override|#)\s*)*([A-Za-z_$#][\w$]*)\s*[?!]?\s*(?::\s*([^=;]+))?\s*(?:=|;|$)"#), !["return", "if", "else"].contains(m[0]) else { return nil }
            return (m[0], m[1].isEmpty ? nil : m[1].trimmingCharacters(in: .whitespaces), false)
        case "go", "rust":
            guard let m = first(#"^(?:pub(?:\([^)]*\))?\s+)?(\w+)\s*:?\s+([\w.*\[\]<>&']+)"#) else { return nil }
            return (m[0], m[1], false)
        default:
            if let m = first(#"^(?:(?:public|private|protected|internal|static|readonly|virtual|override|abstract|sealed|new|required|const|volatile|final|transient|unsafe|extern)\s+)*([\w<>\[\],.?]+(?:<[^>]*>)?)\s+(\w+)\s*(?:\{|=>)"#) {
                return (m[1], m[0], true)
            }
            if let m = first(#"^(?:(?:public|private|protected|internal|static|readonly|const|volatile|final|transient|mutable|unsafe|extern|inline|constexpr)\s+)*([\w<>\[\],.?:*&]+(?:<[^>]*>)?)\s+[*&]?(\w+)\s*(?:=[^=].*|\[[^\]]*\])?;"#),
               !["return", "using", "goto", "break", "continue", "throw", "delete"].contains(m[0]) {
                return (m[1], m[0], false)
            }
            return nil
        }
    }

    private func returnType(_ text: String, name: String) -> String? {
        switch languageId {
        case "swift", "rust":
            return text.range(of: #"->\s*([^{]+)"#, options: .regularExpression).map { String(text[$0]).dropFirst(2).trimmingCharacters(in: .whitespaces) }
        case "kotlin", "typescript":
            return text.range(of: #"\)\s*:\s*([^{=]+)"#, options: .regularExpression)
                .map { String(text[$0]).replacingOccurrences(of: #"^\)\s*:\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        case "go", "javascript", "php":
            return nil
        default:
            // `public static int Add(` → "int"
            guard let range = text.range(of: name + "(") ?? text.range(of: name + " (") else { return nil }
            let before = text[..<range.lowerBound].split(separator: " ").last.map(String.init)
            let keywords: Set<String> = ["public", "private", "protected", "internal", "static", "async", "override", "virtual", "sealed", "abstract", "new", "partial", "extern", "unsafe", "final", "void"]
            return before.flatMap { keywords.contains($0) ? nil : $0 }
        }
    }
}
