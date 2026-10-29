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
