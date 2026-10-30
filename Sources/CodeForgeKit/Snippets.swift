import Foundation

/// A code snippet: type its shortcut and press Tab, pick it from IntelliSense, or insert it from the Toolbox.
/// `$0` in the body marks where the cursor goes, as in Toolbox items.
public struct CodeSnippet: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var shortcut: String
    public var languageId: String
    public var summary: String
    public var body: String
    public var isBuiltIn: Bool

    public init(id: String = UUID().uuidString, title: String, shortcut: String, languageId: String, summary: String = "", body: String, isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.languageId = languageId
        self.summary = summary
        self.body = body
        self.isBuiltIn = isBuiltIn
    }

    public var toolboxItem: ToolboxItem { ToolboxItem(title, "text.badge.plus", body) }
}

/// Built-in snippets plus the user's own, saved as JSON. A user snippet with a built-in's id replaces it.
public struct SnippetLibrary: Sendable {
    public private(set) var userSnippets: [CodeSnippet]
    /// Built-in snippets the user deleted.
    public private(set) var hidden: Set<String>

    public init(userSnippets: [CodeSnippet] = [], hidden: Set<String> = []) {
        self.userSnippets = userSnippets
        self.hidden = hidden
    }

    private struct Stored: Codable {
        var snippets: [CodeSnippet]
        var hidden: [String]?
    }

    public init(contentsOf url: URL) {
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        self.init(userSnippets: stored?.snippets ?? [], hidden: Set(stored?.hidden ?? []))
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Stored(snippets: userSnippets, hidden: hidden.sorted())).write(to: url, options: .atomic)
    }

    public var all: [CodeSnippet] {
        let overridden = Set(userSnippets.map(\.id))
        return BuiltInSnippets.all.filter { !overridden.contains($0.id) && !hidden.contains($0.id) } + userSnippets
    }

    public func snippets(forLanguage id: String) -> [CodeSnippet] {
        all.filter { $0.languageId == id }.sorted { $0.shortcut.lowercased() < $1.shortcut.lowercased() }
    }

    /// The snippet for a shortcut typed before Tab. VB shortcuts ignore case, like the language.
    public func snippet(shortcut: String, languageId: String) -> CodeSnippet? {
        let caseInsensitive = languageId == "vb"
        return snippets(forLanguage: languageId).first {
            caseInsensitive ? $0.shortcut.lowercased() == shortcut.lowercased() : $0.shortcut == shortcut
        }
    }

    /// Adds or replaces a snippet (a changed built-in is saved as a user copy with the same id).
    public mutating func save(_ snippet: CodeSnippet) {
        var copy = snippet
        copy.isBuiltIn = false
        if let index = userSnippets.firstIndex(where: { $0.id == snippet.id }) { userSnippets[index] = copy } else { userSnippets.append(copy) }
    }

    public mutating func delete(id: String) {
        userSnippets.removeAll { $0.id == id }
        if BuiltInSnippets.all.contains(where: { $0.id == id }) { hidden.insert(id) }
    }

    /// Brings back the built-in snippets the user changed or deleted.
    public mutating func restoreBuiltIns() {
        let builtIn = Set(BuiltInSnippets.all.map(\.id))
        userSnippets.removeAll { builtIn.contains($0.id) }
        hidden = []
    }
}

public enum BuiltInSnippets {
    private static func make(_ language: String, _ shortcut: String, _ title: String, _ body: String) -> CodeSnippet {
        CodeSnippet(id: "builtin.\(language).\(shortcut)", title: title, shortcut: shortcut, languageId: language, body: body, isBuiltIn: true)
    }

    public static let all: [CodeSnippet] = vb + csharp + python + javascript + swift + html

    static let vb: [CodeSnippet] = [
        make("vb", "Sub", "Sub procedure", "Public Sub $0MethodName()\n    \nEnd Sub"),
        make("vb", "Function", "Function", "Public Function $0FunctionName() As Integer\n    Return 0\nEnd Function"),
        make("vb", "Property", "Property", "Public Property $0Name As String"),
        make("vb", "PropertyFull", "Property with backing field", "Private _name As String\n\nPublic Property Name As String\n    Get\n        Return _name\n    End Get\n    Set(value As String)\n        _name = value$0\n    End Set\nEnd Property"),
        make("vb", "Class", "Class", "Public Class $0ClassName\n    \nEnd Class"),
        make("vb", "Module", "Module", "Module $0ModuleName\n    \nEnd Module"),
        make("vb", "If", "If…Then…End If", "If $0condition Then\n    \nEnd If"),
        make("vb", "IfElse", "If…Else…End If", "If $0condition Then\n    \nElse\n    \nEnd If"),
        make("vb", "For", "For…Next", "For i As Integer = 0 To $010\n    \nNext"),
        make("vb", "ForEach", "For Each…Next", "For Each item In $0collection\n    \nNext"),
        make("vb", "While", "While…End While", "While $0condition\n    \nEnd While"),
        make("vb", "DoLoop", "Do…Loop Until", "Do\n    $0\nLoop Until condition"),
        make("vb", "Select", "Select Case", "Select Case $0value\n    Case 1\n        \n    Case Else\n        \nEnd Select"),
        make("vb", "Try", "Try…Catch…End Try", "Try\n    $0\nCatch ex As Exception\n    Console.WriteLine(ex.Message)\nEnd Try"),
        make("vb", "TryF", "Try…Catch…Finally", "Try\n    $0\nCatch ex As Exception\n    \nFinally\n    \nEnd Try"),
        make("vb", "Using", "Using block", "Using $0resource = New Object()\n    \nEnd Using"),
        make("vb", "cw", "Console.WriteLine", "Console.WriteLine($0)"),
        make("vb", "Dim", "Dim variable", "Dim $0name As String = \"\""),
        make("vb", "Ctor", "Constructor (Sub New)", "Public Sub New($0)\n    \nEnd Sub"),
        make("vb", "Enum", "Enum", "Public Enum $0Name\n    First\n    Second\nEnd Enum"),
        make("vb", "Interface", "Interface", "Public Interface I$0Name\n    \nEnd Interface"),
        make("vb", "Main", "Sub Main", "Sub Main(args As String())\n    $0\nEnd Sub"),
    ]

    static let csharp: [CodeSnippet] = [
        make("csharp", "prop", "Auto-implemented property", "public $0int MyProperty { get; set; }"),
        make("csharp", "propfull", "Property with backing field", "private int _myVar;\n\npublic int MyProperty\n{\n    get { return _myVar; }\n    set { _myVar = value;$0 }\n}"),
        make("csharp", "ctor", "Constructor", "public $0ClassName()\n{\n    \n}"),
        make("csharp", "class", "Class", "public class $0MyClass\n{\n    \n}"),
        make("csharp", "interface", "Interface", "public interface I$0Name\n{\n    \n}"),
        make("csharp", "enum", "Enum", "public enum $0MyEnum\n{\n    First,\n    Second\n}"),
        make("csharp", "record", "Record", "public record $0Person(string Name, int Age);"),
        make("csharp", "for", "for loop", "for (int i = 0; i < $0length; i++)\n{\n    \n}"),
        make("csharp", "forr", "Reverse for loop", "for (int i = $0length - 1; i >= 0; i--)\n{\n    \n}"),
        make("csharp", "foreach", "foreach loop", "foreach (var item in $0collection)\n{\n    \n}"),
        make("csharp", "while", "while loop", "while ($0condition)\n{\n    \n}"),
        make("csharp", "do", "do…while loop", "do\n{\n    $0\n} while (condition);"),
        make("csharp", "if", "if statement", "if ($0condition)\n{\n    \n}"),
        make("csharp", "else", "else block", "else\n{\n    $0\n}"),
        make("csharp", "switch", "switch statement", "switch ($0value)\n{\n    case 1:\n        break;\n    default:\n        break;\n}"),
        make("csharp", "try", "try…catch", "try\n{\n    $0\n}\ncatch (Exception ex)\n{\n    Console.WriteLine(ex.Message);\n}"),
        make("csharp", "tryf", "try…finally", "try\n{\n    $0\n}\nfinally\n{\n    \n}"),
        make("csharp", "using", "using statement", "using (var $0resource = new Resource())\n{\n    \n}"),
        make("csharp", "cw", "Console.WriteLine", "Console.WriteLine($0);"),
        make("csharp", "svm", "static void Main", "static void Main(string[] args)\n{\n    $0\n}"),
        make("csharp", "async", "Async method", "public async Task $0MethodAsync()\n{\n    await Task.Delay(1);\n}"),
        make("csharp", "test", "xUnit test", "[Fact]\npublic void $0Test()\n{\n    Assert.True(true);\n}"),
    ]

    static let python: [CodeSnippet] = [
        make("python", "def", "Function", "def $0name():\n    pass"),
        make("python", "class", "Class", "class $0Name:\n    def __init__(self):\n        pass"),
        make("python", "main", "Main guard", "def main():\n    $0\n\n\nif __name__ == \"__main__\":\n    main()"),
        make("python", "for", "for loop", "for item in $0items:\n    pass"),
        make("python", "if", "if statement", "if $0condition:\n    pass"),
        make("python", "try", "try…except", "try:\n    $0\nexcept Exception as error:\n    print(error)"),
        make("python", "with", "with open", "with open($0\"file.txt\") as file:\n    text = file.read()"),
    ]

    static let javascript: [CodeSnippet] = [
        make("javascript", "fn", "Function", "function $0name() {\n    \n}"),
        make("javascript", "afn", "Arrow function", "const $0name = () => {\n    \n};"),
        make("javascript", "for", "for loop", "for (let i = 0; i < $0array.length; i++) {\n    \n}"),
        make("javascript", "forof", "for…of loop", "for (const item of $0items) {\n    \n}"),
        make("javascript", "if", "if statement", "if ($0condition) {\n    \n}"),
        make("javascript", "try", "try…catch", "try {\n    $0\n} catch (error) {\n    console.error(error);\n}"),
        make("javascript", "log", "console.log", "console.log($0);"),
        make("javascript", "class", "Class", "class $0Name {\n    constructor() {\n        \n    }\n}"),
        make("javascript", "fetch", "fetch JSON", "const response = await fetch($0url);\nconst data = await response.json();"),
    ]

    static let swift: [CodeSnippet] = [
        make("swift", "func", "Function", "func $0name() {\n    \n}"),
        make("swift", "struct", "Struct", "struct $0Name {\n    \n}"),
        make("swift", "class", "Class", "final class $0Name {\n    \n}"),
        make("swift", "guard", "guard let", "guard let $0value else { return }"),
        make("swift", "iflet", "if let", "if let $0value {\n    \n}"),
        make("swift", "for", "for…in loop", "for item in $0items {\n    \n}"),
        make("swift", "switch", "switch", "switch $0value {\ncase .first:\n    break\ndefault:\n    break\n}"),
        make("swift", "do", "do…catch", "do {\n    try $0\n} catch {\n    print(error)\n}"),
        make("swift", "view", "SwiftUI view", "struct $0ContentView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}"),
    ]

    static let html: [CodeSnippet] = [
        make("html", "html5", "HTML5 page", "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>$0Page</title>\n</head>\n<body>\n    \n</body>\n</html>"),
        make("html", "div", "div", "<div>$0</div>"),
        make("html", "a", "Link", "<a href=\"$0\"></a>"),
        make("html", "img", "Image", "<img src=\"$0\" alt=\"\">"),
        make("html", "ul", "List", "<ul>\n    <li>$0</li>\n</ul>"),
        make("html", "script", "Script", "<script>\n    $0\n</script>"),
    ]
}
