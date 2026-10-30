import XCTest
@testable import CodeForgeKit

final class BuildSystemTests: XCTestCase {
    private func folder(_ files: [String: String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testSwiftPackageFindsExecutable() throws {
        let f = try folder(["Package.swift": #"let package = Package(name: "Pkg", targets: [.executableTarget(name: "Tool")])"#])
        let plan = BuildSystem.detect(in: f)
        XCTAssertEqual(plan?.build, "swift build")
        XCTAssertEqual(plan?.program, f.path + "/.build/debug/Tool")
    }

    func testCargoAndMakeAndNone() throws {
        let cargo = try folder(["Cargo.toml": "[package]\nname = \"demo\"\nversion = \"0.1.0\"\n"])
        XCTAssertEqual(BuildSystem.detect(in: cargo)?.program, cargo.path + "/target/debug/demo")
        XCTAssertEqual(BuildSystem.detect(in: try folder(["Makefile": "all:\n"]))?.build, "make")
        XCTAssertNil(BuildSystem.detect(in: try folder(["main.py": ""])))
        XCTAssertEqual(BuildSystem.detect(in: try folder(["package.json": #"{"scripts": {"start": "node ."}}"#]))?.run, "npm start")
        XCTAssertNil(BuildSystem.detect(in: try folder(["package.json": #"{"name": "x"}"#])))
    }

    func testSingleFileC() {
        let plan = BuildSystem.singleFile(URL(fileURLWithPath: "/p/main.c"), languageId: "c", outputDirectory: URL(fileURLWithPath: "/out"))
        XCTAssertEqual(plan?.build, "clang -std=c17 -g -O0 -Wall '/p/main.c' -o '/out/main'")
        XCTAssertEqual(plan?.program, "/out/main")
        XCTAssertNil(BuildSystem.singleFile(URL(fileURLWithPath: "/p/a.py"), languageId: "python", outputDirectory: URL(fileURLWithPath: "/o"))?.program)
        XCTAssertNil(BuildSystem.singleFile(URL(fileURLWithPath: "/p/a.md"), languageId: "markdown", outputDirectory: URL(fileURLWithPath: "/o")))
    }
}

final class DotNetTests: XCTestCase {
    func testDotNetProjectDetection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Web"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "".write(to: folder.appendingPathComponent("Shop.sln"), atomically: true, encoding: .utf8)
        try "<Project/>".write(to: folder.appendingPathComponent("Web/Web.csproj"), atomically: true, encoding: .utf8)
        let plan = BuildSystem.detect(in: folder)
        XCTAssertEqual(plan?.name, ".NET (Shop)")
        XCTAssertEqual(plan?.build, "dotnet build")
        XCTAssertEqual(plan?.run, "dotnet run --project 'Web/Web.csproj'")
        XCTAssertTrue(plan?.languages.contains("vb") ?? false)
    }

    func testMSBuildErrorsAndVB() {
        let output = "/p/Program.vb(5,27): error BC30451: 'x' is not declared. [/p/HelloVB.vbproj]\n"
        XCTAssertEqual(DiagnosticParser.parse(output),
                       [Diagnostic(severity: .error, message: "'x' is not declared.", file: "/p/Program.vb", line: 5, column: 27)])
        let vb = Tokenizer(language: Languages.forFile(named: "Program.vb"))
        let tokens = vb.tokens(in: "Dim name As String = \"Hi\" ' greet")
        XCTAssertTrue(tokens.contains(Token(range: NSRange(location: 0, length: 3), kind: .keyword)))
        XCTAssertTrue(tokens.contains { $0.kind == .comment })
        XCTAssertEqual(Languages.forFile(named: "Index.cshtml").id, "razor")
        XCTAssertEqual(Languages.forFile(named: "App.vbproj").id, "html")
    }

    func testDotNetTemplateCommand() {
        let template = ProjectTemplates.dotnet.first { $0.id == "vb-console" }!
        XCTAssertEqual(ProjectTemplates.creationCommand(for: template, named: "My Tool"), "dotnet new console -lang VB -o 'My Tool' -n MyTool")
        XCTAssertNil(ProjectTemplates.creationCommand(for: ProjectTemplates.general[0], named: "x"))
    }
}
