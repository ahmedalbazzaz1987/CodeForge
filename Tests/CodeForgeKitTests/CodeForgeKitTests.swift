import XCTest
@testable import CodeForgeKit

final class CodeForgeKitTests: XCTestCase {
    func testLanguageDetection() {
        XCTAssertEqual(Languages.forFile(named: "main.swift").id, "swift")
        XCTAssertEqual(Languages.forFile(named: "App.TSX").id, "typescript")
        XCTAssertEqual(Languages.forFile(named: "Makefile").id, "makefile")
        XCTAssertEqual(Languages.forFile(named: "deploy", firstLine: "#!/usr/bin/env python3").id, "python")
        XCTAssertEqual(Languages.forFile(named: "notes").id, "text")
    }

    func testEveryLanguageCompiles() {
        // An invalid combined pattern would silently disable highlighting, so check each one builds.
        for language in Languages.all {
            XCTAssertNotNil(Tokenizer(language: language).main, "pattern for \(language.id) did not compile")
        }
    }

    func testCommentInsideStringStaysString() {
        let swift = Tokenizer(language: Languages.language(id: "swift")!)
        let tokens = swift.tokens(in: #"let url = "http://x" // note"#)
        XCTAssertEqual(tokens.first { $0.kind == .keyword }?.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(tokens.first { $0.kind == .string }?.range, NSRange(location: 10, length: 10))
        XCTAssertEqual(tokens.first { $0.kind == .comment }?.range, NSRange(location: 21, length: 7))
    }

    func testFunctionsTypesAndNumbers() {
        let python = Tokenizer(language: Languages.language(id: "python")!)
        let tokens = python.tokens(in: "def greet(Name, n=0x1F):\n    print(n)")
        XCTAssertTrue(tokens.contains(Token(range: NSRange(location: 4, length: 5), kind: .function)))
        XCTAssertTrue(tokens.contains(Token(range: NSRange(location: 10, length: 4), kind: .type)))
        XCTAssertTrue(tokens.contains(Token(range: NSRange(location: 18, length: 4), kind: .number)))
    }

    func testCommandTemplateQuotesPaths() {
        let file = URL(fileURLWithPath: "/tmp/it's here/hello.c")
        let command = CommandTemplate.expand("clang {file} -o {out} && {out}", file: file, outputDirectory: URL(fileURLWithPath: "/tmp/out"))
        XCTAssertEqual(command, #"clang '/tmp/it'\''s here/hello.c' -o '/tmp/out/hello' && '/tmp/out/hello'"#)
    }

    func testVersionOrdering() {
        XCTAssertLessThan(Version("0.9.2")!, Version("v0.10.0")!)
        XCTAssertEqual(Version("1.2")!, Version("1.2.0")!)
        XCTAssertGreaterThan(Version("2.0.0-beta")!, Version("1.9.9")!)
        XCTAssertNil(Version("latest"))
    }

    func testFuzzyMatchPrefersFileNames() {
        XCTAssertNil(FuzzyMatch.score("xyz", "Sources/main.swift"))
        let name = FuzzyMatch.score("main", "Sources/main.swift")!
        let scattered = FuzzyMatch.score("main", "Sources/MyApp/Info.plist.n")
        XCTAssertGreaterThan(name, scattered ?? Int.min)
    }
}

final class DiagnosticsAndTemplatesTests: XCTestCase {
    func testCompilerErrors() {
        let output = """
            main.c:5:9: error: use of undeclared identifier 'x'
            /tmp/a.swift:3:1: warning: variable 'y' was never used
            main.c:5:9: note: previous definition is here
            ./main.go:7:2: undefined: fmt.Printn
            Total: 55
            """
        let diagnostics = DiagnosticParser.parse(output)
        XCTAssertEqual(diagnostics, [
            Diagnostic(severity: .error, message: "use of undeclared identifier 'x'", file: "main.c", line: 5, column: 9),
            Diagnostic(severity: .warning, message: "variable 'y' was never used", file: "/tmp/a.swift", line: 3, column: 1),
            Diagnostic(severity: .error, message: "undefined: fmt.Printn", file: "./main.go", line: 7, column: 2),
        ])
    }

    func testPythonTraceback() {
        let output = """
            Traceback (most recent call last):
              File "/p/main.py", line 9, in <module>
                main()
              File "/p/main.py", line 4, in main
                print(nmae)
            NameError: name 'nmae' is not defined
            """
        XCTAssertEqual(DiagnosticParser.parse(output),
                       [Diagnostic(severity: .error, message: "NameError: name 'nmae' is not defined", file: "/p/main.py", line: 4)])
    }

    func testRustNodeAndTypeScript() {
        let rust = "error[E0425]: cannot find value `x` in this scope\n --> src/main.rs:2:20\n"
        XCTAssertEqual(DiagnosticParser.parse(rust).first?.file, "src/main.rs")
        let node = "/p/app.js:2\nconsole.log(y)\n        ^\n\nReferenceError: y is not defined\n    at Object.<anonymous> (/p/app.js:2:13)\n"
        XCTAssertEqual(DiagnosticParser.parse(node), [Diagnostic(severity: .error, message: "ReferenceError: y is not defined", file: "/p/app.js", line: 2)])
        let ts = "index.ts(3,7): error TS2322: Type 'string' is not assignable to type 'number'.\n"
        XCTAssertEqual(DiagnosticParser.parse(ts).first?.column, 7)
    }

    func testTemplatesCreateFiles() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        for template in ProjectTemplates.all {
            let folder = try ProjectTemplates.create(template, named: "My App \(template.id)", in: parent)
            let main = folder.appendingPathComponent(ProjectTemplates.mainFile(of: template, named: "My App \(template.id)"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: main.path), template.id)
            XCTAssertFalse(try String(contentsOf: main, encoding: .utf8).contains("{{"), template.id)
        }
        XCTAssertEqual(ProjectTemplates.identifier(for: "2nd try!"), "App2ndtry")
    }
}
