import Foundation

/// One way to call a function, for Parameter Info: its label and where each parameter is in it (UTF-16 ranges).
public struct SignatureInfo: Sendable, Equatable {
    public let label: String
    public let parameters: [NSRange]
    public let documentation: String
    /// What each parameter is for, when known (same order as `parameters`).
    public let parameterDocs: [String]

    public init(label: String, parameters: [NSRange], documentation: String = "", parameterDocs: [String] = []) {
        self.label = label
        self.parameters = parameters
        self.documentation = documentation
        self.parameterDocs = parameterDocs
    }

    public init(label: String, documentation: String = "") {
        self.init(label: label, parameters: ParameterInfo.parameterRanges(label), documentation: documentation)
    }
}

/// The call the caret is in: `Console.WriteLine(a, |` is WriteLine on Console, second argument.
public struct CallSite: Sendable, Equatable {
    public let qualifier: [String]
    public let name: String
    public let nameStart: Int
    public let openParen: Int
    public let argument: Int
    public let isConstructor: Bool
}

/// Parameter Info (⇧⌘Space): which call the caret is in and the ways to call it. Language servers answer with
/// textDocument/signatureHelp; without one, the project's own declarations, the .NET catalog (VB.NET and C#) and the common
/// built-in functions of each language answer.
public enum ParameterInfo {
    /// Words that are followed by "(" but don't call anything.
    private static let notCalls: Set<String> = [
        "if", "elif", "while", "for", "foreach", "switch", "catch", "using", "lock", "fixed", "return", "when", "with", "sizeof", "typeof",
        "nameof", "and", "or", "not", "in", "is", "function", "def", "func", "fn", "sub", "await", "yield", "throw", "do", "else", "until",
        "select", "case", "match", "assert", "del", "guard",
    ]

    /// Words that, before a name, mean the name is being declared rather than called.
    private static let declarers: Set<String> = [
        "def", "function", "func", "fn", "sub", "void", "class", "struct", "interface", "record", "enum", "property", "event", "delegate", "operator", "init",
    ]

    private static func isIdentifier(_ c: unichar) -> Bool {
        guard let scalar = UnicodeScalar(c) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || c == 0x5F
    }

    /// The innermost call whose argument list the caret is in, or nil (outside any call, or in a string or comment).
    public static func call(in text: String, at offset: Int, language: Language) -> CallSite? {
        let ns = text as NSString
        let offset = min(max(offset, 0), ns.length)
        var from = max(0, offset - 6000)
        if from > 0 { from = NSMaxRange(ns.lineRange(for: NSRange(location: from, length: 0))) }
        let lineComments = language.lineComments + (language.id == "vb" ? ["REM "] : [])
        let quotes = Set(language.strings.filter { ($0 as NSString).length == 1 }.map { ($0 as NSString).character(at: 0) })
        let vb = language.id == "vb"
        func matches(_ marker: String, at i: Int) -> Bool {
            let length = (marker as NSString).length
            return i + length <= ns.length && ns.substring(with: NSRange(location: i, length: length)) == marker
        }
        var stack: [(bracket: unichar, position: Int, commas: Int)] = []
        var i = from
        while i < offset {
            let c = ns.character(at: i)
            if lineComments.contains(where: { matches($0, at: i) }) {
                let end = ns.range(of: "\n", options: [], range: NSRange(location: i, length: ns.length - i)).location
                if end == NSNotFound || end >= offset { return nil }
                i = end + 1
                continue
            }
            if let block = language.blockComment, matches(block.open, at: i) {
                let start = i + (block.open as NSString).length
                let end = ns.range(of: block.close, options: [], range: NSRange(location: start, length: ns.length - start)).location
                if end == NSNotFound || end + (block.close as NSString).length > offset { return nil }
                i = end + (block.close as NSString).length
                continue
            }
            if quotes.contains(c) {
                var j = i + 1
                while j < ns.length {
                    let d = ns.character(at: j)
                    if d == 0x5C, !vb { j += 2; continue }   // backslash escape
                    if d == c {
                        if vb, j + 1 < ns.length, ns.character(at: j + 1) == c { j += 2; continue }
                        break
                    }
                    if d == 0x0A, c != 0x60 { break }   // only backtick strings span lines
                    j += 1
                }
                if j >= offset { return nil }
                i = j + 1
                continue
            }
            switch c {
            case 0x28, 0x5B, 0x7B: stack.append((c, i, 0))                 // ( [ {
            case 0x29, 0x5D, 0x7D: if !stack.isEmpty { stack.removeLast() } // ) ] }
            case 0x2C where !stack.isEmpty: stack[stack.count - 1].commas += 1
            default: break
            }
            i += 1
        }
        guard let top = stack.last, top.bracket == 0x28 else { return nil }
        var k = top.position
        while k > 0, [0x20, 0x09].contains(ns.character(at: k - 1)) { k -= 1 }
        let nameEnd = k
        while k > 0, isIdentifier(ns.character(at: k - 1)) { k -= 1 }
        guard k < nameEnd, !CharacterSet.decimalDigits.contains(UnicodeScalar(ns.character(at: k)) ?? " ") else { return nil }
        let name = ns.substring(with: NSRange(location: k, length: nameEnd - k))
        guard !notCalls.contains(name.lowercased()) else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: k, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: k - lineStart))
        let previous = before.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "\t" }).last.map(String.init) ?? ""
        guard !declarers.contains(previous.lowercased()) else { return nil }
        let qualifier = before.hasSuffix(".") ? BasicIntelliSense.memberExpression(before: String(before.dropLast())) : []
        return CallSite(qualifier: qualifier, name: name, nameStart: k, openParen: top.position, argument: top.commas,
                        isConstructor: previous.lowercased() == "new")
    }

    /// Where each parameter is in a label like `Add(a As Integer, b As Integer) As Integer`.
    public static func parameterRanges(_ label: String) -> [NSRange] {
        let ns = label as NSString
        var open = ns.range(of: "(").location
        guard open != NSNotFound else { return [] }
        // VB generics: Function Map(Of T)(items As T()) — the parameters are in the second pair.
        let afterOpen = ns.substring(from: open + 1).drop { $0 == " " }
        if afterOpen.lowercased().hasPrefix("of "), let closeOf = matching(ns, open), closeOf + 1 < ns.length, ns.character(at: closeOf + 1) == 0x28 {
            open = closeOf + 1
        }
        let close = matching(ns, open) ?? ns.length
        var ranges: [NSRange] = []
        var depth = 0
        var start = open + 1
        var i = open + 1
        while i <= close {
            let c: unichar = i < close ? ns.character(at: i) : 0x2C
            switch c {
            case 0x28, 0x5B, 0x7B, 0x3C: depth += 1
            case 0x29, 0x5D, 0x7D, 0x3E: if depth > 0 { depth -= 1 }
            case 0x2C where depth == 0:
                var s = start, e = i
                while s < e, CharacterSet.whitespaces.contains(UnicodeScalar(ns.character(at: s)) ?? "x") { s += 1 }
                while e > s, CharacterSet.whitespaces.contains(UnicodeScalar(ns.character(at: e - 1)) ?? "x") { e -= 1 }
                if e > s { ranges.append(NSRange(location: s, length: e - s)) }
                start = i + 1
            default: break
            }
            i += 1
        }
        return ranges
    }

    private static func matching(_ ns: NSString, _ open: Int) -> Int? {
        var depth = 0
        for i in open..<ns.length {
            let c = ns.character(at: i)
            if c == 0x28 { depth += 1 }
            if c == 0x29 { depth -= 1; if depth == 0 { return i } }
        }
        return nil
    }

    /// Signatures without a language server: project declarations, the .NET catalog and built-in functions.
    public static func basic(text: String, call: CallSite, language: Language, symbols: [CodeSymbol]) -> [SignatureInfo] {
        let ci = language.caseInsensitiveKeywords
        func same(_ a: String?, _ b: String) -> Bool { guard let a else { return false }; return ci ? a.lowercased() == b.lowercased() : a == b }
        var labels: [String] = []
        if ["vb", "csharp"].contains(language.id), !call.qualifier.isEmpty {
            labels = BasicIntelliSense.methodSignatures(of: call.qualifier, named: call.name, text: text, offset: call.nameStart, languageId: language.id, symbols: symbols)
        } else if call.isConstructor {
            labels = symbols.filter { $0.kind == .constructor && same($0.container, call.name) }.map(\.signature)
        } else if call.qualifier.isEmpty {
            labels = symbols.filter { ($0.kind == .method || $0.kind == .function) && same($0.name, call.name) }.map(\.signature)
        }
        var seen = Set<String>()
        var result = labels.filter { $0.contains("(") && seen.insert($0).inserted }.map { SignatureInfo(label: $0) }
        let qualified = (call.qualifier + [call.name]).joined(separator: ".")
        for builtIn in BuiltInFunctions.signatures(languageId: language.id, name: qualified) where !result.contains(where: { $0.label == builtIn.label }) {
            result.append(builtIn)
        }
        return result
    }

    /// A language server's signatureHelp answer: the signatures, which one is active and which parameter.
    public static func fromLSP(_ result: Any?) -> (signatures: [SignatureInfo], active: Int, parameter: Int) {
        let object = result as? [String: Any]
        var signatures: [SignatureInfo] = []
        var actives: [Int?] = []
        for signature in object?["signatures"] as? [[String: Any]] ?? [] {
            guard let label = signature["label"] as? String else { continue }
            let ns = label as NSString
            var ranges: [NSRange] = []
            var docs: [String] = []
            var searchFrom = max(ns.range(of: "(").location == NSNotFound ? 0 : ns.range(of: "(").location, 0)
            for parameter in signature["parameters"] as? [[String: Any]] ?? [] {
                if let pair = parameter["label"] as? [Int], pair.count == 2, pair[0] <= pair[1], pair[1] <= ns.length {
                    ranges.append(NSRange(location: pair[0], length: pair[1] - pair[0]))
                    searchFrom = pair[1]
                } else if let part = parameter["label"] as? String, !part.isEmpty {
                    var found = ns.range(of: part, options: [], range: NSRange(location: searchFrom, length: ns.length - searchFrom))
                    if found.location == NSNotFound { found = ns.range(of: part) }
                    ranges.append(found.location == NSNotFound ? NSRange(location: 0, length: 0) : found)
                    if found.location != NSNotFound { searchFrom = NSMaxRange(found) }
                } else {
                    ranges.append(NSRange(location: 0, length: 0))
                }
                docs.append(documentation(parameter["documentation"]))
            }
            signatures.append(SignatureInfo(label: label, parameters: ranges, documentation: documentation(signature["documentation"]), parameterDocs: docs))
            actives.append(signature["activeParameter"] as? Int)
        }
        let active = min(max(object?["activeSignature"] as? Int ?? 0, 0), max(signatures.count - 1, 0))
        let parameter = (actives.indices.contains(active) ? actives[active] : nil) ?? object?["activeParameter"] as? Int ?? 0
        return (signatures, active, parameter)
    }

    private static func documentation(_ value: Any?) -> String {
        if let markup = value as? [String: Any], let text = markup["value"] as? String { return HoverText.plain(text) }
        if let text = value as? String { return HoverText.plain(text) }
        return ""
    }

    /// The parameter to show in bold: the argument the caret is in (the last one for a params/... list), or -1.
    public static func activeParameter(_ signature: SignatureInfo, argument: Int) -> Int {
        guard !signature.parameters.isEmpty else { return -1 }
        if argument < signature.parameters.count { return argument }
        let last = (signature.label as NSString).substring(with: signature.parameters[signature.parameters.count - 1])
        return last.contains("...") || last.lowercased().contains("paramarray") || last.hasPrefix("params ") || last.hasPrefix("*")
            ? signature.parameters.count - 1 : -1
    }

    /// The overload that best fits the arguments typed so far: the first with enough parameters.
    public static func bestOverload(_ signatures: [SignatureInfo], argument: Int) -> Int {
        signatures.firstIndex { activeParameter($0, argument: argument) >= 0 } ?? 0
    }
}

/// The built-in functions beginners use most, with a line on what each does, so Parameter Info and the completion list
/// can explain them even without a language server.
public enum BuiltInFunctions {
    private static let all: [(language: String, name: String, label: String, documentation: String)] = [
        ("python", "print", "print(*values, sep=' ', end='\\n')", "Writes the values to the output, separated by sep and followed by end."),
        ("python", "input", "input(prompt='') -> str", "Shows the prompt and waits for the user to type a line; returns what was typed as text."),
        ("python", "len", "len(obj) -> int", "How many items are in a list, string, dictionary or other collection."),
        ("python", "range", "range(start, stop, step=1)", "The numbers from start up to (not including) stop. range(5) is 0, 1, 2, 3, 4."),
        ("python", "int", "int(value, base=10) -> int", "Turns text or a number into a whole number: int(\"42\") is 42."),
        ("python", "float", "float(value) -> float", "Turns text or a number into a decimal number: float(\"2.5\") is 2.5."),
        ("python", "str", "str(value) -> str", "Turns a value into text: str(42) is \"42\"."),
        ("python", "open", "open(file, mode='r', encoding=None)", "Opens a file. mode is 'r' to read, 'w' to write (replacing it) or 'a' to add to the end."),
        ("python", "enumerate", "enumerate(iterable, start=0)", "Pairs each item with its position: for i, item in enumerate(items)."),
        ("python", "zip", "zip(*iterables)", "Walks several lists side by side: for a, b in zip(list1, list2)."),
        ("python", "sorted", "sorted(iterable, key=None, reverse=False) -> list", "A new list with the items in order."),
        ("python", "abs", "abs(x)", "The number without its sign: abs(-3) is 3."),
        ("python", "round", "round(number, ndigits=None)", "Rounds to ndigits decimal places (to a whole number without it)."),
        ("python", "min", "min(iterable, key=None)", "The smallest item."),
        ("python", "max", "max(iterable, key=None)", "The largest item."),
        ("python", "sum", "sum(iterable, start=0)", "Adds up the numbers."),
        ("python", "isinstance", "isinstance(obj, class_or_tuple) -> bool", "Whether a value is of a type: isinstance(x, int)."),
        ("python", "list", "list(iterable=()) -> list", "A new list, from the items of another collection."),
        ("python", "dict", "dict(**kwargs) -> dict", "A new dictionary (key → value pairs)."),
        ("c", "printf", "int printf(const char *format, ...)", "Writes formatted text: %d for whole numbers, %f for decimals, %s for text, %c for a character."),
        ("c", "scanf", "int scanf(const char *format, ...)", "Reads input into variables; pass their addresses: scanf(\"%d\", &number)."),
        ("c", "malloc", "void *malloc(size_t size)", "Reserves size bytes of memory; give it back with free() when done."),
        ("c", "free", "void free(void *ptr)", "Gives back memory reserved with malloc."),
        ("c", "strlen", "size_t strlen(const char *s)", "How many characters a string has (not counting the ending \\0)."),
        ("c", "strcpy", "char *strcpy(char *dest, const char *src)", "Copies src into dest; dest must be big enough."),
        ("c", "strcmp", "int strcmp(const char *a, const char *b)", "Compares two strings: 0 when they're equal."),
        ("c", "fopen", "FILE *fopen(const char *path, const char *mode)", "Opens a file: mode \"r\" reads, \"w\" writes, \"a\" appends. Returns NULL if it fails."),
        ("c", "fclose", "int fclose(FILE *stream)", "Closes a file opened with fopen."),
        ("javascript", "console.log", "console.log(...data)", "Writes the values to the console (the Output window)."),
        ("javascript", "parseInt", "parseInt(string, radix?)", "Reads a whole number from text: parseInt(\"42\") is 42."),
        ("javascript", "parseFloat", "parseFloat(string)", "Reads a decimal number from text: parseFloat(\"2.5\") is 2.5."),
        ("javascript", "setTimeout", "setTimeout(callback, delay)", "Runs the function once, after delay milliseconds."),
        ("javascript", "setInterval", "setInterval(callback, delay)", "Runs the function again and again, every delay milliseconds."),
        ("javascript", "alert", "alert(message)", "Shows a message box in the browser."),
        ("javascript", "fetch", "fetch(url, options?)", "Downloads from a URL; await it to get the response."),
        ("javascript", "document.getElementById", "document.getElementById(id)", "The element on the page with this id, or null."),
        ("javascript", "document.querySelector", "document.querySelector(selectors)", "The first element on the page that matches the CSS selector, or null."),
        ("go", "fmt.Println", "func Println(a ...any) (n int, err error)", "Writes the values separated by spaces, then a new line."),
        ("go", "fmt.Printf", "func Printf(format string, a ...any) (n int, err error)", "Writes formatted text: %d for whole numbers, %f for decimals, %s for text, %v for any value."),
        ("go", "fmt.Sprintf", "func Sprintf(format string, a ...any) string", "Like Printf, but returns the text instead of writing it."),
        ("go", "len", "func len(v Type) int", "How many items are in a slice, map, string or array."),
        ("go", "append", "func append(slice []Type, elems ...Type) []Type", "Adds items to the end of a slice; keep the result: s = append(s, x)."),
        ("go", "make", "func make(t Type, size ...IntegerType) Type", "Creates a slice, map or channel: make([]int, 5), make(map[string]int)."),
        ("java", "System.out.println", "void println(Object x)", "Writes the value, then a new line."),
        ("java", "System.out.print", "void print(Object x)", "Writes the value without a new line."),
        ("java", "System.out.printf", "PrintStream printf(String format, Object... args)", "Writes formatted text: %d for whole numbers, %f for decimals, %s for text."),
        ("java", "Integer.parseInt", "static int parseInt(String s)", "Reads a whole number from text: Integer.parseInt(\"42\") is 42."),
        ("rust", "println", "println!(\"{}\", value)", "Writes formatted text and a new line; {} is replaced by each value in turn."),
        ("swift", "print", "print(_ items: Any..., separator: String = \" \", terminator: String = \"\\n\")", "Writes the values to the output."),
        ("vb", "MsgBox", "MsgBox(Prompt As Object, Buttons As MsgBoxStyle, Title As Object) As MsgBoxResult", "Shows a message box and returns the button that was clicked."),
        ("vb", "InputBox", "InputBox(Prompt As String, Title As String, DefaultResponse As String) As String", "Asks the user to type a value and returns it."),
    ]

    /// The built-in function with this name (or qualified name, like `console.log`) in a language.
    public static func signatures(languageId: String, name: String) -> [SignatureInfo] {
        let language = languageId == "typescript" ? "javascript" : languageId
        let ci = languageId == "vb"
        return all.filter { ($0.language == language || (language == "cpp" && $0.language == "c")) && (ci ? $0.name.lowercased() == name.lowercased() : $0.name == name) }
            .map { SignatureInfo(label: $0.label, documentation: $0.documentation) }
    }

    /// What a built-in function does, for the completion list's explanation.
    public static func explain(languageId: String, name: String) -> String? {
        signatures(languageId: languageId, name: name).first.map { $0.label + "\n\n" + $0.documentation }
    }
}
