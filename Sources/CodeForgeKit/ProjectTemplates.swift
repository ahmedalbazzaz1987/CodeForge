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
}

public enum ProjectTemplates {
    public static let all: [ProjectTemplate] = [
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

    public static func mainFile(of template: ProjectTemplate, named name: String) -> String {
        template.mainFile.replacingOccurrences(of: "{{ident}}", with: identifier(for: name))
    }
}
