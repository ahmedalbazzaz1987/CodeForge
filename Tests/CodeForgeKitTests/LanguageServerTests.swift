import XCTest
@testable import CodeForgeKit

final class LanguageServerTests: XCTestCase {
    func testFramingAcrossChunks() {
        var buffer = LSPMessageBuffer()
        let one = LSPMessageBuffer.frame(Data(#"{"id":1}"#.utf8))
        let two = LSPMessageBuffer.frame(Data(#"{"method":"x","params":{"é":1}}"#.utf8))
        let stream = one + two
        XCTAssertEqual(buffer.append(stream.prefix(5)), [])
        let messages = buffer.append(stream.dropFirst(5))
        XCTAssertEqual(messages.map { String(decoding: $0, as: UTF8.self) }, [#"{"id":1}"#, #"{"method":"x","params":{"é":1}}"#])
    }

    func testTextLines() {
        let lines = TextLines("ab\ncdé\n\nx")
        XCTAssertTrue(lines.position(of: 0) == (0, 0))
        XCTAssertTrue(lines.position(of: 4) == (1, 1))
        XCTAssertTrue(lines.position(of: 7) == (2, 0))
        XCTAssertTrue(lines.position(of: 8) == (3, 0))
        XCTAssertEqual(lines.offset(line: 1, character: 2), 5)
        XCTAssertEqual(lines.offset(line: 1, character: 99), 6)   // clamped to the line's end
        XCTAssertEqual(lines.offset(line: 9, character: 0), 9)
    }

    func testSpecsAndHover() {
        XCTAssertEqual(LanguageServerSpecs.spec(forLanguage: "cpp")?.id, "clangd")
        XCTAssertEqual(LanguageServerSpecs.languageId(forLanguage: "typescript", fileExtension: "tsx"), "typescriptreact")
        XCTAssertNil(LanguageServerSpecs.spec(forLanguage: "markdown"))
        XCTAssertEqual(HoverText.plain("```swift\nfunc f() -> Int\n```\n\n**Returns** the `value`."), "func f() -> Int\n\nReturns the value.")
    }
}
