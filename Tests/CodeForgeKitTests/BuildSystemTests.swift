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
        XCTAssertNil(BuildSystem.detect(in: try folder(["package.json": #"{"scripts": {"start": "node ."}}"#])))
    }

    func testSingleFileC() {
        let plan = BuildSystem.singleFile(URL(fileURLWithPath: "/p/main.c"), languageId: "c", outputDirectory: URL(fileURLWithPath: "/out"))
        XCTAssertEqual(plan?.build, "clang -std=c17 -g -O0 -Wall '/p/main.c' -o '/out/main'")
        XCTAssertEqual(plan?.program, "/out/main")
        XCTAssertNil(BuildSystem.singleFile(URL(fileURLWithPath: "/p/a.py"), languageId: "python", outputDirectory: URL(fileURLWithPath: "/o"))?.program)
        XCTAssertNil(BuildSystem.singleFile(URL(fileURLWithPath: "/p/a.md"), languageId: "markdown", outputDirectory: URL(fileURLWithPath: "/o")))
    }
}
