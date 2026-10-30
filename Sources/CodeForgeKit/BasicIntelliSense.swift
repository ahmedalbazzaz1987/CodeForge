import Foundation

/// IntelliSense without a language server: VB.NET (member lists from the project and the .NET catalog, hover, Go to
/// Definition), and keyword, symbol, snippet and word completion for every other language that has no server.
public enum BasicIntelliSense {
    public struct Item: Sendable, Equatable {
        public let label: String
        public let detail: String
        public let kind: Int          // LSP CompletionItemKind
        public let text: String
        /// Set for snippets: expand this body instead of inserting `text`.
        public let snippetBody: String?

        public init(label: String, detail: String, kind: Int, text: String? = nil, snippetBody: String? = nil) {
            self.label = label
            self.detail = detail
            self.kind = kind
            self.text = text ?? label
            self.snippetBody = snippetBody
        }
    }

    /// What the name in front of a `.` turned out to be.
    enum Target {
        case instance(String)                 // a value of this type
        case type(String)                     // the type itself (Shared members)
        case namespace(String)
    }

    // MARK: Completion

    public static func completions(text: String, offset: Int, languageId: String, symbols: [CodeSymbol], snippets: [CodeSnippet]) -> (items: [Item], wordStart: Int) {
        let ns = text as NSString
        let offset = min(offset, ns.length)
        var start = offset
        while start > 0, isIdentifier(ns.character(at: start - 1)) { start -= 1 }
        let lineStart = ns.lineRange(for: NSRange(location: start, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: start - lineStart))
        let dotNet = ["vb", "csharp"].contains(languageId)

        // In a comment or string: nothing.
        if let language = Languages.language(id: languageId), offset > lineStart {
            let prefix = ns.substring(with: NSRange(location: lineStart, length: offset - lineStart))
            let masked = ExtractMethod.mask(prefix, language: language)
            if masked.last == " ", prefix.last != " " { return ([], start) }
        }

        if before.hasSuffix(".") {
            let expression = memberExpression(before: String(before.dropLast()))
            return (members(of: expression, text: text, offset: start, languageId: languageId, symbols: symbols), start)
        }
        if dotNet, before.range(of: #"^\s*(?:Imports|using)\s+[\w.]*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return (DotNetCatalog.namespaces.map { Item(label: $0, detail: "Namespace", kind: 9) }, start)
        }
        let wantsType = languageId == "vb" && before.range(of: #"\b(?:As|Of|Inherits|Implements)\s+(?:New\s+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil

        var items: [Item] = []
        var seen = Set<String>()
        func add(_ item: Item) {
            let key = languageId == "vb" ? item.label.lowercased() : item.label
            if seen.insert(key).inserted { items.append(item) }
        }
        let sameLanguage = symbols.filter { symbol in symbol.url.map { Languages.forFile(named: $0.lastPathComponent).id == languageId } ?? true }
        if wantsType {
            for keyword in ["Boolean", "Byte", "Char", "Date", "Decimal", "Double", "Integer", "Long", "Object", "Short", "Single", "String"] {
                add(Item(label: keyword, detail: "Type", kind: 7))
            }
        } else {
            // Locals and parameters of the method around the cursor.
            for local in locals(in: text, before: start, languageId: languageId) { add(Item(label: local.name, detail: local.type ?? "Local variable", kind: 6)) }
            for snippet in snippets { add(Item(label: snippet.shortcut, detail: snippet.title, kind: 15, snippetBody: snippet.body)) }
            let keywords = languageId == "vb" ? DotNetCatalog.vbKeywords : (Languages.language(id: languageId).map { Array($0.keywords) } ?? [])
            for keyword in keywords.sorted() { add(Item(label: keyword, detail: "Keyword", kind: 14)) }
            // Members of the current type, and module members (they're visible everywhere in VB).
            let container = enclosingType(at: start, text: text, symbols: sameLanguage)
            for symbol in sameLanguage where !symbol.kind.isType && symbol.kind != .namespace {
                if symbol.container == container || (languageId == "vb" && sameLanguage.contains { $0.kind == .module && $0.name == symbol.container }) || symbol.container == nil {
                    add(Item(label: symbol.name, detail: symbol.signature, kind: symbol.kind.completionKind))
                }
            }
        }
        for symbol in sameLanguage where symbol.kind.isType { add(Item(label: symbol.name, detail: "\(symbol.kind.title) \(symbol.qualifiedName)", kind: symbol.kind.completionKind)) }
        if dotNet {
            for type in DotNetCatalog.types { add(Item(label: type.name, detail: "\(type.kind.title) \(type.qualifiedName)", kind: type.kind.completionKind)) }
        }
        if !wantsType {
            // Other words in the file, like Visual Studio's word completion for plain text.
            let regex = try! NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]{2,}\b"#)
            for match in regex.matches(in: text, range: NSRange(location: 0, length: min(ns.length, 400_000))) where match.range.location != start {
                add(Item(label: ns.substring(with: match.range), detail: "", kind: 1))
            }
        }
        return (items, start)
    }

    /// The members after `expression.` — `Console`, `name`, `Me`, `list.First()`, `System.IO`.
    static func members(of expression: [String], text: String, offset: Int, languageId: String, symbols: [CodeSymbol]) -> [Item] {
        guard let target = resolve(expression, text: text, offset: offset, languageId: languageId, symbols: symbols) else { return [] }
        var items: [Item] = []
        switch target {
        case .namespace(let name):
            let prefix = name + "."
            for child in DotNetCatalog.namespaces where child.hasPrefix(prefix) && !child.dropFirst(prefix.count).contains(".") {
                items.append(Item(label: String(child.dropFirst(prefix.count)), detail: "Namespace", kind: 9))
            }
            for type in DotNetCatalog.types where type.namespace == name {
                items.append(Item(label: type.name, detail: "\(type.kind.title) \(type.qualifiedName)", kind: type.kind.completionKind))
            }
            for symbol in symbols where symbol.kind.isType && symbol.namespace == name {
                items.append(Item(label: symbol.name, detail: "\(symbol.kind.title) \(symbol.qualifiedName)", kind: symbol.kind.completionKind))
            }
        case .type(let name), .instance(let name):
            let wantsShared: Bool
            if case .type = target { wantsShared = true } else { wantsShared = false }
            let projectMembers = symbols.filter { $0.container?.lowercased() == DotNetCatalog.baseName(name).lowercased() && !$0.kind.isType }
            if !projectMembers.isEmpty || symbols.contains(where: { $0.kind.isType && $0.name.lowercased() == DotNetCatalog.baseName(name).lowercased() }) {
                let isModule = symbols.contains { $0.kind == .module && $0.name.lowercased() == DotNetCatalog.baseName(name).lowercased() }
                // Private members are visible only inside their own type.
                let inside = enclosingType(at: offset, text: text, symbols: symbols)?.lowercased() == DotNetCatalog.baseName(name).lowercased()
                for member in projectMembers where member.kind != .constructor && (isModule || member.isShared == wantsShared)
                    && (inside || !member.signature.lowercased().hasPrefix("private")) {
                    items.append(Item(label: member.name, detail: member.signature, kind: member.kind.completionKind))
                }
                // A class's instance also has Object's members.
                if !wantsShared, let object = DotNetCatalog.type(named: "Object") {
                    items += object.members.map { Item(label: $0.name, detail: $0.signature, kind: $0.isMethod ? 2 : 10) }
                }
            } else if let type = DotNetCatalog.type(named: name) {
                var seen = Set<String>()
                for member in type.members where member.isShared == wantsShared && seen.insert(member.name).inserted {
                    items.append(Item(label: member.name, detail: member.signature, kind: member.isMethod ? 2 : 10))
                }
            }
        }
        return items.sorted { $0.label.lowercased() < $1.label.lowercased() }
    }

    /// Works out the type of `a.b.c` step by step.
    static func resolve(_ expression: [String], text: String, offset: Int, languageId: String, symbols: [CodeSymbol]) -> Target? {
        guard let first = expression.first else { return nil }
        let ci = languageId == "vb"
        func same(_ a: String, _ b: String) -> Bool { ci ? a.lowercased() == b.lowercased() : a == b }
        var target: Target?
        if ["me", "this", "self", "mybase"].contains(first.lowercased()) {
            target = enclosingType(at: offset, text: text, symbols: symbols).map { .instance($0) }
        } else if let local = locals(in: text, before: offset, languageId: languageId).last(where: { same($0.name, first) }), let type = local.type {
            target = .instance(type)
        } else if let field = symbols.first(where: { !$0.kind.isType && same($0.name, first) && $0.type != nil && $0.container == enclosingType(at: offset, text: text, symbols: symbols) }) {
            target = .instance(field.type!)
        } else if let type = symbols.first(where: { $0.kind.isType && same($0.name, first) }) {
            target = .type(type.name)
        } else if let type = DotNetCatalog.types.first(where: { same($0.name, first) }) ?? DotNetCatalog.type(named: first).flatMap({ DotNetCatalog.aliases[first.lowercased()] != nil ? $0 : nil }) {
            target = .type(type.name)
        } else if DotNetCatalog.namespaces.contains(where: { same($0, first) }) {
            target = .namespace(DotNetCatalog.namespaces.first { same($0, first) }!)
        } else {
            return nil
        }
        for part in expression.dropFirst() {
            switch target {
            case .namespace(let name):
                let qualified = name + "." + part
                if let match = DotNetCatalog.namespaces.first(where: { same($0, qualified) }) {
                    target = .namespace(match)
                } else if let type = DotNetCatalog.types.first(where: { $0.namespace == name && same($0.name, part) }) {
                    target = .type(type.name)
                } else {
                    return nil
                }
            case .type(let name), .instance(let name):
                if let member = symbols.first(where: { same($0.container ?? "", DotNetCatalog.baseName(name)) && same($0.name, part) }) {
                    if member.kind == .enumMember { target = .instance(name) } else if let type = member.type { target = .instance(type) } else { return nil }
                } else if let type = DotNetCatalog.type(named: name), let member = type.members.first(where: { same($0.name, part) }), let returns = member.returnType {
                    // A generic List(Of T) item is unknown; stop rather than guess.
                    if ["T", "TKey", "TValue", "TResult"].contains(returns) { return nil }
                    target = .instance(returns)
                } else {
                    return nil
                }
            case nil:
                return nil
            }
        }
        return target
    }

    /// The identifiers of `a.b(1).c` before a dot, without call arguments.
    static func memberExpression(before text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in text.reversed() {
            if depth > 0 {
                if character == ")" { depth += 1 }
                if character == "(" { depth -= 1 }
                continue
            }
            if character == ")" { depth = 1; continue }
            if character.isLetter || character.isNumber || character == "_" {
                current.insert(character, at: current.startIndex)
            } else if character == ".", !current.isEmpty {
                parts.insert(current, at: 0)
                current = ""
            } else {
                break
            }
        }
        if !current.isEmpty { parts.insert(current, at: 0) }
        return parts
    }

    // MARK: Variables

    public struct Local: Sendable, Equatable {
        public let name: String
        public let type: String?
        public let line: Int   // 1-based
    }

    /// Variables and parameters declared before an offset, in the method around it (or the file for scripts).
    public static func locals(in text: String, before offset: Int, languageId: String) -> [Local] {
        guard let language = Languages.language(id: languageId) else { return [] }
        let ns = text as NSString
        let head = ns.substring(to: min(offset, ns.length))
        let lines = ExtractMethod.mask(head, language: language).components(separatedBy: "\n")
        let originals = head.components(separatedBy: "\n")
        // Start at the method's header, if there is one.
        var start = 0
        if let flavor = Flavor.forLanguage(languageId) {
            for index in stride(from: lines.count - 1, through: 0, by: -1) where flavor.isHeader(lines[index]) {
                start = index
                break
            }
        }
        var result: [Local] = []
        let patterns: [String]
        switch languageId {
        case "vb":
            patterns = [#"\b(?:Dim|Static|Const|Using)\s+(\w+)(?:\(\))?(?:\s+As\s+(?:New\s+)?([\w.]+(?:\(Of[^)]*\))?(?:\(\))?))?(?:\s*=\s*(.*))?"#,
                        #"\bFor\s+(?:Each\s+)?(\w+)(?:\s+As\s+([\w.]+(?:\(Of[^)]*\))?))?"#,
                        #"(?:\(|,)\s*(?:(?:ByVal|ByRef|Optional|ParamArray)\s+)*(\w+)(?:\(\))?\s+As\s+([\w.]+(?:\(Of[^)]*\))?(?:\(\))?)"#,
                        #"\bCatch\s+(\w+)\s+As\s+([\w.]+)"#]
        case "csharp":
            patterns = [#"\b(var|[A-Z]\w*(?:<[^;=()]*?>)?(?:\[\])?|int|long|string|double|bool|decimal|char|float|object|byte)\s+([A-Za-z_]\w*)\s*(?:=\s*(.*?);|;|\bin\b)"#]
        default:
            patterns = [#"\b(?:let|const|var|Dim)\s+([A-Za-z_$][\w$]*)(?:\s*:\s*([\w.<>\[\]]+))?(?:\s*=\s*(.*))?"#,
                        #"^\s*([A-Za-z_]\w*)\s*=\s*(?!=)(.*)"#]
        }
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: languageId == "vb" ? [.caseInsensitive] : []) }
        for index in start..<lines.count {
            // Match the real line (values like "text" are needed), but not inside strings or comments.
            let line = originals[index]
            let masked = lines[index] as NSString
            let range = NSRange(location: 0, length: (line as NSString).length)
            for regex in regexes {
                for match in regex.matches(in: line, range: range) {
                    guard match.range.location < masked.length,
                          masked.character(at: match.range.location) == (line as NSString).character(at: match.range.location) else { continue }
                    func group(_ i: Int) -> String? {
                        guard i < match.numberOfRanges, match.range(at: i).location != NSNotFound else { return nil }
                        let value = (line as NSString).substring(with: match.range(at: i)).trimmingCharacters(in: .whitespaces)
                        return value.isEmpty ? nil : value
                    }
                    var name: String?
                    var type: String?
                    var value: String?
                    if languageId == "csharp" {
                        name = group(2)
                        type = group(1) == "var" ? nil : group(1)
                        value = group(3)
                    } else if regex.pattern.hasPrefix(#"^\s*("#) {
                        name = group(1)
                        value = group(2)
                    } else {
                        name = group(1)
                        type = group(2)
                        value = group(3)
                    }
                    guard let name, !["if", "for", "while", "return"].contains(name.lowercased()) else { continue }
                    // `Dim calc As New Calculator()`: the parentheses are the constructor call, not an array.
                    if let declared = type, declared.hasSuffix("()"), (line as NSString).substring(with: match.range).range(of: #"\bNew\s"#, options: [.regularExpression, .caseInsensitive]) != nil {
                        type = String(declared.dropLast(2))
                    }
                    if type == nil, let value { type = inferType(value, languageId: languageId) }
                    result.append(Local(name: name, type: type, line: index + 1))
                }
            }
        }
        return result
    }

    /// The type a value starts out as: `New List(Of String)`, `"text"`, `42`, `Foo(…)` for a Python class.
    static func inferType(_ value: String, languageId: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if let match = text.range(of: #"^(?:New|new)\s+([\w.]+(?:\(Of[^)]*\)|<[^>]*>)?)"#, options: .regularExpression) {
            return String(text[match]).replacingOccurrences(of: #"^(?:New|new)\s+"#, with: "", options: .regularExpression)
        }
        if text.hasPrefix("\"") || text.hasPrefix("$\"") || text.hasPrefix("'") && languageId != "vb" { return "String" }
        if text.range(of: #"^-?\d+$"#, options: .regularExpression) != nil { return "Integer" }
        if text.range(of: #"^-?\d+\.\d+$"#, options: .regularExpression) != nil { return "Double" }
        if ["true", "false"].contains(text.lowercased()) { return "Boolean" }
        if let match = text.range(of: #"^(?:DateTime\.Now|Now)\b"#, options: .regularExpression) { _ = match; return "DateTime" }
        if languageId == "python", let match = text.range(of: #"^[A-Z]\w*(?=\()"#, options: .regularExpression) { return String(text[match]) }
        return nil
    }

    /// The type whose body holds an offset, from the file's own symbols.
    static func enclosingType(at offset: Int, text: String, symbols: [CodeSymbol]) -> String? {
        let line = TextLines(text).position(of: offset).line + 1
        return symbols.filter { $0.kind.isType && $0.line <= line }.max { $0.line < $1.line }?.name
    }

    // MARK: Hover and Go to Definition

    /// The word at an offset and what's in front of it (`Console.` for `Console.WriteLine`).
    public static func word(at offset: Int, in text: String) -> (word: String, range: NSRange, qualifier: [String])? {
        let ns = text as NSString
        var start = min(offset, ns.length), end = min(offset, ns.length)
        while start > 0, isIdentifier(ns.character(at: start - 1)) { start -= 1 }
        while end < ns.length, isIdentifier(ns.character(at: end)) { end += 1 }
        guard end > start else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: start, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: start - lineStart))
        let qualifier = before.hasSuffix(".") ? memberExpression(before: String(before.dropLast())) : []
        return (ns.substring(with: NSRange(location: start, length: end - start)), NSRange(location: start, length: end - start), qualifier)
    }

    public static func hover(at offset: Int, text: String, languageId: String, symbols: [CodeSymbol]) -> String? {
        guard let (word, range, qualifier) = word(at: offset, in: text) else { return nil }
        let ci = languageId == "vb"
        func same(_ a: String, _ b: String) -> Bool { ci ? a.lowercased() == b.lowercased() : a == b }
        if !qualifier.isEmpty, let target = resolve(qualifier, text: text, offset: range.location, languageId: languageId, symbols: symbols) {
            switch target {
            case .type(let name), .instance(let name):
                if let member = symbols.first(where: { same($0.container ?? "", DotNetCatalog.baseName(name)) && same($0.name, word) }) {
                    return member.signature + "\n\n" + member.kind.title + " in " + (member.container ?? "")
                }
                if let type = DotNetCatalog.type(named: name), let member = type.members.first(where: { same($0.name, word) }) {
                    return (member.isShared ? "Shared " : "") + member.signature + "\n\n" + type.qualifiedName
                }
            case .namespace(let name):
                if let type = DotNetCatalog.types.first(where: { $0.namespace == name && same($0.name, word) }) { return "\(type.kind.title) \(type.qualifiedName)" }
                return "Namespace \(name).\(word)"
            }
            return nil
        }
        if let local = locals(in: text, before: range.location + range.length, languageId: languageId).last(where: { same($0.name, word) }) {
            return (languageId == "vb" ? "Dim \(local.name)" : local.name) + (local.type.map { languageId == "vb" ? " As \($0)" : ": \($0)" } ?? "") + "\n\nLocal variable"
        }
        if let symbol = symbols.first(where: { same($0.name, word) }) {
            return symbol.signature + "\n\n" + symbol.kind.title + (symbol.container.map { " in \($0)" } ?? "") + (symbol.url.map { " — \($0.lastPathComponent), line \(symbol.line)" } ?? "")
        }
        if ["vb", "csharp"].contains(languageId), let type = DotNetCatalog.type(named: word), DotNetCatalog.aliases[word.lowercased()] != nil || same(type.name, word) {
            return "\(type.kind.title) \(type.qualifiedName)"
        }
        return nil
    }

    /// Where a symbol is declared: a project symbol, or a local variable in this file (url nil).
    public static func definition(at offset: Int, text: String, languageId: String, symbols: [CodeSymbol]) -> (url: URL?, line: Int)? {
        guard let (word, range, qualifier) = word(at: offset, in: text) else { return nil }
        let ci = languageId == "vb"
        func same(_ a: String, _ b: String) -> Bool { ci ? a.lowercased() == b.lowercased() : a == b }
        if !qualifier.isEmpty, let target = resolve(qualifier, text: text, offset: range.location, languageId: languageId, symbols: symbols) {
            if case .type(let name) = target, let member = symbols.first(where: { same($0.container ?? "", name) && same($0.name, word) }) { return (member.url, member.line) }
            if case .instance(let name) = target, let member = symbols.first(where: { same($0.container ?? "", DotNetCatalog.baseName(name)) && same($0.name, word) }) { return (member.url, member.line) }
            return nil
        }
        if let local = locals(in: text, before: range.location, languageId: languageId).last(where: { same($0.name, word) }) { return (nil, local.line) }
        let container = enclosingType(at: offset, text: text, symbols: symbols)
        let matches = symbols.filter { same($0.name, word) }
        if let symbol = matches.first(where: { $0.container == container }) ?? matches.first(where: { $0.kind.isType }) ?? matches.first {
            return (symbol.url, symbol.line)
        }
        return nil
    }

    private static func isIdentifier(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(character) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || character == 0x5F
    }
}
