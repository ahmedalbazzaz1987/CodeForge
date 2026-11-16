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

    public static let all: [CodeSnippet] = vb + csharp + python + javascript + typescript + swift + html + c + cpp + java + go + rust + fsharp

    static let c: [CodeSnippet] = [
        make("c", "main", "main", "#include <stdio.h>\n\nint main(void) {\n    $0\n    return 0;\n}"),
        make("c", "for", "for loop", "for (int ${1:i} = 0; $1 < ${2:count}; $1++) {\n    $0\n}"),
        make("c", "if", "if statement", "if (${1:condition}) {\n    $0\n}"),
        make("c", "while", "while loop", "while (${1:condition}) {\n    $0\n}"),
        make("c", "struct", "typedef struct", "typedef struct {\n    ${1:int} ${2:value};\n} ${3:Name};$0"),
        make("c", "pf", "printf", "printf(\"$1\\n\");$0"),
    ]

    static let cpp: [CodeSnippet] = [
        make("cpp", "main", "main", "#include <iostream>\n\nint main() {\n    $0\n    return 0;\n}"),
        make("cpp", "class", "Class", "class ${1:Name} {\npublic:\n    $1() = default;\n\nprivate:\n    int ${2:value_} = 0;\n};$0"),
        make("cpp", "for", "Range for", "for (const auto& ${1:item} : ${2:items}) {\n    $0\n}"),
        make("cpp", "if", "if statement", "if (${1:condition}) {\n    $0\n}"),
        make("cpp", "cout", "std::cout", "std::cout << $1 << std::endl;$0"),
        make("cpp", "try", "try…catch", "try {\n    $0\n} catch (const std::exception& error) {\n    std::cerr << error.what() << std::endl;\n}"),
    ]

    static let java: [CodeSnippet] = [
        make("java", "main", "main method", "public static void main(String[] args) {\n    $0\n}"),
        make("java", "sout", "System.out.println", "System.out.println($0);"),
        make("java", "class", "Class", "public class ${1:Name} {\n    $0\n}"),
        make("java", "for", "for each", "for (var ${1:item} : ${2:items}) {\n    $0\n}"),
        make("java", "if", "if statement", "if (${1:condition}) {\n    $0\n}"),
        make("java", "try", "try…catch", "try {\n    $0\n} catch (Exception error) {\n    error.printStackTrace();\n}"),
    ]

    static let typescript: [CodeSnippet] = [
        make("typescript", "fn", "Typed function", "function ${1:name}(${2:value}: ${3:string}): ${4:string} {\n    ${5:return value;}\n}$0"),
        make("typescript", "afn", "Arrow function", "const ${1:name} = (${2:value}: ${3:string}): ${4:string} => {\n    ${5:return value;}\n};$0"),
        make("typescript", "int", "Interface", "interface ${1:Name} {\n    ${2:id}: ${3:number};\n}$0"),
        make("typescript", "type", "Type", "type ${1:Name} = {\n    ${2:id}: ${3:number};\n};$0"),
        make("typescript", "class", "Class", "class ${1:Name} {\n    constructor(private readonly ${2:id}: ${3:number}) {}\n}$0"),
        make("typescript", "log", "console.log", "console.log($0);"),
    ]

    static let go: [CodeSnippet] = [
        make("go", "main", "main", "func main() {\n\t$0\n}"),
        make("go", "func", "Function", "func ${1:name}($2) ${3:error} {\n\t${4:return nil}\n}$0"),
        make("go", "iferr", "if err != nil", "if err != nil {\n\treturn ${1:err}\n}$0"),
        make("go", "for", "for range", "for _, ${1:item} := range ${2:items} {\n\t$0\n}"),
        make("go", "pl", "fmt.Println", "fmt.Println($0)"),
    ]

    static let rust: [CodeSnippet] = [
        make("rust", "main", "main", "fn main() {\n    $0\n}"),
        make("rust", "fn", "Function", "fn ${1:name}($2) -> ${3:i32} {\n    ${4:0}\n}$0"),
        make("rust", "struct", "Struct", "struct ${1:Name} {\n    ${2:id}: ${3:u32},\n}$0"),
        make("rust", "match", "match", "match ${1:value} {\n    Some(${2:item}) => {}\n    None => {}\n}$0"),
        make("rust", "pl", "println!", "println!(\"{}\", $1);$0"),
    ]

    static let fsharp = [
        make("fsharp", "let", "Function", "let ${1:name} ${2:x} =\n    ${3:x}$0"),
        make("fsharp", "rec", "Recursive function", "let rec ${1:name} n =\n    if n <= 0 then 0 else n + $1 (n - 1)$0"),
        make("fsharp", "type", "Record type", "type ${1:Name} = { ${2:Field}: ${3:string} }$0"),
        make("fsharp", "union", "Discriminated union", "type ${1:Shape} =\n    | ${2:Circle} of float\n    | ${3:Square} of float$0"),
        make("fsharp", "match", "match expression", "match ${1:value} with\n| Some x -> x\n| None -> 0$0"),
        make("fsharp", "for", "for…in loop", "for ${1:item} in ${2:items} do\n    printfn \"%A\" $1$0"),
        make("fsharp", "pf", "printfn", "printfn \"%A\" $0"),
        make("fsharp", "async", "async block", "async {\n    $0\n    return ()\n}"),
        make("fsharp", "try", "try…with", "try\n    $0\nwith ex ->\n    printfn \"%s\" ex.Message"),
    ]

    static let vb: [CodeSnippet] = [
        make("vb", "Sub", "Sub procedure", "Public Sub ${1:MethodName}()\n    $0\nEnd Sub"),
        make("vb", "Function", "Function", "Public Function ${1:FunctionName}() As ${2:Integer}\n    Return ${3:0}$0\nEnd Function"),
        make("vb", "Property", "Property", "Public Property ${1:Name} As ${2:String}$0"),
        make("vb", "PropertyFull", "Property with backing field", "Private ${1:_name} As ${2:String}\n\nPublic Property ${3:Name} As $2\n    Get\n        Return $1\n    End Get\n    Set(value As $2)\n        $1 = value$0\n    End Set\nEnd Property"),
        make("vb", "Class", "Class", "Public Class ${1:ClassName}\n    $0\nEnd Class"),
        make("vb", "Module", "Module", "Module ${1:ModuleName}\n    $0\nEnd Module"),
        make("vb", "If", "If…Then…End If", "If ${1:condition} Then\n    $0\nEnd If"),
        make("vb", "IfElse", "If…Else…End If", "If ${1:condition} Then\n    $2\nElse\n    $0\nEnd If"),
        make("vb", "For", "For…Next", "For ${1:i} As Integer = ${2:0} To ${3:10}\n    $0\nNext"),
        make("vb", "ForEach", "For Each…Next", "For Each ${1:item} In ${2:collection}\n    $0\nNext"),
        make("vb", "While", "While…End While", "While ${1:condition}\n    $0\nEnd While"),
        make("vb", "DoLoop", "Do…Loop Until", "Do\n    $0\nLoop Until condition"),
        make("vb", "Select", "Select Case", "Select Case ${1:value}\n    Case ${2:1}\n        $0\n    Case Else\n        \nEnd Select"),
        make("vb", "Try", "Try…Catch…End Try", "Try\n    $0\nCatch ex As Exception\n    Console.WriteLine(ex.Message)\nEnd Try"),
        make("vb", "TryF", "Try…Catch…Finally", "Try\n    $0\nCatch ex As Exception\n    \nFinally\n    \nEnd Try"),
        make("vb", "Using", "Using block", "Using ${1:resource} = ${2:New Object()}\n    $0\nEnd Using"),
        make("vb", "cw", "Console.WriteLine", "Console.WriteLine($0)"),
        make("vb", "Dim", "Dim variable", "Dim ${1:name} As ${2:String} = ${3:\"\"}$0"),
        make("vb", "Ctor", "Constructor (Sub New)", "Public Sub New($1)\n    $0\nEnd Sub"),
        make("vb", "Enum", "Enum", "Public Enum ${1:Name}\n    ${2:First}\n    ${3:Second}\nEnd Enum$0"),
        make("vb", "Interface", "Interface", "Public Interface I${1:Name}\n    $0\nEnd Interface"),
        make("vb", "Main", "Sub Main", "Sub Main(args As String())\n    $0\nEnd Sub"),
    ]

    static let csharp: [CodeSnippet] = [
        make("csharp", "prop", "Auto-implemented property", "public ${1:int} ${2:MyProperty} { get; set; }$0"),
        make("csharp", "propfull", "Property with backing field", "private ${1:int} ${2:_myVar};\n\npublic $1 ${3:MyProperty}\n{\n    get { return $2; }\n    set { $2 = value; }\n}$0"),
        make("csharp", "ctor", "Constructor", "public ${1:ClassName}()\n{\n    $0\n}"),
        make("csharp", "class", "Class", "public class ${1:MyClass}\n{\n    $0\n}"),
        make("csharp", "interface", "Interface", "public interface I${1:Name}\n{\n    $0\n}"),
        make("csharp", "enum", "Enum", "public enum ${1:MyEnum}\n{\n    ${2:First},\n    ${3:Second}\n}$0"),
        make("csharp", "record", "Record", "public record ${1:Person}(${2:string Name, int Age});$0"),
        make("csharp", "for", "for loop", "for (int ${1:i} = 0; $1 < ${2:length}; $1++)\n{\n    $0\n}"),
        make("csharp", "forr", "Reverse for loop", "for (int ${1:i} = ${2:length} - 1; $1 >= 0; $1--)\n{\n    $0\n}"),
        make("csharp", "foreach", "foreach loop", "foreach (${1:var} ${2:item} in ${3:collection})\n{\n    $0\n}"),
        make("csharp", "while", "while loop", "while (${1:condition})\n{\n    $0\n}"),
        make("csharp", "do", "do…while loop", "do\n{\n    $0\n} while (${1:condition});"),
        make("csharp", "if", "if statement", "if (${1:condition})\n{\n    $0\n}"),
        make("csharp", "else", "else block", "else\n{\n    $0\n}"),
        make("csharp", "switch", "switch statement", "switch (${1:value})\n{\n    case ${2:1}:\n        $0\n        break;\n    default:\n        break;\n}"),
        make("csharp", "try", "try…catch", "try\n{\n    $0\n}\ncatch (Exception ex)\n{\n    Console.WriteLine(ex.Message);\n}"),
        make("csharp", "tryf", "try…finally", "try\n{\n    $0\n}\nfinally\n{\n    \n}"),
        make("csharp", "using", "using statement", "using (var ${1:resource} = ${2:new Resource()})\n{\n    $0\n}"),
        make("csharp", "cw", "Console.WriteLine", "Console.WriteLine($0);"),
        make("csharp", "svm", "static void Main", "static void Main(string[] args)\n{\n    $0\n}"),
        make("csharp", "async", "Async method", "public async Task ${1:MethodAsync}()\n{\n    await Task.Delay(1);$0\n}"),
        make("csharp", "test", "xUnit test", "[Fact]\npublic void ${1:Test}()\n{\n    Assert.True(true);$0\n}"),
    ]

    static let python: [CodeSnippet] = [
        make("python", "def", "Function", "def ${1:name}($2):\n    ${3:pass}$0"),
        make("python", "class", "Class", "class ${1:Name}:\n    def __init__(self$2):\n        ${3:pass}$0"),
        make("python", "main", "Main guard", "def main():\n    $0\n\n\nif __name__ == \"__main__\":\n    main()"),
        make("python", "for", "for loop", "for ${1:item} in ${2:items}:\n    ${3:pass}$0"),
        make("python", "if", "if statement", "if ${1:condition}:\n    ${2:pass}$0"),
        make("python", "try", "try…except", "try:\n    $0\nexcept Exception as error:\n    print(error)"),
        make("python", "with", "with open", "with open(${1:\"file.txt\"}) as ${2:file}:\n    ${3:text} = $2.read()$0"),
    ]

    static let javascript: [CodeSnippet] = [
        make("javascript", "fn", "Function", "function ${1:name}($2) {\n    $0\n}"),
        make("javascript", "afn", "Arrow function", "const ${1:name} = ($2) => {\n    $0\n};"),
        make("javascript", "for", "for loop", "for (let ${1:i} = 0; $1 < ${2:array}.length; $1++) {\n    $0\n}"),
        make("javascript", "forof", "for…of loop", "for (const ${1:item} of ${2:items}) {\n    $0\n}"),
        make("javascript", "if", "if statement", "if (${1:condition}) {\n    $0\n}"),
        make("javascript", "try", "try…catch", "try {\n    $0\n} catch (error) {\n    console.error(error);\n}"),
        make("javascript", "log", "console.log", "console.log($0);"),
        make("javascript", "class", "Class", "class ${1:Name} {\n    constructor($2) {\n        $0\n    }\n}"),
        make("javascript", "fetch", "fetch JSON", "const response = await fetch(${1:url});\nconst ${2:data} = await response.json();$0"),
    ]

    static let swift: [CodeSnippet] = [
        make("swift", "func", "Function", "func ${1:name}($2) {\n    $0\n}"),
        make("swift", "struct", "Struct", "struct ${1:Name} {\n    $0\n}"),
        make("swift", "class", "Class", "final class ${1:Name} {\n    $0\n}"),
        make("swift", "guard", "guard let", "guard let ${1:value} else { ${2:return} }$0"),
        make("swift", "iflet", "if let", "if let ${1:value} {\n    $0\n}"),
        make("swift", "for", "for…in loop", "for ${1:item} in ${2:items} {\n    $0\n}"),
        make("swift", "switch", "switch", "switch ${1:value} {\ncase ${2:.first}:\n    ${3:break}\ndefault:\n    break\n}$0"),
        make("swift", "do", "do…catch", "do {\n    try $0\n} catch {\n    print(error)\n}"),
        make("swift", "view", "SwiftUI view", "struct ${1:ContentView}: View {\n    var body: some View {\n        ${2:Text(\"Hello\")}\n    }\n}$0"),
    ]

    static let html: [CodeSnippet] = [
        make("html", "html5", "HTML5 page", "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>${1:Page}</title>\n</head>\n<body>\n    $0\n</body>\n</html>"),
        make("html", "div", "div", "<div>$0</div>"),
        make("html", "a", "Link", "<a href=\"${1:#}\">${2:text}</a>$0"),
        make("html", "img", "Image", "<img src=\"${1:image.png}\" alt=\"${2:description}\">$0"),
        make("html", "ul", "List", "<ul>\n    <li>$0</li>\n</ul>"),
        make("html", "script", "Script", "<script>\n    $0\n</script>"),
    ]
}
