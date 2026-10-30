import Foundation

/// Extract Method for languages without a language server that offers it (VB.NET above all), and as a fallback for
/// C#, Python, JavaScript, TypeScript and Swift. It works on whole lines inside one method: variables declared before
/// the selection become parameters, and one variable set in the selection and used after it becomes the return value.
public enum ExtractMethod {
    public struct Result: Equatable, Sendable {
        public let text: String
        /// Where the new method's name is in `text`, so the editor can select it.
        public let nameRange: NSRange
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case unsupportedLanguage, emptySelection, notInMethod, containsReturn, tooManyResults([String]), unknownType(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedLanguage: "Extract Method works for VB.NET, C#, Python, JavaScript, TypeScript and Swift."
            case .emptySelection: "Select the lines to move into the new method."
            case .notInMethod: "Select lines inside one method or function."
            case .containsReturn: "The selection returns from the method, so it can't be moved into a new one."
            case .tooManyResults(let names): "The selection sets \(names.map { "“\($0)”" }.joined(separator: ", ")), which are all used afterwards. A new method can return only one of them."
            case .unknownType(let name): "Couldn't work out the type of “\(name)”. Give it an explicit type, then try again."
            }
        }
    }

    public static func defaultName(forLanguage id: String) -> String {
        switch id {
        case "python": "new_method"
        case "javascript", "typescript", "swift": "newMethod"
        default: "NewMethod"
        }
    }

    public static func supports(languageId: String) -> Bool { Flavor.forLanguage(languageId) != nil }

    public static func extract(_ text: String, selection: NSRange, languageId: String, name: String? = nil) -> Swift.Result<Result, Failure> {
        guard let flavor = Flavor.forLanguage(languageId), let language = Languages.language(id: languageId) else { return .failure(.unsupportedLanguage) }
        let name = name ?? defaultName(forLanguage: languageId)
        let lines = text.components(separatedBy: "\n")
        let masked = mask(text, language: language).components(separatedBy: "\n")
        let lineStarts = TextLines(text).lineStarts
        func lineOf(_ offset: Int) -> Int { (lineStarts.lastIndex { $0 <= offset }) ?? 0 }

        // Whole lines, without blank ones at either end.
        var first = lineOf(selection.location)
        var last = lineOf(max(selection.location, NSMaxRange(selection) - (selection.length > 0 ? 1 : 0)))
        while first <= last, lines[first].trimmingCharacters(in: .whitespaces).isEmpty { first += 1 }
        while last >= first, lines[last].trimmingCharacters(in: .whitespaces).isEmpty { last -= 1 }
        guard first <= last else { return .failure(.emptySelection) }

        let selected = masked[first...last].joined(separator: "\n")
        if selected.range(of: flavor.returnPattern, options: flavor.caseInsensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]) != nil {
            return .failure(.containsReturn)
        }

        // The enclosing method: the nearest header above the selection whose body contains it.
        let method = enclosingMethod(lines: lines, masked: masked, first: first, last: last, flavor: flavor)
        if method == nil, !flavor.allowsTopLevel(masked) { return .failure(.notInMethod) }
        let bodyStart = method.map { $0.header + 1 } ?? 0
        let bodyEnd = method?.end ?? lines.count     // exclusive

        // Variables: parameters of the method, and declarations before, inside and after the selection.
        var known: [String: String?] = [:]          // name → type (nil when it isn't written down)
        var order: [String] = []
        func remember(_ found: [(String, String?)]) {
            for (variable, type) in found where known[key(variable, flavor)] == nil {
                known[key(variable, flavor)] = .some(type)
                order.append(variable)
            }
        }
        if let method { remember(flavor.parameters(lines[method.header])) }
        for index in bodyStart..<first { remember(flavor.declarations(masked[index], original: lines[index])) }
        let declaredBefore = Set(order.map { key($0, flavor) })
        var declaredInside: [(String, String?)] = []
        for index in first...last { declaredInside += flavor.declarations(masked[index], original: lines[index]) }

        let after = masked[(last + 1)..<max(bodyEnd, last + 1)].joined(separator: "\n")
        let usedInside = identifiers(selected, flavor)
        let usedAfter = identifiers(after, flavor)
        let assignedInside = assignments(selected, flavor)

        let parameters = order.filter { usedInside.contains(key($0, flavor)) && declaredBefore.contains(key($0, flavor)) && !flavor.isReceiver($0) }
        var results: [(name: String, type: String?, declaredInside: Bool)] = []
        for (variable, type) in declaredInside where usedAfter.contains(key(variable, flavor)) && !declaredBefore.contains(key(variable, flavor)) {
            if !results.contains(where: { key($0.name, flavor) == key(variable, flavor) }) { results.append((variable, type, true)) }
        }
        for variable in parameters where assignedInside.contains(key(variable, flavor)) && usedAfter.contains(key(variable, flavor)) {
            results.append((variable, known[key(variable, flavor)] ?? nil, false))
        }
        if results.count > 1 { return .failure(.tooManyResults(results.map(\.name))) }

        // Types, where the language needs them.
        var typed: [(name: String, type: String)] = []
        for variable in parameters {
            let type = (known[key(variable, flavor)] ?? nil) ?? flavor.inferType(variable, lines: Array(lines[bodyStart..<first]))
            if flavor.needsTypes, type == nil { return .failure(.unknownType(variable)) }
            typed.append((variable, type ?? ""))
        }
        var resultType: String?
        if let result = results.first {
            resultType = result.type ?? flavor.inferType(result.name, lines: Array(lines[first...last]))
            if flavor.needsTypes, resultType == nil { return .failure(.unknownType(result.name)) }
        }

        // The new method's body, re-indented one level inside the method's own indentation.
        let methodIndent = method.map { indentation(lines[$0.header]) } ?? flavor.topLevelIndent
        let unit = lines.first { $0.hasPrefix("\t") } != nil ? "\t" : "    "
        let selectionIndent = lines[first...last].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(indentation).min { $0.count < $1.count } ?? ""
        let body = lines[first...last].map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
            return methodIndent + unit + flavor.bodyIndentExtra(unit) + String(line.dropFirst(selectionIndent.count))
        }
        let isStatic = method.map { flavor.isStatic(lines: lines, header: $0.header) } ?? false
        let receiver = method.flatMap { flavor.receiver(lines[$0.header]) }
        let declaration = flavor.declare(name: name, parameters: typed, result: results.first.map { ($0.name, resultType) },
                                         isStatic: isStatic, receiver: receiver, indent: methodIndent, unit: unit, body: body,
                                         topLevel: method == nil)

        // The call that replaces the selection.
        let callee = receiver.map { "\($0).\(name)" } ?? name
        let arguments = parameters.joined(separator: ", ")
        let call: String
        if let result = results.first {
            call = flavor.assignCall(result.name, type: resultType, declare: result.declaredInside, call: "\(callee)(\(arguments))")
        } else {
            call = flavor.statementCall("\(callee)(\(arguments))")
        }

        var output = lines
        // Insert the method first (it comes after the selection), then replace the selection.
        let insertAt = method.map { $0.end + (flavor.endIsLine ? 1 : 0) } ?? flavor.topLevelInsertion(lines: lines, masked: masked)
        let block = declaration.components(separatedBy: "\n")
        let insertion = insertAt <= first ? block + [""] : [""] + block
        let clampedInsert = min(insertAt, output.count)
        output.insert(contentsOf: insertion, at: clampedInsert)
        let shift = clampedInsert <= first ? insertion.count : 0
        output.replaceSubrange((first + shift)...(last + shift), with: [selectionIndent + call])
        let newText = output.joined(separator: "\n")

        // Find the declaration's name to select it.
        let removed = clampedInsert > first ? last - first : 0
        let declarationLine = clampedInsert - removed + (clampedInsert <= first ? 0 : 1) + (block.firstIndex { $0.contains(name + "(") } ?? 0)
        let newStarts = TextLines(newText).lineStarts
        let lineText = output[declarationLine] as NSString
        let column = lineText.range(of: name + "(").location
        let nameRange = NSRange(location: newStarts[declarationLine] + (column == NSNotFound ? 0 : column), length: (name as NSString).length)
        return .success(Result(text: newText, nameRange: nameRange))
    }

    // MARK: Helpers

    private static func key(_ name: String, _ flavor: Flavor) -> String { flavor.caseInsensitive ? name.lowercased() : name }

    private static func indentation(_ line: String) -> String { String(line.prefix { $0 == " " || $0 == "\t" }) }

    /// Blanks out strings and comments so that words in them aren't taken for code.
    public static func mask(_ text: String, language: Language) -> String {
        let ns = NSMutableString(string: text)
        for token in Tokenizer(language: language).tokens(in: text) where token.kind == .string || token.kind == .comment {
            let original = ns.substring(with: token.range)
            let blank = String(original.map { $0 == "\n" ? "\n" : " " })
            ns.replaceCharacters(in: token.range, with: blank)
        }
        return ns as String
    }

    private static func identifiers(_ text: String, _ flavor: Flavor) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: #"(?<![\w.$])[A-Za-z_$][\w$]*"#)
        let ns = text as NSString
        return Set(regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { key(ns.substring(with: $0.range), flavor) })
    }

    private static func assignments(_ text: String, _ flavor: Flavor) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: #"(?<![\w.$])([A-Za-z_$][\w$]*)\s*(?:[-+*/&|^%]|<<|>>)?=(?!=)"#)
        let ns = text as NSString
        var names = Set(regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { key(ns.substring(with: $0.range(at: 1)), flavor) })
        if let increment = try? NSRegularExpression(pattern: #"([A-Za-z_$][\w$]*)\s*(?:\+\+|--)|(?:\+\+|--)\s*([A-Za-z_$][\w$]*)"#) {
            for match in increment.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                for group in [1, 2] where match.range(at: group).location != NSNotFound { names.insert(key(ns.substring(with: match.range(at: group)), flavor)) }
            }
        }
        return names
    }

    private static func enclosingMethod(lines: [String], masked: [String], first: Int, last: Int, flavor: Flavor) -> (header: Int, end: Int)? {
        var index = first - 1
        while index >= 0 {
            if flavor.isHeader(masked[index]), let end = flavor.end(of: index, lines: masked), end > last {
                return (index, end)
            }
            index -= 1
        }
        return nil
    }
}

/// How one language writes methods, variables and calls.
struct Flavor {
    enum Blocks { case braces, vb, indentation }

    let id: String
    let caseInsensitive: Bool
    let blocks: Blocks
    let needsTypes: Bool
    let header: NSRegularExpression
    let returnPattern: String
    let declarationPatterns: [NSRegularExpression]

    static func forLanguage(_ id: String) -> Flavor? {
        let ci: NSRegularExpression.Options = [.caseInsensitive, .anchorsMatchLines]
        func re(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }
        switch id {
        case "vb":
            return Flavor(id: id, caseInsensitive: true, blocks: .vb, needsTypes: true,
                          header: re(#"^\s*(?:(?:Public|Private|Protected|Friend|Shared|Overrides|Overridable|Overloads|Async|Static|Iterator)\s+)*(?:Sub|Function)\s+\w+\s*(?:\(Of[^)]*\))?\s*\("#, ci),
                          returnPattern: #"(?m)^\s*(?:Return\b|Exit\s+(?:Sub|Function)\b|Yield\b)"#,
                          declarationPatterns: [
                            re(#"\b(?:Dim|Static)\s+(?<name>\w+)(?:\(\))?(?:\s+As\s+(?:New\s+)?(?<type>[\w.]+(?:\(Of[^)]*\))?(?:\(\))?))?"#, ci),
                            re(#"\bFor\s+(?:Each\s+)?(?<name>\w+)(?:\s+As\s+(?<type>[\w.]+(?:\(Of[^)]*\))?))?\s+(?:=|In\b)"#, ci),
                            re(#"\bUsing\s+(?<name>\w+)(?:\s+As\s+(?:New\s+)?(?<type>[\w.]+))?"#, ci),
                          ])
        case "csharp":
            return Flavor(id: id, caseInsensitive: false, blocks: .braces, needsTypes: true,
                          header: re(#"^\s*(?:(?:public|private|protected|internal|static|async|override|virtual|sealed|abstract|partial|unsafe|extern|new)\s+)*(?!(?:if|for|foreach|while|switch|catch|using|lock|return|new|else|fixed|when|await|throw|yield|case|var)\b)[\w<>\[\],.?]+(?:\s*<[^>]*>)?\s+(?!(?:if|for|foreach|while|switch|catch|using|lock)\b)\w+\s*(?:<[^>]*>)?\s*\([^;]*$"#),
                          returnPattern: #"\b(?:return|yield)\b"#,
                          declarationPatterns: [
                            re(#"(?<![\w.])(?!(?:return|new|else|case|throw|await|using|goto|in|is|as|out|ref|params|yield)\b)(?<type>var|[A-Za-z_][\w.]*(?:<[^;=()]*?>)?(?:\[\])?\??)\s+(?<name>[A-Za-z_]\w*)\s*(?:=(?!=)|;|\bin\b)"#),
                          ])
        case "python":
            return Flavor(id: id, caseInsensitive: false, blocks: .indentation, needsTypes: false,
                          header: re(#"^\s*(?:async\s+)?def\s+\w+\s*\("#),
                          returnPattern: #"\b(?:return|yield)\b"#,
                          declarationPatterns: [
                            re(#"^\s*(?<name>[A-Za-z_]\w*)\s*(?::\s*(?<type>[^=\n]+))?\s*=(?!=)"#),
                            re(#"\bfor\s+(?<name>[A-Za-z_]\w*)\s+in\b"#),
                            re(#"\bas\s+(?<name>[A-Za-z_]\w*)\s*:"#),
                          ])
        case "javascript", "typescript":
            return Flavor(id: id, caseInsensitive: false, blocks: .braces, needsTypes: false,
                          header: re(#"^\s*(?:(?:export|default|async|static|public|private|protected)\s+)*(?:function\s*\*?\s*\w+\s*\(|(?:const|let|var)\s+\w+\s*=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::[^=]+)?=>)|(?!(?:if|for|while|switch|catch|return|function)\b)\w+\s*\([^)]*\)\s*(?::\s*[^{]+)?\{)"#),
                          returnPattern: #"\b(?:return|yield)\b"#,
                          declarationPatterns: [
                            re(#"\b(?:let|const|var)\s+(?<name>[A-Za-z_$][\w$]*)(?:\s*:\s*(?<type>[^=;]+?))?\s*(?:=(?!=)|;|$|\bof\b|\bin\b)"#),
                          ])
        case "swift":
            return Flavor(id: id, caseInsensitive: false, blocks: .braces, needsTypes: true,
                          header: re(#"^\s*(?:(?:@\w+|public|private|fileprivate|internal|open|static|class|override|mutating|final|nonisolated)\s+)*func\s+\w+"#),
                          returnPattern: #"\breturn\b"#,
                          declarationPatterns: [
                            re(#"\b(?:let|var)\s+(?<name>[A-Za-z_]\w*)(?:\s*:\s*(?<type>[^={\n]+?))?\s*(?:=|$|\{)"#),
                            re(#"\bfor\s+(?<name>[A-Za-z_]\w*)\s+in\b"#),
                          ])
        default:
            return nil
        }
    }

    var endIsLine: Bool { blocks != .indentation }

    func isHeader(_ line: String) -> Bool {
        header.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// For braces and VB: the line with the method's closing `}` or `End Sub`. For Python: the first line after the body.
    func end(of headerIndex: Int, lines: [String]) -> Int? {
        switch blocks {
        case .vb:
            let headerIndent = lines[headerIndex].prefix { $0 == " " || $0 == "\t" }.count
            for index in (headerIndex + 1)..<lines.count {
                let line = lines[index]
                if line.range(of: #"^\s*End\s+(?:Sub|Function)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
                   line.prefix(while: { $0 == " " || $0 == "\t" }).count <= headerIndent { return index }
            }
            return nil
        case .braces:
            var depth = 0
            var opened = false
            for index in headerIndex..<lines.count {
                for character in lines[index] {
                    if character == "{" { depth += 1; opened = true }
                    if character == "}" { depth -= 1 }
                    if opened && depth == 0 { return index }
                }
                // An expression-bodied or abstract method has no body to extract from.
                if !opened, index > headerIndex + 3 { return nil }
            }
            return nil
        case .indentation:
            let headerIndent = lines[headerIndex].prefix { $0 == " " || $0 == "\t" }.count
            var index = headerIndex + 1
            var lastContent = headerIndex
            while index < lines.count {
                let line = lines[index]
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    if line.prefix(while: { $0 == " " || $0 == "\t" }).count <= headerIndent { break }
                    lastContent = index
                }
                index += 1
            }
            return lastContent + 1
        }
    }

    /// Top-level code (C# top-level statements, Python and JavaScript scripts, Swift main.swift).
    func allowsTopLevel(_ masked: [String]) -> Bool {
        switch id {
        case "python", "javascript", "typescript": return true
        case "csharp", "swift":
            return !masked.contains { $0.range(of: #"^\s*(?:(?:public|internal|private|static|partial|sealed|abstract|final)\s+)*(?:class|struct|record|namespace|enum|interface|actor|extension)\b"#, options: .regularExpression) != nil }
        default: return false
        }
    }

    var topLevelIndent: String { "" }

    /// Where a new top-level function goes: after the imports (Python, JavaScript), or at the end (C#, Swift).
    func topLevelInsertion(lines: [String], masked: [String]) -> Int {
        switch id {
        case "python", "javascript", "typescript":
            let imports = masked.lastIndex { $0.range(of: #"^(?:import|from)\s"#, options: .regularExpression) != nil }
            return imports.map { $0 + 1 } ?? 0
        default:
            var end = lines.count
            while end > 0, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            return end
        }
    }

    func bodyIndentExtra(_ unit: String) -> String { "" }

    func declarations(_ masked: String, original: String) -> [(String, String?)] {
        let ns = masked as NSString
        var found: [(String, String?)] = []
        for pattern in declarationPatterns {
            for match in pattern.matches(in: masked, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: match.range(withName: "name"))
                let typeRange = match.range(withName: "type")
                var type = typeRange.location == NSNotFound ? nil : ns.substring(with: typeRange).trimmingCharacters(in: .whitespaces)
                if type == "var" { type = nil }
                if id == "python" { type = nil }
                found.append((name, type))
            }
        }
        // C#: `int a = 1, b = 2;` is rare enough to skip; VB: `Dim a, b As Integer` gives both the type.
        if id == "vb", let match = masked.range(of: #"\bDim\s+(\w+\s*,[\w\s,]+?)\s+As\s+(?!New\b)([\w.]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let text = String(masked[match])
            if let names = text.range(of: #"(?<=Dim\s)[\w\s,]+?(?=\s+As\s)"#, options: [.regularExpression, .caseInsensitive]),
               let type = text.range(of: #"(?<=As\s)[\w.]+$"#, options: [.regularExpression, .caseInsensitive]) {
                for name in text[names].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
                    if let index = found.firstIndex(where: { $0.0.lowercased() == name.lowercased() }) { found[index].1 = String(text[type]) }
                    else { found.append((name, String(text[type]))) }
                }
            }
        }
        return found
    }

    func parameters(_ headerLine: String) -> [(String, String?)] {
        guard let open = headerLine.firstIndex(of: "("), let close = headerLine.lastIndex(of: ")"), open < close else { return [] }
        var list = String(headerLine[headerLine.index(after: open)..<close])
        if id == "vb", list.lowercased().hasPrefix("of ") { return [] }
        if id == "vb", let inner = headerLine.range(of: #"\)\s*\("#, options: .regularExpression) {   // Sub Foo(Of T)(x As T)
            list = String(headerLine[inner.upperBound..<close])
        }
        var depth = 0
        var parts: [String] = []
        var currentPart = ""
        for character in list {
            if "<([".contains(character) { depth += 1 }
            if ">)]".contains(character) { depth -= 1 }
            if character == ",", depth == 0 { parts.append(currentPart); currentPart = "" } else { currentPart.append(character) }
        }
        parts.append(currentPart)
        return parts.compactMap { raw -> (String, String?)? in
            var part = raw.trimmingCharacters(in: .whitespaces)
            if let equals = part.firstIndex(of: "=") { part = String(part[..<equals]).trimmingCharacters(in: .whitespaces) }
            guard !part.isEmpty else { return nil }
            switch id {
            case "vb":
                let words = part.replacingOccurrences(of: #"^(?:(?:ByVal|ByRef|Optional|ParamArray)\s+)+"#, with: "", options: [.regularExpression, .caseInsensitive])
                let pieces = words.components(separatedBy: " As ")
                let name = pieces[0].replacingOccurrences(of: "()", with: "").trimmingCharacters(in: .whitespaces)
                return (name, pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : nil)
            case "csharp":
                let cleaned = part.replacingOccurrences(of: #"^(?:(?:this|ref|out|in|params)\s+)+"#, with: "", options: .regularExpression)
                guard let space = cleaned.lastIndex(of: " ") else { return nil }
                return (String(cleaned[cleaned.index(after: space)...]), String(cleaned[..<space]).trimmingCharacters(in: .whitespaces))
            case "swift":
                let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard pieces.count == 2, let name = pieces[0].split(separator: " ").last else { return nil }
                return (String(name), pieces[1].replacingOccurrences(of: "inout ", with: ""))
            default:
                let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                let cleaned = (pieces.first ?? part).trimmingCharacters(in: CharacterSet(charactersIn: "*. {}[]?"))
                guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }) else { return nil }
                return (cleaned, id == "typescript" && pieces.count > 1 ? pieces[1] : nil)
            }
        }
    }

    /// Python's `self` and `cls` aren't passed as arguments.
    func isReceiver(_ name: String) -> Bool { id == "python" && (name == "self" || name == "cls") }

    /// `self` for Python methods, `this` for JavaScript class methods; nil for plain functions.
    func receiver(_ headerLine: String) -> String? {
        switch id {
        case "python":
            let first = parameters(headerLine).first?.0
            return first == "self" || first == "cls" ? first : nil
        case "javascript", "typescript":
            return headerLine.range(of: #"\bfunction\b|=>|^\s*(?:export\s+)?(?:const|let|var)\s"#, options: .regularExpression) == nil ? "this" : nil
        default:
            return nil
        }
    }

    func isStatic(lines: [String], header: Int) -> Bool {
        let line = lines[header]
        switch id {
        case "vb": return line.range(of: #"\bShared\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        case "csharp", "swift": return line.range(of: #"\bstatic\b"#, options: .regularExpression) != nil
        case "python": return header > 0 && lines[header - 1].trimmingCharacters(in: .whitespaces) == "@staticmethod"
        default: return false
        }
    }

    /// The type of a variable declared without one, from the value it starts with.
    func inferType(_ name: String, lines: [String]) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        for line in lines.reversed() {
            guard let range = line.range(of: #"\b"# + escaped + #"\s*=\s*(.+)$"#, options: caseInsensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]) else { continue }
            let value = String(line[range]).replacingOccurrences(of: #"^.*?=\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let names: (int: String, double: String, string: String, bool: String)
            switch id {
            case "vb": names = ("Integer", "Double", "String", "Boolean")
            case "swift": names = ("Int", "Double", "String", "Bool")
            default: names = ("int", "double", "string", "bool")
            }
            if value.range(of: #"^-?\d+;?$"#, options: .regularExpression) != nil { return names.int }
            if value.range(of: #"^-?\d+\.\d+;?$"#, options: .regularExpression) != nil { return names.double }
            if value.hasPrefix("\"") || value.hasPrefix("$\"") { return names.string }
            if ["true", "false", "true;", "false;"].contains(value.lowercased()) { return names.bool }
            if let match = value.range(of: #"^(?:New|new)\s+([\w.]+(?:<[^>]*>|\(Of[^)]*\))?)"#, options: .regularExpression) {
                return String(value[match]).replacingOccurrences(of: #"^(?:New|new)\s+"#, with: "", options: .regularExpression)
            }
            if id == "swift", let match = value.range(of: #"^[A-Z]\w*(?=\()"#, options: .regularExpression) { return String(value[match]) }
            return nil
        }
        return nil
    }

    func declare(name: String, parameters: [(name: String, type: String)], result: (name: String, type: String?)?, isStatic: Bool,
                 receiver: String?, indent: String, unit: String, body: [String], topLevel: Bool) -> String {
        let inner = indent + unit
        var lines: [String] = []
        switch id {
        case "vb":
            let list = parameters.map { "\($0.name) As \($0.type)" }.joined(separator: ", ")
            let shared = isStatic ? "Shared " : ""
            if let result {
                lines.append("\(indent)Private \(shared)Function \(name)(\(list)) As \(result.type ?? "Object")")
                lines += body
                lines.append("\(inner)Return \(result.name)")
                lines.append("\(indent)End Function")
            } else {
                lines.append("\(indent)Private \(shared)Sub \(name)(\(list))")
                lines += body
                lines.append("\(indent)End Sub")
            }
        case "csharp":
            let list = parameters.map { "\($0.type) \($0.name)" }.joined(separator: ", ")
            let modifiers = topLevel ? "static " : "private " + (isStatic ? "static " : "")
            lines.append("\(indent)\(modifiers)\(result.map { $0.type ?? "object" } ?? "void") \(name)(\(list))")
            lines.append("\(indent){")
            lines += body
            if let result { lines.append("\(inner)return \(result.name);") }
            lines.append("\(indent)}")
        case "python":
            let list = ((receiver.map { [$0] } ?? []) + parameters.map(\.name)).joined(separator: ", ")
            if isStatic { lines.append("\(indent)@staticmethod") }
            lines.append("\(indent)def \(name)(\(list)):")
            lines += body
            if let result { lines.append("\(inner)return \(result.name)") }
        case "javascript", "typescript":
            let list = parameters.map { id == "typescript" && !$0.type.isEmpty ? "\($0.name): \($0.type)" : $0.name }.joined(separator: ", ")
            lines.append(receiver != nil ? "\(indent)\(isStatic ? "static " : "")\(name)(\(list)) {" : "\(indent)function \(name)(\(list)) {")
            lines += body
            if let result { lines.append("\(inner)return \(result.name);") }
            lines.append("\(indent)}")
        default:   // swift
            let list = parameters.map { "_ \($0.name): \($0.type)" }.joined(separator: ", ")
            let modifiers = topLevel ? "" : "private " + (isStatic ? "static " : "")
            lines.append("\(indent)\(modifiers)func \(name)(\(list))\(result.map { " -> \($0.type ?? "Any")" } ?? "") {")
            lines += body
            if let result { lines.append("\(inner)return \(result.name)") }
            lines.append("\(indent)}")
        }
        return lines.joined(separator: "\n")
    }

    func statementCall(_ call: String) -> String {
        switch id {
        case "vb", "python", "swift": call
        default: call + ";"
        }
    }

    func assignCall(_ variable: String, type: String?, declare: Bool, call: String) -> String {
        guard declare else { return statementCall("\(variable) = \(call)") }
        switch id {
        case "vb": return "Dim \(variable) As \(type ?? "Object") = \(call)"
        case "csharp": return "\(type ?? "var") \(variable) = \(call);"
        case "python": return "\(variable) = \(call)"
        case "swift": return "let \(variable) = \(call)"
        default: return "let \(variable) = \(call);"
        }
    }
}
