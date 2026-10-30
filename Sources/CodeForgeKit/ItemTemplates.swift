import Foundation

/// A new file from Project ▸ Add New Item…, like Visual Studio's item templates.
public struct ItemTemplate: Sendable {
    public let name: String
    public let group: String
    public let fileExtension: String
    public let defaultName: String
    /// File contents. `{{name}}` is the file name without its extension, `{{namespace}}` the project's root namespace.
    public let contents: String
}

public enum ItemTemplates {
    public static let all: [ItemTemplate] = [
        ItemTemplate(name: "Class", group: "C#", fileExtension: "cs", defaultName: "Class1",
                     contents: "namespace {{namespace}};\n\npublic class {{name}}\n{\n}\n"),
        ItemTemplate(name: "Interface", group: "C#", fileExtension: "cs", defaultName: "IInterface1",
                     contents: "namespace {{namespace}};\n\npublic interface {{name}}\n{\n}\n"),
        ItemTemplate(name: "Razor Page", group: "ASP.NET", fileExtension: "cshtml", defaultName: "Page1",
                     contents: "@page\n\n<h1>{{name}}</h1>\n"),
        ItemTemplate(name: "Razor Component", group: "ASP.NET", fileExtension: "razor", defaultName: "Component1",
                     contents: "<h3>{{name}}</h3>\n\n@code {\n}\n"),
        ItemTemplate(name: "Class", group: "VB.NET", fileExtension: "vb", defaultName: "Class1",
                     contents: "Public Class {{name}}\n\nEnd Class\n"),
        ItemTemplate(name: "Module", group: "VB.NET", fileExtension: "vb", defaultName: "Module1",
                     contents: "Module {{name}}\n\nEnd Module\n"),
        ItemTemplate(name: "HTML Page", group: "Web", fileExtension: "html", defaultName: "page1",
                     contents: "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <title>{{name}}</title>\n</head>\n<body>\n\n</body>\n</html>\n"),
        ItemTemplate(name: "Style Sheet", group: "Web", fileExtension: "css", defaultName: "styles", contents: "body {\n}\n"),
        ItemTemplate(name: "JavaScript File", group: "Web", fileExtension: "js", defaultName: "script", contents: ""),
        ItemTemplate(name: "TypeScript File", group: "Web", fileExtension: "ts", defaultName: "module1", contents: "export {};\n"),
        ItemTemplate(name: "JSON File", group: "General", fileExtension: "json", defaultName: "settings", contents: "{\n}\n"),
        ItemTemplate(name: "Swift File", group: "Swift", fileExtension: "swift", defaultName: "File1", contents: "import Foundation\n"),
        ItemTemplate(name: "Python File", group: "Python", fileExtension: "py", defaultName: "module1", contents: ""),
        ItemTemplate(name: "C Source File", group: "C/C++", fileExtension: "c", defaultName: "source1", contents: "#include <stdio.h>\n"),
        ItemTemplate(name: "C++ Source File", group: "C/C++", fileExtension: "cpp", defaultName: "source1", contents: "#include <iostream>\n"),
        ItemTemplate(name: "Header File", group: "C/C++", fileExtension: "h", defaultName: "header1",
                     contents: "#pragma once\n"),
        ItemTemplate(name: "Text File", group: "General", fileExtension: "txt", defaultName: "TextFile1", contents: ""),
        ItemTemplate(name: "Markdown File", group: "General", fileExtension: "md", defaultName: "README", contents: "# {{name}}\n"),
    ]

    /// The file name with the template's extension added when the user didn't type one.
    public static func fileName(_ typed: String, for template: ItemTemplate) -> String {
        let name = typed.trimmingCharacters(in: .whitespaces)
        let base = name.isEmpty ? template.defaultName : name
        return (base as NSString).pathExtension.isEmpty ? base + "." + template.fileExtension : base
    }

    public static func contents(of template: ItemTemplate, fileName: String, namespace: String) -> String {
        template.contents
            .replacingOccurrences(of: "{{name}}", with: (fileName as NSString).deletingPathExtension)
            .replacingOccurrences(of: "{{namespace}}", with: namespace)
    }
}
