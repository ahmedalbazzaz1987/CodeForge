import Foundation

/// Something you can drag or double-click from the Toolbox into the editor.
public struct ToolboxItem: Sendable, Equatable {
    public let name: String
    /// SF Symbol shown next to the name.
    public let symbol: String
    /// The text inserted. `$0` marks where the cursor goes; `\n` lines are indented to match the insertion point.
    public let snippet: String

    public init(_ name: String, _ symbol: String, _ snippet: String) {
        self.name = name
        self.symbol = symbol
        self.snippet = snippet
    }

    /// The snippet as it is inserted at a line with `indent`, and where the cursor ends up (UTF-16 offset in it).
    public func expanded(indent: String) -> (text: String, cursor: Int) {
        let indented = snippet.replacingOccurrences(of: "\n", with: "\n" + indent)
        guard let marker = indented.range(of: "$0") else { return (indented, (indented as NSString).length) }
        let cursor = (String(indented[..<marker.lowerBound]) as NSString).length
        return (indented.replacingCharacters(in: marker, with: ""), cursor)
    }
}

public struct ToolboxGroup: Sendable {
    public let name: String
    public let items: [ToolboxItem]

    public init(name: String, items: [ToolboxItem]) {
        self.name = name
        self.items = items
    }
}

/// The Toolbox contents for each kind of file, like Visual Studio's Toolbox tabs.
public enum ToolboxCatalog {
    public static func groups(forLanguage id: String) -> [ToolboxGroup] {
        switch id {
        case "html": [html, bootstrap]
        case "razor": [tagHelpers, html, bootstrap]
        case "csharp": [csharp]
        case "vb": [vb]
        case "swift": [swiftUI, swift]
        case "python": [python]
        case "javascript", "typescript": [javascript]
        case "css": [css]
        default: []
        }
    }

    static let html = ToolboxGroup(name: "HTML", items: [
        ToolboxItem("Button", "rectangle.and.hand.point.up.left", #"<button type="button">$0Button</button>"#),
        ToolboxItem("Text Box", "character.cursor.ibeam", #"<input type="text" name="$0" placeholder="">"#),
        ToolboxItem("Password", "key", #"<input type="password" name="$0">"#),
        ToolboxItem("Check Box", "checkmark.square", "<label><input type=\"checkbox\" name=\"$0\"> Check box</label>"),
        ToolboxItem("Radio Button", "largecircle.fill.circle", "<label><input type=\"radio\" name=\"$0\" value=\"\"> Option</label>"),
        ToolboxItem("Drop-Down List", "chevron.down.square", "<select name=\"$0\">\n    <option>Item 1</option>\n    <option>Item 2</option>\n</select>"),
        ToolboxItem("List Box", "list.bullet.rectangle", "<select name=\"$0\" size=\"4\" multiple>\n    <option>Item 1</option>\n    <option>Item 2</option>\n</select>"),
        ToolboxItem("Text Area", "text.alignleft", #"<textarea name="$0" rows="4" cols="40"></textarea>"#),
        ToolboxItem("Label", "textformat", #"<label for="">$0Label</label>"#),
        ToolboxItem("Hyperlink", "link", #"<a href="$0">Link</a>"#),
        ToolboxItem("Image", "photo", #"<img src="$0" alt="">"#),
        ToolboxItem("Table", "tablecells", "<table>\n    <tr>\n        <th>$0Header</th>\n        <th>Header</th>\n    </tr>\n    <tr>\n        <td>Cell</td>\n        <td>Cell</td>\n    </tr>\n</table>"),
        ToolboxItem("Panel (div)", "square.dashed", "<div>\n    $0\n</div>"),
        ToolboxItem("Form", "doc.plaintext", "<form method=\"post\" action=\"\">\n    $0\n    <button type=\"submit\">Submit</button>\n</form>"),
        ToolboxItem("Heading", "textformat.size.larger", "<h1>$0Heading</h1>"),
        ToolboxItem("Paragraph", "paragraphsign", "<p>$0</p>"),
        ToolboxItem("List", "list.bullet", "<ul>\n    <li>$0Item</li>\n    <li>Item</li>\n</ul>"),
        ToolboxItem("Horizontal Rule", "minus", "<hr>"),
        ToolboxItem("Video", "film", #"<video src="$0" controls></video>"#),
        ToolboxItem("Frame (iframe)", "macwindow", #"<iframe src="$0" width="600" height="400"></iframe>"#),
    ])

    static let bootstrap = ToolboxGroup(name: "Bootstrap", items: [
        ToolboxItem("Primary Button", "rectangle.fill", #"<button type="button" class="btn btn-primary">$0Button</button>"#),
        ToolboxItem("Alert", "exclamationmark.bubble", "<div class=\"alert alert-info\" role=\"alert\">\n    $0Message\n</div>"),
        ToolboxItem("Card", "rectangle.portrait", "<div class=\"card\" style=\"width: 18rem;\">\n    <div class=\"card-body\">\n        <h5 class=\"card-title\">$0Title</h5>\n        <p class=\"card-text\">Text</p>\n    </div>\n</div>"),
        ToolboxItem("Grid Row", "square.grid.3x1.below.line.grid.1x2", "<div class=\"row\">\n    <div class=\"col\">$0</div>\n    <div class=\"col\"></div>\n</div>"),
        ToolboxItem("Form Field", "rectangle.and.pencil.and.ellipsis", "<div class=\"mb-3\">\n    <label class=\"form-label\">$0Label</label>\n    <input type=\"text\" class=\"form-control\">\n</div>"),
        ToolboxItem("Navbar", "menubar.rectangle", "<nav class=\"navbar navbar-expand-lg bg-body-tertiary\">\n    <div class=\"container-fluid\">\n        <a class=\"navbar-brand\" href=\"#\">$0Brand</a>\n    </div>\n</nav>"),
    ])

    static let tagHelpers = ToolboxGroup(name: "ASP.NET Tag Helpers", items: [
        ToolboxItem("Form", "doc.plaintext", "<form method=\"post\" asp-page=\"$0\">\n    <button type=\"submit\">Submit</button>\n</form>"),
        ToolboxItem("Input", "character.cursor.ibeam", #"<input asp-for="$0" class="form-control" />"#),
        ToolboxItem("Label", "textformat", #"<label asp-for="$0" class="form-label"></label>"#),
        ToolboxItem("Validation Message", "exclamationmark.triangle", #"<span asp-validation-for="$0" class="text-danger"></span>"#),
        ToolboxItem("Validation Summary", "list.bullet.rectangle", #"<div asp-validation-summary="ModelOnly" class="text-danger">$0</div>"#),
        ToolboxItem("Select", "chevron.down.square", #"<select asp-for="$0" asp-items="Model.Items" class="form-select"></select>"#),
        ToolboxItem("Link to Page", "link", #"<a asp-page="$0">Link</a>"#),
        ToolboxItem("Partial View", "rectangle.split.3x1", #"<partial name="$0" />"#),
        ToolboxItem("Razor Code Block", "curlybraces", "@{\n    $0\n}"),
        ToolboxItem("Razor foreach", "repeat", "@foreach (var item in $0)\n{\n    <p>@item</p>\n}"),
        ToolboxItem("Razor if", "arrow.triangle.branch", "@if ($0)\n{\n    <p></p>\n}"),
    ])

    static let csharp = ToolboxGroup(name: "C# Snippets", items: [
        ToolboxItem("Class", "c.square", "public class $0MyClass\n{\n}"),
        ToolboxItem("Interface", "i.square", "public interface $0IMyInterface\n{\n}"),
        ToolboxItem("Record", "r.square", "public record $0MyRecord(string Name);"),
        ToolboxItem("Property", "p.square", "public string $0Name { get; set; }"),
        ToolboxItem("Constructor", "hammer", "public MyClass($0)\n{\n}"),
        ToolboxItem("Method", "m.square", "public void $0DoWork()\n{\n}"),
        ToolboxItem("Async Method", "clock.arrow.circlepath", "public async Task $0DoWorkAsync()\n{\n    await Task.CompletedTask;\n}"),
        ToolboxItem("if", "arrow.triangle.branch", "if ($0)\n{\n}"),
        ToolboxItem("for", "repeat", "for (int i = 0; i < $0; i++)\n{\n}"),
        ToolboxItem("foreach", "repeat.circle", "foreach (var item in $0)\n{\n}"),
        ToolboxItem("while", "arrow.clockwise", "while ($0)\n{\n}"),
        ToolboxItem("switch", "switch.2", "switch ($0)\n{\n    case 1:\n        break;\n    default:\n        break;\n}"),
        ToolboxItem("try / catch", "exclamationmark.shield", "try\n{\n    $0\n}\ncatch (Exception ex)\n{\n    Console.WriteLine(ex.Message);\n}"),
        ToolboxItem("using", "shippingbox", "using (var $0resource = )\n{\n}"),
        ToolboxItem("Console.WriteLine", "text.bubble", "Console.WriteLine($0);"),
        ToolboxItem("API Endpoint", "server.rack", "app.MapGet(\"/$0hello\", () => \"Hello!\");"),
    ])

    static let vb = ToolboxGroup(name: "VB.NET Snippets", items: [
        ToolboxItem("Class", "c.square", "Public Class $0MyClass\n\nEnd Class"),
        ToolboxItem("Module", "square.stack", "Module $0MyModule\n\nEnd Module"),
        ToolboxItem("Sub", "s.square", "Public Sub $0DoWork()\n\nEnd Sub"),
        ToolboxItem("Function", "f.square", "Public Function $0Calculate() As Integer\n    Return 0\nEnd Function"),
        ToolboxItem("Property", "p.square", "Public Property $0Name As String"),
        ToolboxItem("If…Then", "arrow.triangle.branch", "If $0 Then\n\nEnd If"),
        ToolboxItem("If…Else", "arrow.triangle.branch", "If $0 Then\n\nElse\n\nEnd If"),
        ToolboxItem("For…Next", "repeat", "For i As Integer = 1 To $0\n\nNext"),
        ToolboxItem("For Each", "repeat.circle", "For Each item In $0\n\nNext"),
        ToolboxItem("Do While", "arrow.clockwise", "Do While $0\n\nLoop"),
        ToolboxItem("Select Case", "switch.2", "Select Case $0\n    Case 1\n\n    Case Else\n\nEnd Select"),
        ToolboxItem("Try…Catch", "exclamationmark.shield", "Try\n    $0\nCatch ex As Exception\n    Console.WriteLine(ex.Message)\nEnd Try"),
        ToolboxItem("Using", "shippingbox", "Using $0resource As New Object()\n\nEnd Using"),
        ToolboxItem("Console.WriteLine", "text.bubble", "Console.WriteLine($0)"),
        ToolboxItem("MsgBox-style Input", "keyboard", "Console.Write(\"Enter a value: \")\nDim $0value As String = Console.ReadLine()"),
    ])

    static let swiftUI = ToolboxGroup(name: "SwiftUI Controls", items: [
        ToolboxItem("Text", "textformat", #"Text("$0Hello")"#),
        ToolboxItem("Button", "rectangle.and.hand.point.up.left", "Button(\"$0Button\") {\n}"),
        ToolboxItem("Text Field", "character.cursor.ibeam", #"TextField("$0Placeholder", text: $text)"#),
        ToolboxItem("Toggle", "switch.2", #"Toggle("$0Option", isOn: $isOn)"#),
        ToolboxItem("Slider", "slider.horizontal.3", "Slider(value: $0$value, in: 0...100)"),
        ToolboxItem("Image", "photo", #"Image(systemName: "$0star")"#),
        ToolboxItem("List", "list.bullet", "List(items, id: \\.self) { item in\n    Text($0item)\n}"),
        ToolboxItem("VStack", "rectangle.split.1x2", "VStack {\n    $0\n}"),
        ToolboxItem("HStack", "rectangle.split.2x1", "HStack {\n    $0\n}"),
        ToolboxItem("Navigation Stack", "sidebar.left", "NavigationStack {\n    $0\n}"),
    ])

    static let swift = ToolboxGroup(name: "Swift Snippets", items: [
        ToolboxItem("struct", "s.square", "struct $0MyType {\n}"),
        ToolboxItem("class", "c.square", "final class $0MyClass {\n}"),
        ToolboxItem("func", "f.square", "func $0doWork() {\n}"),
        ToolboxItem("if let", "arrow.triangle.branch", "if let $0value {\n}"),
        ToolboxItem("for in", "repeat", "for item in $0 {\n}"),
        ToolboxItem("switch", "switch.2", "switch $0 {\ncase .a:\n    break\ndefault:\n    break\n}"),
        ToolboxItem("do / catch", "exclamationmark.shield", "do {\n    $0\n} catch {\n    print(error)\n}"),
    ])

    static let python = ToolboxGroup(name: "Python Snippets", items: [
        ToolboxItem("def", "f.square", "def $0name():\n    pass"),
        ToolboxItem("class", "c.square", "class $0Name:\n    def __init__(self):\n        pass"),
        ToolboxItem("if", "arrow.triangle.branch", "if $0:\n    pass"),
        ToolboxItem("for", "repeat", "for item in $0:\n    pass"),
        ToolboxItem("while", "arrow.clockwise", "while $0:\n    pass"),
        ToolboxItem("try / except", "exclamationmark.shield", "try:\n    $0\nexcept Exception as error:\n    print(error)"),
        ToolboxItem("with open", "doc.text", "with open(\"$0file.txt\") as file:\n    text = file.read()"),
        ToolboxItem("main guard", "play", "if __name__ == \"__main__\":\n    $0main()"),
    ])

    static let javascript = ToolboxGroup(name: "JavaScript Snippets", items: [
        ToolboxItem("function", "f.square", "function $0name() {\n}"),
        ToolboxItem("arrow function", "arrow.right", "const $0name = () => {\n};"),
        ToolboxItem("class", "c.square", "class $0Name {\n    constructor() {\n    }\n}"),
        ToolboxItem("if", "arrow.triangle.branch", "if ($0) {\n}"),
        ToolboxItem("for…of", "repeat", "for (const item of $0) {\n}"),
        ToolboxItem("try / catch", "exclamationmark.shield", "try {\n    $0\n} catch (error) {\n    console.error(error);\n}"),
        ToolboxItem("fetch", "network", "const response = await fetch(\"$0\");\nconst data = await response.json();"),
        ToolboxItem("event listener", "hand.tap", "document.querySelector(\"$0\").addEventListener(\"click\", () => {\n});"),
    ])

    static let css = ToolboxGroup(name: "CSS", items: [
        ToolboxItem("Rule", "curlybraces", "$0selector {\n}"),
        ToolboxItem("Flex Row", "rectangle.split.3x1", "display: flex;\ngap: $08px;\nalign-items: center;"),
        ToolboxItem("Grid", "square.grid.2x2", "display: grid;\ngrid-template-columns: repeat($03, 1fr);\ngap: 16px;"),
        ToolboxItem("Media Query", "iphone", "@media (max-width: $0600px) {\n}"),
    ])
}

/// The HTML start tag around a position, for the Properties window.
public struct HTMLTag: Equatable, Sendable {
    public let range: NSRange              // the whole start tag, `<` to `>`
    public let name: String
    public var attributes: [(name: String, value: String?)]
    public let selfClosing: Bool

    public static func == (a: HTMLTag, b: HTMLTag) -> Bool {
        a.range == b.range && a.name == b.name && a.selfClosing == b.selfClosing
            && a.attributes.map { "\($0.name)=\($0.value ?? "∅")" } == b.attributes.map { "\($0.name)=\($0.value ?? "∅")" }
    }

    private static let attribute = try! NSRegularExpression(pattern: #"([^\s=/>"']+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s>]+))?"#)

    /// The start tag the position is in, or else the nearest one before it on the same line or earlier.
    public static func at(_ offset: Int, in text: String) -> HTMLTag? {
        let ns = text as NSString
        var index = min(offset, ns.length - 1)
        while index >= 0 {
            if ns.character(at: index) == 0x3C /* < */, index + 1 < ns.length,
               let next = UnicodeScalar(ns.character(at: index + 1)), CharacterSet.letters.contains(next),
               let tag = parse(ns, from: index) {
                return tag
            }
            index -= 1
        }
        return nil
    }

    static func parse(_ ns: NSString, from start: Int) -> HTMLTag? {
        var index = start + 1
        var quote: unichar = 0
        while index < ns.length {
            let c = ns.character(at: index)
            if quote != 0 { if c == quote { quote = 0 } }
            else if c == 0x22 || c == 0x27 { quote = c }
            else if c == 0x3E /* > */ { break }
            index += 1
        }
        guard index < ns.length else { return nil }
        let range = NSRange(location: start, length: index - start + 1)
        var inner = ns.substring(with: NSRange(location: start + 1, length: index - start - 1))
        let selfClosing = inner.hasSuffix("/")
        if selfClosing { inner.removeLast() }
        let name = String(inner.prefix { !$0.isWhitespace })
        let rest = String(inner.dropFirst(name.count)) as NSString
        var attributes: [(String, String?)] = []
        attribute.enumerateMatches(in: rest as String, range: NSRange(location: 0, length: rest.length)) { match, _, _ in
            guard let match else { return }
            let key = rest.substring(with: match.range(at: 1))
            var value: String?
            if match.range(at: 2).location != NSNotFound {
                var raw = rest.substring(with: match.range(at: 2))
                if raw.count >= 2, let first = raw.first, first == "\"" || first == "'", raw.last == first { raw = String(raw.dropFirst().dropLast()) }
                value = raw
            }
            attributes.append((key, value))
        }
        return HTMLTag(range: range, name: name, attributes: attributes, selfClosing: selfClosing)
    }

    /// The start tag written back out, e.g. `<input type="text" required>`.
    public var source: String {
        var text = "<" + name
        for (key, value) in attributes {
            text += " " + key
            if let value { text += "=\"" + value.replacingOccurrences(of: "\"", with: "&quot;") + "\"" }
        }
        return text + (selfClosing ? " />" : ">")
    }
}
