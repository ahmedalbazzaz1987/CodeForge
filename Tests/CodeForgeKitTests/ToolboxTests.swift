import XCTest
@testable import CodeForgeKit

final class ToolboxTests: XCTestCase {
    func testSnippetExpansion() {
        let item = ToolboxItem("Panel", "x", "<div>\n    $0\n</div>")
        let (text, cursor) = item.expanded(indent: "  ")
        XCTAssertEqual(text, "<div>\n      \n  </div>")
        XCTAssertEqual(cursor, 12)
        XCTAssertEqual(ToolboxItem("Rule", "x", "<hr>").expanded(indent: "").cursor, 4)
    }

    func testCatalogPerLanguage() {
        XCTAssertEqual(ToolboxCatalog.groups(forLanguage: "razor").map(\.name), ["ASP.NET Tag Helpers", "HTML", "Bootstrap"])
        XCTAssertEqual(ToolboxCatalog.groups(forLanguage: "vb").first?.name, "VB.NET Snippets")
        XCTAssertTrue(ToolboxCatalog.groups(forLanguage: "markdown").isEmpty)
        for language in ["html", "razor", "csharp", "vb", "swift", "python", "javascript", "css"] {
            for group in ToolboxCatalog.groups(forLanguage: language) {
                for item in group.items { XCTAssertTrue(item.snippet.contains("$0") || !item.snippet.isEmpty, item.name) }
            }
        }
    }

    func testTagAtCursorAndRewrite() {
        let html = #"<p>Hi</p>\n<input type="text" name='user' required />\n"#.replacingOccurrences(of: "\\n", with: "\n")
        let inside = (html as NSString).range(of: "name").location
        var tag = HTMLTag.at(inside, in: html)!
        XCTAssertEqual(tag.name, "input")
        XCTAssertTrue(tag.selfClosing)
        XCTAssertEqual(tag.attributes.map(\.name), ["type", "name", "required"])
        XCTAssertEqual(tag.attributes[1].value, "user")
        XCTAssertNil(tag.attributes[2].value)
        tag.attributes[0].value = "email"
        XCTAssertEqual(tag.source, #"<input type="email" name="user" required />"#)
        XCTAssertEqual(HTMLTag.at(5, in: html)?.name, "p")   // in the text after <p>
        XCTAssertNil(HTMLTag.at(3, in: "plain text"))
    }
}
