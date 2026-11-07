import XCTest
@testable import CodeForgeKit

final class FindInFilesTests: XCTestCase {
    func testMatchesAndOptions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cf-find-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "Module Program\n    Sub Main()\n        Console.WriteLine(total)\n        Dim totals = 2\n    End Sub\nEnd Module\n"
            .write(to: folder.appendingPathComponent("Program.vb"), atomically: true, encoding: .utf8)
        try "total = 1\n".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "total".write(to: folder.appendingPathComponent("bin/skip.vb"), atomically: true, encoding: .utf8)

        let all = FileSearch.search("total", in: folder, options: SearchOptions())
        XCTAssertEqual(all.count, 3)                                    // bin/ is skipped
        let vb = all.filter { $0.url.pathExtension == "vb" }
        XCTAssertEqual(vb.map(\.line), [3, 4])
        XCTAssertEqual(vb[0].column, 27)
        XCTAssertEqual(vb[0].preview, "        Console.WriteLine(total)")

        XCTAssertEqual(FileSearch.search("total", in: folder, options: SearchOptions(wholeWord: true)).count, 2)
        XCTAssertEqual(FileSearch.search("TOTAL", in: folder, options: SearchOptions(matchCase: true)).count, 0)
        XCTAssertEqual(FileSearch.search("total", in: folder, options: SearchOptions(fileTypes: "*.vb")).count, 2)
        XCTAssertEqual(FileSearch.search(#"Dim (\w+)"#, in: folder, options: SearchOptions(regularExpression: true)).count, 1)
        XCTAssertNil(FileSearch.expression(for: "(", options: SearchOptions(regularExpression: true)))
    }

    func testReplace() {
        let expression = FileSearch.expression(for: "count", options: SearchOptions(wholeWord: true))!
        let result = FileSearch.replace(in: "count = count + 1 ' counter", expression: expression, with: "total", regularExpression: false)
        XCTAssertEqual(result.text, "total = total + 1 ' counter")
        XCTAssertEqual(result.count, 2)
        let regex = FileSearch.expression(for: #"(\w+)\.Length"#, options: SearchOptions(regularExpression: true))!
        XCTAssertEqual(FileSearch.replace(in: "name.Length", expression: regex, with: "Len($1)", regularExpression: true).text, "Len(name)")
        // Without regular expressions, `$1` is literal text.
        XCTAssertEqual(FileSearch.replace(in: "a", expression: FileSearch.expression(for: "a", options: SearchOptions())!, with: "$1", regularExpression: false).text, "$1")
    }
}

final class ExtractMethodTests: XCTestCase {
    private func extract(_ text: String, lines: ClosedRange<Int>, language: String) -> Result<ExtractMethod.Result, ExtractMethod.Failure> {
        let starts = TextLines(text).lineStarts
        let start = starts[lines.lowerBound - 1]
        let end = lines.upperBound < starts.count ? starts[lines.upperBound] : (text as NSString).length
        return ExtractMethod.extract(text, selection: NSRange(location: start, length: end - start), languageId: language)
    }

    func testVisualBasic() throws {
        let code = """
            Module Program
                Sub Main(args As String())
                    Dim price As Double = 9.5
                    Dim count = 3
                    Dim total As Double = price * count
                    total = total * 1.2
                    Console.WriteLine(total)
                End Sub
            End Module
            """
        let result = try extract(code, lines: 5...6, language: "vb").get()
        XCTAssertEqual(result.text, """
            Module Program
                Sub Main(args As String())
                    Dim price As Double = 9.5
                    Dim count = 3
                    Dim total As Double = NewMethod(price, count)
                    Console.WriteLine(total)
                End Sub

                Private Function NewMethod(price As Double, count As Integer) As Double
                    Dim total As Double = price * count
                    total = total * 1.2
                    Return total
                End Function
            End Module
            """)
        XCTAssertEqual((result.text as NSString).substring(with: result.nameRange), "NewMethod")
        XCTAssertTrue((result.text as NSString).substring(to: result.nameRange.location).hasSuffix("Private Function "))

        // `As New Type` gives the type; `Dim a, b As Integer` gives both names the type.
        let objects = "Module M\n    Sub Main()\n        Dim cart As New List(Of String)\n        Dim a, b As Integer\n        cart.Add(\"x\")\n        Console.WriteLine(a + b)\n    End Sub\nEnd Module"
        let typed = try extract(objects, lines: 5...6, language: "vb").get()
        XCTAssertTrue(typed.text.contains("Private Sub NewMethod(cart As List(Of String), a As Integer, b As Integer)"), typed.text)

        // A Sub when nothing is used afterwards.
        let sub = try extract(code, lines: 7...7, language: "vb").get()
        XCTAssertTrue(sub.text.contains("        NewMethod(total)\n"))
        XCTAssertTrue(sub.text.contains("    Private Sub NewMethod(total As Double)\n        Console.WriteLine(total)\n    End Sub"))
    }

    func testCSharpAndFailures() throws {
        let code = """
            class Calculator
            {
                public static int Run(int a, int b)
                {
                    int sum = a + b;
                    Console.WriteLine(sum);
                    return sum;
                }
            }
            """
        let result = try extract(code, lines: 5...5, language: "csharp").get()
        XCTAssertTrue(result.text.contains("        int sum = NewMethod(a, b);"))
        XCTAssertTrue(result.text.contains("    private static int NewMethod(int a, int b)\n    {\n        int sum = a + b;\n        return sum;\n    }"))
        XCTAssertEqual(extract(code, lines: 6...7, language: "csharp"), .failure(.containsReturn))
        XCTAssertEqual(extract("int x = 1;", lines: 1...1, language: "csharp").map(\.text).mapError { $0 }.isSuccess, true)   // top-level statements
        XCTAssertEqual(ExtractMethod.extract("x", selection: NSRange(location: 0, length: 1), languageId: "rust"), .failure(.unsupportedLanguage))
    }

    func testPythonMethod() throws {
        let code = """
            class Cart:
                def total(self, items):
                    subtotal = sum(items)
                    tax = subtotal * 0.2
                    return subtotal + tax
            """
        let result = try extract(code, lines: 4...4, language: "python").get()
        XCTAssertTrue(result.text.contains("        tax = self.new_method(subtotal)\n"))
        XCTAssertTrue(result.text.contains("    def new_method(self, subtotal):\n        tax = subtotal * 0.2\n        return tax"))
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
}

final class SymbolTests: XCTestCase {
    func testVisualBasic() {
        let code = """
            Namespace Shop
                Public Class Product
                    Public Property Name As String
                    Private _price As Decimal
                    Public Shared Count As Integer
                    Public Sub New(name As String)
                        Me.Name = name
                        Dim local As Integer = 1
                    End Sub
                    Public Function Total(quantity As Integer) As Decimal
                        Return _price * quantity
                    End Function
                End Class
                Public Enum Size
                    Small
                    Large = 2
                End Enum
            End Namespace
            Module Helpers
                Sub Greet()
                End Sub
            End Module
            """
        let symbols = SymbolParser.symbols(in: code, languageId: "vb")
        XCTAssertEqual(symbols.map(\.name), ["Product", "Name", "_price", "Count", "Product", "Total", "Size", "Small", "Large", "Helpers", "Greet"])
        let total = symbols.first { $0.name == "Total" }!
        XCTAssertEqual(total.kind, .method)
        XCTAssertEqual(total.type, "Decimal")
        XCTAssertEqual(total.container, "Product")
        XCTAssertEqual(total.namespace, "Shop")
        XCTAssertEqual(total.qualifiedName, "Shop.Product.Total")
        XCTAssertEqual(symbols.first { $0.name == "Count" }?.isShared, true)
        XCTAssertEqual(symbols[4].kind, .constructor)
        XCTAssertEqual(symbols.first { $0.name == "Greet" }?.isShared, true)          // module members
        XCTAssertEqual(symbols.first { $0.name == "Large" }?.kind, .enumMember)
    }

    func testCSharpAndOthers() {
        let cs = """
            namespace Shop;

            public class Cart
            {
                private readonly List<Item> _items = new();
                public int Count { get; set; }
                public Cart() { }
                public decimal Total(decimal tax)
                {
                    var sum = 0m;
                    return sum;
                }
                public override string ToString() => "Cart";
            }
            public enum Color { Red, Green }
            """
        let symbols = SymbolParser.symbols(in: cs, languageId: "csharp")
        XCTAssertEqual(symbols.map(\.name), ["Cart", "_items", "Count", "Cart", "Total", "ToString", "Color"])
        XCTAssertEqual(symbols.first { $0.name == "Total" }?.type, "decimal")
        XCTAssertEqual(symbols.first { $0.name == "Count" }?.kind, .property)
        XCTAssertEqual(symbols.first?.namespace, "Shop")

        let python = "class Dog:\n    legs = 4\n    def __init__(self, name):\n        self.name = name\n    def bark(self) -> str:\n        return 'woof'\n\ndef helper():\n    pass\n"
        XCTAssertEqual(SymbolParser.symbols(in: python, languageId: "python").map { "\($0.kind.rawValue) \($0.name)" },
                       ["class Dog", "field legs", "constructor __init__", "field name", "method bark", "function helper"])

        let swift = "struct Point {\n    var x: Double\n    func length() -> Double {\n        let y = 1\n        return x\n    }\n}\nprotocol Shape {\n    func area() -> Double\n    var name: String { get }\n}\n"
        XCTAssertEqual(SymbolParser.symbols(in: swift, languageId: "swift").map(\.name), ["Point", "x", "length", "Shape", "area", "name"])
    }
}

final class BasicIntelliSenseTests: XCTestCase {
    private let code = """
        Module Program
            Sub Main(args As String())
                Dim names As New List(Of String)
                Dim message = "hi"
                Dim calc As New Calculator()
                Console.
            End Sub
        End Module
        Public Class Calculator
            Public Function Add(a As Integer, b As Integer) As Integer
                Return a + b
            End Function
            Public Shared Function Create() As Calculator
                Return New Calculator()
            End Function
        End Class
        """

    private func complete(after marker: String, replacing: String? = nil) -> [String] {
        var text = code
        if let replacing { text = text.replacingOccurrences(of: "Console.", with: replacing) }
        let offset = (text as NSString).range(of: marker).upperBound
        let symbols = SymbolParser.symbols(in: text, languageId: "vb")
        return BasicIntelliSense.completions(text: text, offset: offset, languageId: "vb", symbols: symbols, snippets: []).items.map(\.label)
    }

    func testMemberLists() {
        let console = complete(after: "Console.")
        XCTAssertTrue(console.contains("WriteLine"))
        XCTAssertTrue(console.contains("ReadLine"))
        XCTAssertFalse(console.contains("Length"))
        XCTAssertTrue(complete(after: "names.", replacing: "names.").contains("Add"))
        XCTAssertTrue(complete(after: "names.", replacing: "names.").contains("Where"))        // LINQ
        XCTAssertTrue(complete(after: "message.", replacing: "message.").contains("ToUpper"))
        let calc = complete(after: "calc.", replacing: "calc.")
        XCTAssertTrue(calc.contains("Add"))
        XCTAssertFalse(calc.contains("Create"))                                                // Shared: not on an instance
        XCTAssertEqual(complete(after: "Calculator.", replacing: "Calculator."), ["Create"])
        XCTAssertTrue(complete(after: "IO.", replacing: "System.IO.").contains("File"))
        XCTAssertTrue(complete(after: "Now.", replacing: "DateTime.Now.").contains("AddDays"))  // chain through a property's type
    }

    func testWordsKeywordsAndHover() {
        let words = complete(after: "Console.", replacing: "Dim x As ")
        XCTAssertTrue(words.contains("Integer"))
        XCTAssertTrue(words.contains("Calculator"))
        let start = complete(after: "Console.", replacing: "")
        XCTAssertTrue(start.contains("Dim"))
        XCTAssertTrue(start.contains("names"))
        let symbols = SymbolParser.symbols(in: code, languageId: "vb")
        let offset = (code as NSString).range(of: "Console").location + 2
        XCTAssertEqual(BasicIntelliSense.hover(at: offset, text: code, languageId: "vb", symbols: symbols), "Class System.Console")
        let add = (code as NSString).range(of: "Add(a").location
        XCTAssertTrue(BasicIntelliSense.hover(at: add, text: code, languageId: "vb", symbols: symbols)?.hasPrefix("Public Function Add") == true)
        let calcUse = (code as NSString).range(of: "New Calculator()").location + 5
        XCTAssertEqual(BasicIntelliSense.definition(at: calcUse, text: code, languageId: "vb", symbols: symbols)?.line, 9)
        XCTAssertEqual(DotNetCatalog.type(named: "String")?.members.first { $0.name == "Split" }?.returnType, "String()")
    }
}

final class SnippetAndThemeTests: XCTestCase {
    func testSnippetLibrary() throws {
        var library = SnippetLibrary()
        XCTAssertEqual(library.snippet(shortcut: "prop", languageId: "csharp")?.title, "Auto-implemented property")
        XCTAssertEqual(library.snippet(shortcut: "foreach", languageId: "vb")?.title, "For Each…Next")   // VB ignores case
        XCTAssertNil(library.snippet(shortcut: "Prop", languageId: "csharp"))
        var mine = CodeSnippet(title: "Log", shortcut: "log", languageId: "vb", body: "Debug.WriteLine($0)")
        library.save(mine)
        mine.body = "Trace.WriteLine($0)"
        library.save(mine)
        XCTAssertEqual(library.snippet(shortcut: "LOG", languageId: "vb")?.body, "Trace.WriteLine($0)")
        let builtIn = library.snippet(shortcut: "cw", languageId: "csharp")!
        library.delete(id: builtIn.id)
        XCTAssertNil(library.snippet(shortcut: "cw", languageId: "csharp"))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cf-snippets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try library.write(to: file)
        var loaded = SnippetLibrary(contentsOf: file)
        XCTAssertEqual(loaded.userSnippets.count, 1)
        XCTAssertNil(loaded.snippet(shortcut: "cw", languageId: "csharp"))
        loaded.restoreBuiltIns()
        XCTAssertNotNil(loaded.snippet(shortcut: "cw", languageId: "csharp"))
        XCTAssertEqual(Set(BuiltInSnippets.all.map(\.id)).count, BuiltInSnippets.all.count)
    }

    func testThemes() {
        XCTAssertEqual(ColorThemes.theme(id: "monokai")?.isDark, true)
        XCTAssertNil(ColorThemes.theme(id: "system"))
        XCTAssertEqual(Set(ColorThemes.all.map(\.id)).count, ColorThemes.all.count)
        XCTAssertEqual(ColorThemes.visualStudioLight.color(for: .keyword), 0x0000FF)
        XCTAssertEqual(ColorThemes.theme(id: "gray")?.isDark, true)
        XCTAssertEqual(ColorThemes.theme(id: "midnight")?.name, "Midnight")
    }
}

final class DatabaseTests: XCTestCase {
    func testSQLite() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("cf-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = try SQLiteDatabase(path: path, create: true)
        let created = try database.execute("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, age INTEGER); INSERT INTO people (name, age) VALUES ('Ada', 36), ('Alan', NULL);")
        XCTAssertEqual(created.changes, 2)
        let result = try database.execute("SELECT name, age FROM people ORDER BY id")
        XCTAssertEqual(result.columns, ["name", "age"])
        XCTAssertEqual(result.rows, [["Ada", "36"], ["Alan", nil]])
        let tables = try database.tables()
        XCTAssertEqual(tables.map(\.name), ["people"])
        XCTAssertEqual(tables[0].columns.map(\.name), ["id", "name", "age"])
        XCTAssertEqual(tables[0].columns[0].isKey, true)
        XCTAssertThrowsError(try database.execute("SELECT * FROM missing"))
        XCTAssertThrowsError(try SQLiteDatabase(path: "/nonexistent/folder/x.db"))
    }

    func testClientOutput() {
        let csv = DatabaseClient.parse("id,name,note\n1,\"Smith, Jo\",\n2,Ann,\"\"\n", kind: .postgres)
        XCTAssertEqual(csv.columns, ["id", "name", "note"])
        XCTAssertEqual(csv.rows, [["1", "Smith, Jo", nil], ["2", "Ann", ""]])
        let tsv = DatabaseClient.parse("id\tname\n1\tNULL\n", kind: .mysql)
        XCTAssertEqual(tsv.rows, [["1", nil]])
        let sqlcmd = DatabaseClient.parse("id\u{1F}name\n--\u{1F}----\n1\u{1F}Bo\n\n(1 rows affected)\n", kind: .sqlserver)
        XCTAssertEqual(sqlcmd.rows, [["1", "Bo"]])
        XCTAssertEqual(DatabaseClient.topRowsQuery(.sqlserver, table: "dbo.Users"), "SELECT TOP 200 * FROM [dbo].[Users]")
        XCTAssertEqual(DatabaseClient.topRowsQuery(.mysql, table: "users", count: 5), "SELECT * FROM `users` LIMIT 5")
        let command = DatabaseClient.command(for: DataConnection(name: "x", kind: .postgres, location: "localhost", port: "5432", database: "shop", user: "me"), sql: "SELECT 1")!
        XCTAssertEqual(command.executable, "psql")
        XCTAssertEqual(command.arguments, ["-X", "--csv", "-v", "ON_ERROR_STOP=1", "-h", "localhost", "-p", "5432", "-U", "me", "-d", "shop", "-c", "SELECT 1"])
    }
}

final class NavigationTests: XCTestCase {
    func testTaskListFindsOnlyComments() {
        let code = "' TODO: check the total\nDim note = \"TODO not this one\"\nDim x = 1 ' HACK works for now\n"
        let tasks = TaskScanner.tasks(in: code, url: URL(fileURLWithPath: "/a.vb"), language: Languages.language(id: "vb")!)
        XCTAssertEqual(tasks.map(\.token), ["TODO", "HACK"])
        XCTAssertEqual(tasks[0].text, "check the total")
        XCTAssertEqual(tasks[1].line, 3)
        XCTAssertEqual(tasks[1].column, 13)
        let block = TaskScanner.tasks(in: "/* FIXME: leak */", url: URL(fileURLWithPath: "/a.c"), language: Languages.language(id: "c")!)
        XCTAssertEqual(block.first?.text, "leak")
    }

    func testBookmarksFollowTheirLines() {
        XCTAssertEqual(BookmarkLines.shift([2, 5, 9], editLine: 3, removed: 0, added: 2), [2, 7, 11])
        XCTAssertEqual(BookmarkLines.shift([2, 5, 9], editLine: 3, removed: 3, added: 0), [2, 3, 6])
        XCTAssertEqual(BookmarkLines.shift([4], editLine: 4, removed: 0, added: 1), [4])
    }

    func testBookmarkOrderWraps() throws {
        let marks = ["/a": Set([3, 9]), "/b": Set([1])]
        XCTAssertEqual(try XCTUnwrap(BookmarkLines.next(after: ("/a", 3), in: marks, backward: false)).line, 9)
        XCTAssertEqual(try XCTUnwrap(BookmarkLines.next(after: ("/a", 9), in: marks, backward: false)).path, "/b")
        XCTAssertEqual(try XCTUnwrap(BookmarkLines.next(after: ("/b", 1), in: marks, backward: false)).line, 3)   // wraps around
        XCTAssertEqual(try XCTUnwrap(BookmarkLines.next(after: ("/a", 3), in: marks, backward: true)).path, "/b")
        XCTAssertNil(BookmarkLines.next(after: ("/a", 1), in: [:], backward: false))
    }

    func testNavigationHistoryWorksLikeABrowser() {
        var history = NavigationHistory<String>()
        history.record("a")
        history.record("b")
        XCTAssertEqual(history.goBack(from: "c"), "b")
        XCTAssertEqual(history.goBack(from: "b"), "a")
        XCTAssertNil(history.goBack(from: "a"))
        XCTAssertEqual(history.goForward(from: "a"), "b")
        XCTAssertEqual(history.goForward(from: "b"), "c")
        XCTAssertNil(history.goForward(from: "c"))
        _ = history.goBack(from: "c")
        history.record("z")     // a new jump clears Forward
        XCTAssertNil(history.goForward(from: "z"))
    }
}

final class OutputDecodingTests: XCTestCase {
    func testClassifiesLinesByContent() {
        for line in ["main.c:3:1: error: expected ';'", "Program.vb(6,27): error BC30451: 'totl' is not declared.", "error: linking failed", "error[E0308]: mismatched types",
                     "Traceback (most recent call last):", "ValueError: bad value", "Swift/Array.swift:175: Fatal error: Index out of range", "panic: boom", "zsh: command not found: go", "Build FAILED."] {
            XCTAssertEqual(OutputClassifier.kind(of: line), .error, line)
        }
        for line in ["main.c:3:1: warning: unused variable", "warning: unused import", "npm WARN deprecated x"] {
            XCTAssertEqual(OutputClassifier.kind(of: line), .warning, line)
        }
        for line in ["Building for debugging...", "Build complete! (0.5s)", "[3/4] Compiling main.swift", "No errors found", "Hello, error handling", "0 Error(s)", "Build succeeded."] {
            XCTAssertEqual(OutputClassifier.kind(of: line), .normal, line)
        }
    }

    func testDecodesLinesPromptsAndSplitCharacters() {
        var decoder = OutputDecoder()
        XCTAssertEqual(decoder.append(Array("one\nerror: two\n".utf8)), [.init(text: "one\n", kind: .normal), .init(text: "error: two\n", kind: .error)])
        // A prompt with no line break shows right away.
        XCTAssertEqual(decoder.append(Array("Name? ".utf8)), [.init(text: "Name? ", kind: .normal)])
        XCTAssertEqual(decoder.append(Array("\n".utf8)), [.init(text: "\n", kind: .normal)])
        // An Arabic letter split between two reads stays whole.
        let letter = Array("م".utf8)
        XCTAssertEqual(decoder.append([letter[0]]), [])
        XCTAssertEqual(decoder.append([letter[1]]), [.init(text: "م", kind: .normal)])
        XCTAssertEqual(decoder.append(Array("\r\nnext\rover\n".utf8)), [.init(text: "\n", kind: .normal), .init(text: "over\n", kind: .normal)])
        XCTAssertEqual(decoder.append(Array("end".utf8)), [.init(text: "end", kind: .normal)])
        XCTAssertEqual(decoder.finish(), [])
    }
}

final class DiagnosticMergeTests: XCTestCase {
    func testListsTheSameProblemOnce() {
        let folder = URL(fileURLWithPath: "/project")
        let fromBuild = Diagnostic(severity: .error, message: "expected ';' after expression", file: "main.c", line: 4, column: 9)
        let fromServer = Diagnostic(severity: .error, message: "Expected ';' after expression (fix available)", file: "/project/main.c", line: 4, column: 9, endLine: 4, endColumn: 10)
        let other = Diagnostic(severity: .warning, message: "unused variable 'x'", file: "main.c", line: 2)
        let merged = DiagnosticMerge.merged(run: [fromBuild, other], live: [fromServer], folder: folder)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.filter { $0.severity == .error }, [fromBuild])
        // clangd reports a missing ';' on the next line.
        let nextLine = Diagnostic(severity: .error, message: "Expected ';' after expression (fix available)", file: "/project/main.c", line: 5, column: 1)
        XCTAssertEqual(DiagnosticMerge.merged(run: [fromBuild], live: [nextLine], folder: folder), [fromBuild])
        // Two languages-server problems on neighboring lines are both real.
        let neighbor = Diagnostic(severity: .error, message: "Unknown type name 'foo'", file: "/project/main.c", line: 6)
        let neighbor2 = Diagnostic(severity: .error, message: "Unknown type name 'foo'", file: "/project/main.c", line: 7)
        XCTAssertEqual(DiagnosticMerge.merged(run: [], live: [neighbor, neighbor2], folder: folder).count, 2)
        // Different lines are different problems.
        let elsewhere = Diagnostic(severity: .error, message: "expected ';' after expression", file: "main.c", line: 9)
        XCTAssertEqual(DiagnosticMerge.merged(run: [fromBuild, elsewhere], live: [], folder: folder).count, 2)
    }
}

final class ToolRequirementTests: XCTestCase {
    func testFindsTheProgramACommandNeeds() {
        XCTAssertEqual(ToolRequirement.tool(ofCommand: "npx --yes tsx a.ts"), "npx")
        XCTAssertEqual(ToolRequirement.tool(ofCommand: "{ dotnet new list maui | grep x; } && dotnet new maui"), "dotnet")
        let templates = Dictionary(uniqueKeysWithValues: ProjectTemplates.all.map { ($0.id, $0) })
        XCTAssertEqual(ToolRequirement.tool(for: templates["java"]!), "java")
        XCTAssertEqual(ToolRequirement.tool(for: templates["go"]!).map { ["go", "go run ."].contains($0) }, true)
        XCTAssertEqual(ToolRequirement.tool(for: templates["vb-console"]!), "dotnet")
        XCTAssertTrue(ToolRequirement.installHint(for: "java").contains("brew install"))
        XCTAssertTrue(ToolRequirement.installHint(for: "cargo").contains("rust"))
    }

    func testToolboxAndSnippetsCoverCompiledLanguages() {
        for language in ["c", "cpp", "java", "go", "rust"] {
            XCTAssertFalse(ToolboxCatalog.groups(forLanguage: language).isEmpty, language)
            XCTAssertFalse(SnippetLibrary().snippets(forLanguage: language).isEmpty, language)
        }
        XCTAssertEqual(ToolboxCatalog.groups(forLanguage: "typescript").first?.name, "TypeScript Snippets")
        XCTAssertEqual(Set(BuiltInSnippets.all.map(\.id)).count, BuiltInSnippets.all.count)
    }
}

final class OutputProgressTests: XCTestCase {
    private func decode(_ text: String) -> String {
        var decoder = OutputDecoder()
        let pieces = decoder.append(Array(text.utf8)) + decoder.finish()
        return pieces.map(\.text).joined()
    }

    func testRewrittenLinesKeepOnlyTheLastVersion() {
        XCTAssertEqual(decode("Counting 1%\rCounting 50%\rCounting 100%, done.\r\nNext\r\n"), "Counting 100%, done.\nNext\n")
    }

    func testSwiftPMStepCounterIsHiddenButProgramOutputIsNot() {
        XCTAssertEqual(decode("[1\u{2009}/\u{2009}3]\r\n[2\u{2009}/\u{2009}3] App-product\r\nBuild complete!\r\n"), "Build complete!\n")
        XCTAssertEqual(decode("[1/3] mine\n"), "[1/3] mine\n")
    }
}
