import XCTest
@testable import CodeForgeKit

final class ParameterInfoTests: XCTestCase {
    private let csharp = Languages.language(id: "csharp")!
    private let python = Languages.language(id: "python")!
    private let vb = Languages.language(id: "vb")!

    private func call(_ text: String, _ language: Language) -> CallSite? {
        ParameterInfo.call(in: text, at: (text as NSString).length, language: language)
    }

    func testFindsTheCallAndArgument() {
        let site = call("Console.WriteLine(a, ", csharp)
        XCTAssertEqual(site?.name, "WriteLine")
        XCTAssertEqual(site?.qualifier, ["Console"])
        XCTAssertEqual(site?.argument, 1)
        XCTAssertEqual(site?.openParen, 17)
        XCTAssertEqual(call("Math.Max(Math.Abs(x), ", csharp)?.name, "Max")
        XCTAssertEqual(call("Math.Max(Math.Abs(", csharp)?.name, "Abs")
        XCTAssertEqual(call("var r = new Random(", csharp)?.isConstructor, true)
    }

    func testIgnoresStringsCommentsAndClosedCalls() {
        XCTAssertNil(ParameterInfo.call(in: "Print(\"a, (b", at: 12, language: csharp))
        XCTAssertEqual(call("Print(\"a, b\", ", csharp)?.argument, 1)
        XCTAssertNil(ParameterInfo.call(in: "Print(a) // (", at: 13, language: csharp))
        XCTAssertNil(call("Print(a); x = 1", csharp))
        XCTAssertNil(call("if (x > ", csharp))
        XCTAssertNil(call("def greet(name", python))
        XCTAssertEqual(call("MsgBox(\"say \"\"hi\"\", ok\", ", vb)?.argument, 1)
    }

    func testSplitsParameters() {
        func parts(_ label: String) -> [String] { ParameterInfo.parameterRanges(label).map { (label as NSString).substring(with: $0) } }
        XCTAssertEqual(parts("Substring(startIndex As Integer, length As Integer) As String"), ["startIndex As Integer", "length As Integer"])
        XCTAssertEqual(parts("void Add(Dictionary<string, int> map, int count)"), ["Dictionary<string, int> map", "int count"])
        XCTAssertEqual(parts("Now()"), [])
        XCTAssertEqual(parts("Function Map(Of T)(items As T(), f As Func(Of T, T)) As T()"), ["items As T()", "f As Func(Of T, T)"])
    }

    func testBasicSignatures() {
        let text = "Dim r As New Random()\nr.Next("
        let site = call(text, vb)!
        let signatures = ParameterInfo.basic(text: text, call: site, language: vb, symbols: [])
        XCTAssertEqual(signatures.count, 3)
        XCTAssertTrue(signatures.contains { $0.label == "Next(minValue As Integer, maxValue As Integer) As Integer" })

        let code = "Module M\n    Function Add(a As Integer, b As Integer) As Integer\n        Return a + b\n    End Function\nEnd Module\nAdd(1, "
        let symbols = SymbolParser.symbols(in: code, languageId: "vb")
        let add = call(code, vb)!
        let found = ParameterInfo.basic(text: code, call: add, language: vb, symbols: symbols)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(ParameterInfo.activeParameter(found[0], argument: add.argument), 1)

        let print = ParameterInfo.basic(text: "print(", call: call("print(", python)!, language: python, symbols: [])
        XCTAssertEqual(print.count, 1)
        XCTAssertTrue(print[0].documentation.contains("output"))
    }

    func testActiveParameterAndOverloads() {
        XCTAssertEqual(ParameterInfo.activeParameter(SignatureInfo(label: "Max(a, b)"), argument: 2), -1)
        XCTAssertEqual(ParameterInfo.activeParameter(SignatureInfo(label: "Printf(format string, a ...any)"), argument: 5), 1)
        XCTAssertEqual(ParameterInfo.bestOverload([SignatureInfo(label: "Next()"), SignatureInfo(label: "Next(max)")], argument: 0), 1)
    }

    func testReadsSignatureHelp() throws {
        let json = """
            { "signatures": [
                { "label": "Println(a ...any) (n int, err error)", "documentation": "Println formats.", "parameters": [ { "label": "a ...any" } ] },
                { "label": "f(x int, y int)", "parameters": [ { "label": [2, 7] }, { "label": [9, 14], "documentation": { "kind": "markdown", "value": "the **y**" } } ] }
              ], "activeSignature": 1, "activeParameter": 1 }
            """
        let result = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let help = ParameterInfo.fromLSP(result)
        XCTAssertEqual(help.signatures.count, 2)
        XCTAssertEqual(help.signatures[0].parameters[0], NSRange(location: 8, length: 8))
        XCTAssertEqual(help.signatures[0].documentation, "Println formats.")
        XCTAssertEqual(help.signatures[1].parameters[1], NSRange(location: 9, length: 5))
        XCTAssertEqual(help.signatures[1].parameterDocs[1], "the y")
        XCTAssertEqual(help.active, 1)
        XCTAssertEqual(help.parameter, 1)
        XCTAssertTrue(ParameterInfo.fromLSP(nil).signatures.isEmpty)
    }
}

final class SnippetTemplateTests: XCTestCase {
    func testExpandsFieldsAndIndents() {
        let (text, fields) = SnippetTemplate.expand("for (int ${1:i} = 0; $1 < ${2:length}; $1++)\n{\n    $0\n}", indent: "  ")
        XCTAssertEqual(text, "for (int i = 0; i < length; i++)\n  {\n      \n  }")
        XCTAssertEqual(fields, [SnippetField(index: 1, location: 9, length: 1), SnippetField(index: 1, location: 16, length: 1),
                                SnippetField(index: 2, location: 20, length: 6), SnippetField(index: 1, location: 28, length: 1),
                                SnippetField(index: 0, location: 43, length: 0)])
    }

    func testChoicesNestingAndEscapes() {
        XCTAssertEqual(SnippetTemplate.plainText("${1|public,private|} void ${2:Run(${3:a})}"), "public void Run(a)")
        XCTAssertEqual(SnippetTemplate.plainText("cost: \\$5 \\}"), "cost: $5 }")
        XCTAssertEqual(SnippetTemplate.plainText("{ ${1:get; set;} }"), "{ get; set; }")
    }

    func testOlderSnippetsAndDollarSignsStayAsTheyWere() {
        let (text, fields) = SnippetTemplate.expand("if ($0condition) {\n}")
        XCTAssertEqual(text, "if (condition) {\n}")
        XCTAssertEqual(fields, [SnippetField(index: 0, location: 4, length: 0)])
        XCTAssertFalse(SnippetTemplate.hasFields("if ($0condition) {\n}"))
        XCTAssertTrue(SnippetTemplate.hasFields("print(${1:x})"))
        XCTAssertEqual(SnippetTemplate.plainText("echo $name; `${total}`"), "echo $name; `${total}`")
        XCTAssertEqual(SnippetTemplate.plainText("$"), "$")
    }

    func testBuiltInSnippetsAllParse() {
        for snippet in BuiltInSnippets.all {
            let (text, fields) = SnippetTemplate.expand(snippet.body)
            XCTAssertFalse(text.replacingOccurrences(of: "`${", with: "").contains("${"), snippet.id)
            for field in fields { XCTAssertLessThanOrEqual(NSMaxRange(field.range), (text as NSString).length, snippet.id) }
        }
    }

    func testSessionTabsAndMirrors() {
        // "for (int i = 0; i < length; i++)" inserted at 10.
        let (text, fields) = SnippetTemplate.expand("for (int ${1:i} = 0; $1 < ${2:length}; $1++) {$0}")
        var session = SnippetSession(fields: fields, base: 10)!
        XCTAssertEqual(session.current, NSRange(location: 19, length: 1))
        // Typing "row" over the "i": the field grows, the fields after it move, and the copies are brought in line.
        let document = NSMutableString(string: String(repeating: " ", count: 10) + text)
        document.replaceCharacters(in: NSRange(location: 19, length: 1), with: "row")
        XCTAssertTrue(session.edit(NSRange(location: 19, length: 1), replacementLength: 3))
        for (range, value) in session.mirrorEdits(in: document) {
            document.replaceCharacters(in: range, with: value)
            XCTAssertTrue(session.edit(range, replacementLength: (value as NSString).length))
        }
        XCTAssertEqual(document as String, String(repeating: " ", count: 10) + "for (int row = 0; row < length; row++) {}")
        XCTAssertTrue(session.next())
        XCTAssertEqual(document.substring(with: session.current), "length")
        XCTAssertTrue(session.next())
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.current.location, document.length - 1)
        XCTAssertFalse(session.next())
        // An edit across a field's edge ends the session.
        XCTAssertFalse(session.edit(NSRange(location: 15, length: 6), replacementLength: 0))
        XCTAssertNil(SnippetSession(fields: SnippetTemplate.expand("if ($0x)").fields, base: 0))
    }

    func testEmptyFieldsGrowWhenTypedInto() {
        let (_, fields) = SnippetTemplate.expand("def ${1:name}($2):\n    ${3:pass}$0")
        var session = SnippetSession(fields: fields, base: 0)!
        XCTAssertTrue(session.next())
        XCTAssertEqual(session.current, NSRange(location: 9, length: 0))
        XCTAssertTrue(session.edit(NSRange(location: 9, length: 0), replacementLength: 4))   // "self"
        XCTAssertEqual(session.current, NSRange(location: 9, length: 4))
        XCTAssertTrue(session.next())
        XCTAssertEqual(session.current, NSRange(location: 20, length: 4))
    }
}

final class CompletionRankingTests: XCTestCase {
    func testKindsOfMatchInOrder() throws {
        let names = ["StringBuilder", "string", "String", "IsNullOrEmpty", "ToString", "Substring"]
        func ranked(_ query: String) -> [String] {
            names.compactMap { name in CompletionMatch.score(query, name).map { (name, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        }
        XCTAssertEqual(ranked("String").prefix(3), ["String", "string", "StringBuilder"])
        XCTAssertEqual(ranked("sb").first, "StringBuilder")
        XCTAssertEqual(ranked("strb").first, "StringBuilder")
        XCTAssertEqual(ranked("inoe").first, "IsNullOrEmpty")
        XCTAssertNil(CompletionMatch.score("xyz", "String"))
        XCTAssertTrue(CompletionMatch.matchesWordStarts("gv", "get_value"))
        XCTAssertTrue(CompletionMatch.matchesWordStarts("HTTPS", "HTTPServer"))
        XCTAssertFalse(CompletionMatch.matchesWordStarts("bs", "StringBuilder"))
        XCTAssertEqual(CompletionMatch.words("HTTPServer"), ["HTTP", "Server"])
    }

    func testRecentNamesRankHigher() {
        let history = CompletionHistory()
        XCTAssertEqual(history.recency(of: "WriteLine", languageId: "csharp"), 0)
        history.used("WriteLine", languageId: "csharp")
        history.used("Write", languageId: "csharp")
        XCTAssertGreaterThan(history.recency(of: "Write", languageId: "csharp"), history.recency(of: "WriteLine", languageId: "csharp"))
        XCTAssertEqual(history.recency(of: "Write", languageId: "python"), 0)
    }
}

final class ExplanationTests: XCTestCase {
    func testExplainsCommonErrors() {
        XCTAssertTrue(ErrorExplanations.explain("; expected", code: "CS1002", languageId: "csharp")?.contains("semicolon") == true)
        XCTAssertTrue(ErrorExplanations.explain("BC30451: 'x' is not declared.", languageId: "vb")?.contains("Dim") == true)
        XCTAssertTrue(ErrorExplanations.explain("IndentationError: expected an indented block", languageId: "python")?.contains("indented") == true)
        XCTAssertTrue(ErrorExplanations.explain("use of undeclared identifier 'printf'", languageId: "cpp")?.contains("#include") == true)
        XCTAssertTrue(ErrorExplanations.explain("ReferenceError: x is not defined", languageId: "javascript")?.contains("let or const") == true)
        XCTAssertTrue(ErrorExplanations.explain("cannot find 'greet' in scope", languageId: "swift")?.contains("declare") == true)
        XCTAssertFalse(ErrorExplanations.explain("x is not defined", languageId: "javascript")?.contains("Python") ?? false)
        XCTAssertNil(ErrorExplanations.explain("something unusual happened", languageId: "csharp"))
        XCTAssertNotNil(ErrorExplanations.explain("error CS0103: The name 'x' does not exist in the current context"))
    }

    func testExplainsKeywords() {
        XCTAssertTrue(KeywordGuide.explain("void", languageId: "csharp")?.contains("no value back") == true)
        XCTAssertTrue(KeywordGuide.explain("let", languageId: "swift")?.contains("constant") == true)
        XCTAssertTrue(KeywordGuide.explain("let", languageId: "javascript")?.contains("can change") == true)
        XCTAssertTrue(KeywordGuide.explain("dim", languageId: "vb")?.contains("Dim") == true)
        XCTAssertTrue(KeywordGuide.explain("padding", languageId: "css")?.contains("inside") == true)
        XCTAssertNil(KeywordGuide.explain("padding", languageId: "csharp"))
    }
}
