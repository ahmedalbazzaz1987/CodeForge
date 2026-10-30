import Foundation

/// A starter project for File ▸ New Project.
public struct ProjectTemplate: Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let tags: String
    /// SF Symbol shown in the template list.
    public let symbol: String
    /// Relative paths and contents. `{{name}}` is the project name; `{{ident}}` the name as an identifier.
    public let files: [String: String]
    /// The file opened after the project is created.
    public let mainFile: String
    /// Project run command; nil runs the current file.
    public let runCommand: String?
    /// A shell command that creates the project instead of `files` (run in the parent folder).
    /// `{{folder}}` is the new folder's name, `{{ident}}` the identifier form of the name.
    public var command: String? = nil
    /// The group shown in New Project.
    public var group: String = "General"
}

public enum ProjectTemplates {
    public static let all: [ProjectTemplate] = dotnet + general

    /// .NET templates, created with `dotnet new` (needs the .NET SDK).
    public static let dotnet: [ProjectTemplate] = [
        ProjectTemplate(id: "aspnet-razor", name: "ASP.NET Core Web App (Razor Pages)",
                        summary: "A web site with Razor Pages, opened in your browser when you press Start.",
                        tags: "C#  ASP.NET  Web", symbol: "globe.americas", files: [:], mainFile: "Pages/Index.cshtml", runCommand: nil,
                        command: "dotnet new webapp -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "aspnet-mvc", name: "ASP.NET Core Web App (Model-View-Controller)",
                        summary: "A web site with controllers and views (MVC).",
                        tags: "C#  ASP.NET  Web", symbol: "square.stack.3d.up", files: [:], mainFile: "Controllers/HomeController.cs", runCommand: nil,
                        command: "dotnet new mvc -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "aspnet-api", name: "ASP.NET Core Web API",
                        summary: "An HTTP API with OpenAPI support.",
                        tags: "C#  ASP.NET  API", symbol: "server.rack", files: [:], mainFile: "Program.cs", runCommand: nil,
                        command: "dotnet new webapi -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "blazor", name: "Blazor Web App",
                        summary: "Interactive web UI built with C# and Razor components.",
                        tags: "C#  Blazor  Web", symbol: "flame", files: [:], mainFile: "Components/Pages/Home.razor", runCommand: nil,
                        command: "dotnet new blazor -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "vb-console", name: "Console App (VB.NET)",
                        summary: "A Visual Basic .NET command-line program.",
                        tags: "VB.NET  Console", symbol: "v.square", files: [:], mainFile: "Program.vb", runCommand: nil,
                        command: "dotnet new console -lang VB -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "vb-library", name: "Class Library (VB.NET)",
                        summary: "A Visual Basic .NET library of classes to share between projects.",
                        tags: "VB.NET  Library", symbol: "books.vertical", files: [:], mainFile: "Class1.vb", runCommand: nil,
                        command: "dotnet new classlib -lang VB -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "cs-console", name: "Console App (C#)",
                        summary: "A C# command-line program.",
                        tags: "C#  Console", symbol: "number.square", files: [:], mainFile: "Program.cs", runCommand: nil,
                        command: "dotnet new console -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "cs-library", name: "Class Library (C#)",
                        summary: "A C# library of classes to share between projects.",
                        tags: "C#  Library", symbol: "books.vertical.fill", files: [:], mainFile: "Class1.cs", runCommand: nil,
                        command: "dotnet new classlib -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "aspnet-empty", name: "ASP.NET Core Empty",
                        summary: "An empty ASP.NET Core app: one Program.cs that answers “Hello World!”.",
                        tags: "C#  ASP.NET  Web", symbol: "doc.badge.gearshape", files: [:], mainFile: "Program.cs", runCommand: nil,
                        command: "dotnet new web -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "grpc", name: "ASP.NET Core gRPC Service",
                        summary: "A gRPC service with a sample Greeter (Protos/greet.proto).",
                        tags: "C#  gRPC  Service", symbol: "point.3.connected.trianglepath.dotted", files: [:], mainFile: "Services/GreeterService.cs", runCommand: nil,
                        command: "dotnet new grpc -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "worker", name: "Worker Service",
                        summary: "A long-running background service (it logs every second until you press Stop).",
                        tags: "C#  Service  Background", symbol: "gearshape.2", files: [:], mainFile: "Worker.cs", runCommand: nil,
                        command: "dotnet new worker -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "blazorwasm", name: "Blazor WebAssembly Standalone App",
                        summary: "A Blazor app that runs entirely in the browser with WebAssembly.",
                        tags: "C#  Blazor  WebAssembly", symbol: "flame.fill", files: [:], mainFile: "Pages/Home.razor", runCommand: nil,
                        command: "dotnet new blazorwasm -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "razorclasslib", name: "Razor Class Library",
                        summary: "Razor components to share between ASP.NET Core and Blazor apps.",
                        tags: "C#  Razor  Library", symbol: "shippingbox", files: [:], mainFile: "Component1.razor", runCommand: nil,
                        command: "dotnet new razorclasslib -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "maui", name: ".NET MAUI App",
                        summary: "A cross-platform app with XAML pages; Start runs it on this Mac (Mac Catalyst). Needs the MAUI workload and Xcode.",
                        tags: "C#  MAUI  XAML  Mobile  Desktop", symbol: "iphone.and.arrow.forward", files: [:], mainFile: "MainPage.xaml", runCommand: nil,
                        command: "{ dotnet new list maui 2>/dev/null | grep -q ' maui ' || { echo 'The .NET MAUI workload is not installed. Install it with: dotnet workload install maui  (about 2 GB; Xcode is needed to run on this Mac)'; exit 1; }; } && dotnet new maui -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "avalonia", name: "Avalonia Desktop App (XAML)",
                        summary: "A desktop app with XAML windows, like WPF, that runs on macOS, Windows and Linux.",
                        tags: "C#  XAML  Desktop  Avalonia", symbol: "macwindow", files: [:], mainFile: "MainWindow.axaml", runCommand: nil,
                        command: "{ dotnet new list avalonia.app 2>/dev/null | grep -q avalonia.app || dotnet new install Avalonia.Templates; } && dotnet new avalonia.app -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "avalonia-mvvm", name: "Avalonia MVVM App (XAML)",
                        summary: "An Avalonia desktop app organized as Views and ViewModels (MVVM), like a WPF MVVM app.",
                        tags: "C#  XAML  MVVM  Avalonia", symbol: "rectangle.3.group", files: [:], mainFile: "Views/MainWindow.axaml", runCommand: nil,
                        command: "{ dotnet new list avalonia.mvvm 2>/dev/null | grep -q avalonia.mvvm || dotnet new install Avalonia.Templates; } && dotnet new avalonia.mvvm -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "xunit-cs", name: "xUnit Test Project (C#)",
                        summary: "Unit tests with xUnit. Run them with Test ▸ Run All Tests (⌘U).",
                        tags: "C#  Test  xUnit", symbol: "checkmark.seal", files: [:], mainFile: "UnitTest1.cs", runCommand: nil,
                        command: "dotnet new xunit -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "xunit-vb", name: "xUnit Test Project (VB.NET)",
                        summary: "Visual Basic unit tests with xUnit. Run them with Test ▸ Run All Tests (⌘U).",
                        tags: "VB.NET  Test  xUnit", symbol: "checkmark.seal.fill", files: [:], mainFile: "UnitTest1.vb", runCommand: nil,
                        command: "dotnet new xunit -lang VB -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "mstest", name: "MSTest Test Project",
                        summary: "Unit tests with Microsoft's MSTest framework.",
                        tags: "C#  Test  MSTest", symbol: "checklist", files: [:], mainFile: "Test1.cs", runCommand: nil,
                        command: "dotnet new mstest -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "nunit", name: "NUnit Test Project",
                        summary: "Unit tests with NUnit.",
                        tags: "C#  Test  NUnit", symbol: "checklist.checked", files: [:], mainFile: "UnitTest1.cs", runCommand: nil,
                        command: "dotnet new nunit -o {{folder}} -n {{ident}}", group: ".NET"),
        ProjectTemplate(id: "fs-console", name: "Console App (F#)",
                        summary: "An F# command-line program.",
                        tags: "F#  Console", symbol: "f.square", files: [:], mainFile: "Program.fs", runCommand: nil,
                        command: "dotnet new console -lang F# -o {{folder}} -n {{ident}}", group: ".NET"),
    ]

    public static let general: [ProjectTemplate] = [
        ProjectTemplate(
            id: "python", name: "Python Console App", summary: "A Python 3 program that runs in the Output panel.",
            tags: "Python", symbol: "chevron.left.forwardslash.chevron.right",
            files: [
                "main.py": """
                    def main():
                        name = input("What's your name? ")
                        print(f"Hello, {name}! Welcome to {{name}}.")


                    if __name__ == "__main__":
                        main()

                    """,
                ".gitignore": "__pycache__/\n.venv/\n",
            ],
            mainFile: "main.py", runCommand: nil
        ),
        ProjectTemplate(
            id: "c", name: "C Console App", summary: "A C17 program built with clang.",
            tags: "C", symbol: "c.square",
            files: [
                "main.c": """
                    #include <stdio.h>

                    int main(void) {
                        printf("Hello from {{name}}!\\n");
                        return 0;
                    }

                    """,
            ],
            mainFile: "main.c", runCommand: nil
        ),
        ProjectTemplate(
            id: "cpp", name: "C++ Console App", summary: "A C++20 program built with clang++.",
            tags: "C++", symbol: "plus.square",
            files: [
                "main.cpp": """
                    #include <iostream>
                    #include <string>

                    int main() {
                        std::string name = "{{name}}";
                        std::cout << "Hello from " << name << "!" << std::endl;
                        return 0;
                    }

                    """,
            ],
            mainFile: "main.cpp", runCommand: nil
        ),
        ProjectTemplate(
            id: "swift-package", name: "Swift Command-Line Tool", summary: "A Swift package with an executable, run with `swift run`.",
            tags: "Swift", symbol: "swift",
            files: [
                "Package.swift": """
                    // swift-tools-version: 5.9
                    import PackageDescription

                    let package = Package(
                        name: "{{ident}}",
                        targets: [
                            .executableTarget(name: "{{ident}}"),
                        ]
                    )

                    """,
                "Sources/{{ident}}/main.swift": """
                    print("Hello from {{name}}!")

                    """,
                ".gitignore": ".build/\n.swiftpm/\n",
            ],
            mainFile: "Sources/{{ident}}/main.swift", runCommand: "swift run"
        ),
        ProjectTemplate(
            id: "node", name: "Node.js Console App", summary: "A JavaScript program with a package.json, run with Node.",
            tags: "JavaScript", symbol: "curlybraces",
            files: [
                "package.json": """
                    {
                      "name": "{{ident}}",
                      "version": "1.0.0",
                      "main": "index.js",
                      "scripts": { "start": "node index.js" }
                    }

                    """,
                "index.js": """
                    const name = "{{name}}";
                    console.log(`Hello from ${name}!`);

                    """,
                ".gitignore": "node_modules/\n",
            ],
            mainFile: "index.js", runCommand: "npm start --silent"
        ),
        ProjectTemplate(
            id: "typescript", name: "TypeScript Console App", summary: "A TypeScript program run with tsx.",
            tags: "TypeScript", symbol: "t.square",
            files: [
                "index.ts": """
                    function greet(name: string): string {
                        return `Hello from ${name}!`;
                    }

                    console.log(greet("{{name}}"));

                    """,
            ],
            mainFile: "index.ts", runCommand: nil
        ),
        ProjectTemplate(
            id: "web", name: "Web Page", summary: "HTML, CSS and JavaScript, opened in your browser.",
            tags: "HTML  CSS  JavaScript", symbol: "globe",
            files: [
                "index.html": """
                    <!doctype html>
                    <html lang="en">
                    <head>
                      <meta charset="utf-8">
                      <meta name="viewport" content="width=device-width, initial-scale=1">
                      <title>{{name}}</title>
                      <link rel="stylesheet" href="style.css">
                    </head>
                    <body>
                      <h1>{{name}}</h1>
                      <button id="button">Click me</button>
                      <script src="script.js"></script>
                    </body>
                    </html>

                    """,
                "style.css": """
                    body {
                      font-family: -apple-system, system-ui, sans-serif;
                      margin: 40px;
                    }

                    """,
                "script.js": """
                    document.getElementById("button").addEventListener("click", () => {
                      alert("Hello from {{name}}!");
                    });

                    """,
            ],
            mainFile: "index.html", runCommand: "open index.html"
        ),
        ProjectTemplate(
            id: "go", name: "Go Console App", summary: "A Go module, run with `go run .`.",
            tags: "Go", symbol: "g.square",
            files: [
                "go.mod": "module {{ident}}\n\ngo 1.22\n",
                "main.go": """
                    package main

                    import "fmt"

                    func main() {
                    \tfmt.Println("Hello from {{name}}!")
                    }

                    """,
            ],
            mainFile: "main.go", runCommand: "go run ."
        ),
        ProjectTemplate(
            id: "rust", name: "Rust Console App", summary: "A Cargo project, run with `cargo run`.",
            tags: "Rust", symbol: "gearshape.2",
            files: [
                "Cargo.toml": """
                    [package]
                    name = "{{ident}}"
                    version = "0.1.0"
                    edition = "2021"

                    """,
                "src/main.rs": """
                    fn main() {
                        println!("Hello from {{name}}!");
                    }

                    """,
                ".gitignore": "target/\n",
            ],
            mainFile: "src/main.rs", runCommand: "cargo run --quiet"
        ),
        ProjectTemplate(
            id: "java", name: "Java Console App", summary: "A single-file Java program.",
            tags: "Java", symbol: "cup.and.saucer",
            files: [
                "Main.java": """
                    public class Main {
                        public static void main(String[] args) {
                            System.out.println("Hello from {{name}}!");
                        }
                    }

                    """,
            ],
            mainFile: "Main.java", runCommand: nil
        ),
        ProjectTemplate(
            id: "empty", name: "Empty Project", summary: "A folder with a README, ready for any language.",
            tags: "Any", symbol: "folder",
            files: ["README.md": "# {{name}}\n"],
            mainFile: "README.md", runCommand: nil
        ),
    ]

    /// "My App 2" → "MyApp2"; used where a language needs an identifier.
    public static func identifier(for name: String) -> String {
        let ident = name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(String.init).joined()
        guard let first = ident.first else { return "App" }
        return first.isNumber ? "App" + ident : ident
    }

    /// Creates `parent/name` with the template's files and returns the new folder.
    public static func create(_ template: ProjectTemplate, named name: String, in parent: URL) throws -> URL {
        let folder = parent.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: folder.path])
        }
        let ident = identifier(for: name)
        func fill(_ text: String) -> String {
            text.replacingOccurrences(of: "{{name}}", with: name).replacingOccurrences(of: "{{ident}}", with: ident)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (path, contents) in template.files {
            let file = folder.appendingPathComponent(fill(path))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fill(contents).write(to: file, atomically: true, encoding: .utf8)
        }
        return folder
    }

    /// The shell command that creates a `dotnet new`-style template, with the name filled in.
    public static func creationCommand(for template: ProjectTemplate, named name: String) -> String? {
        template.command.map {
            $0.replacingOccurrences(of: "{{folder}}", with: CommandTemplate.shellQuote(name))
                .replacingOccurrences(of: "{{ident}}", with: identifier(for: name))
        }
    }

    public static func mainFile(of template: ProjectTemplate, named name: String) -> String {
        template.mainFile.replacingOccurrences(of: "{{ident}}", with: identifier(for: name))
    }
}
