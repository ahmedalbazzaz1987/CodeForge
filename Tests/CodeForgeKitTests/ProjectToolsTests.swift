import XCTest
@testable import CodeForgeKit

final class ProjectToolsTests: XCTestCase {
    func testReleaseConfiguration() {
        let swift = BuildPlan(name: "Swift package", build: "swift build", program: "/p/.build/debug/Tool", folder: "/p", run: "swift run")
        let release = BuildSystem.plan(swift, for: .release)
        XCTAssertEqual(release.build, "swift build -c release")
        XCTAssertEqual(release.run, "swift run -c release")
        XCTAssertEqual(release.program, "/p/.build/release/Tool")
        let dotnet = BuildPlan(name: ".NET", build: "dotnet build", folder: "/p", run: "dotnet run --project 'Web/Web.csproj'")
        XCTAssertEqual(BuildSystem.plan(dotnet, for: .release).run, "dotnet run -c Release --project 'Web/Web.csproj'")
        XCTAssertEqual(BuildSystem.plan(dotnet, for: .debug).build, "dotnet build")
    }

    func testTestCommands() throws {
        func folder(_ files: [String: String]) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for (name, text) in files { try text.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8) }
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
            return url
        }
        XCTAssertEqual(BuildSystem.testCommand(in: try folder(["App.vbproj": ""])), "dotnet test")
        XCTAssertEqual(BuildSystem.testCommand(in: try folder(["Package.swift": ""])), "swift test")
        XCTAssertEqual(BuildSystem.testCommand(in: try folder(["test_math.py": ""]))?.hasPrefix("python3 -m pytest"), true)
        XCTAssertNil(BuildSystem.testCommand(in: try folder(["main.py": ""])))
    }

    func testItemTemplates() {
        let vbClass = ItemTemplates.all.first { $0.group == "VB.NET" && $0.name == "Class" }!
        XCTAssertEqual(ItemTemplates.fileName("Customer", for: vbClass), "Customer.vb")
        XCTAssertEqual(ItemTemplates.fileName("", for: vbClass), "Class1.vb")
        XCTAssertEqual(ItemTemplates.contents(of: vbClass, fileName: "Customer.vb", namespace: "Shop"), "Public Class Customer\n\nEnd Class\n")
        let csClass = ItemTemplates.all.first { $0.group == "C#" && $0.name == "Class" }!
        XCTAssertTrue(ItemTemplates.contents(of: csClass, fileName: "Order.cs", namespace: "Shop").hasPrefix("namespace Shop;"))
    }
}
