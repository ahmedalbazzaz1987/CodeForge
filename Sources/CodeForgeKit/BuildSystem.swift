import Foundation

/// How to build (and where to find the program to debug) for a project or a single file.
public struct BuildPlan: Equatable, Sendable {
    public let name: String
    /// Builds with debug information. Runs in `folder`.
    public let build: String
    public let clean: String?
    /// The program to debug after building (absolute), when it can be known in advance.
    public let program: String?
    public let folder: String

    public init(name: String, build: String, clean: String? = nil, program: String? = nil, folder: String) {
        self.name = name
        self.build = build
        self.clean = clean
        self.program = program
        self.folder = folder
    }
}

public enum BuildSystem {
    /// Recognizes the project in a folder from the files at its top level.
    public static func detect(in folder: URL) -> BuildPlan? {
        let fm = FileManager.default
        let names = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        func read(_ name: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "" }
        let path = folder.path

        if names.contains("Package.swift") {
            let manifest = read("Package.swift")
            let product = firstMatch(#"\.executable(?:Target)?\(\s*name:\s*"([^"]+)""#, in: manifest)
                ?? firstMatch(#"Package\(\s*name:\s*"([^"]+)""#, in: manifest)
            return BuildPlan(name: "Swift package", build: "swift build", clean: "swift package clean",
                             program: product.map { path + "/.build/debug/" + $0 }, folder: path)
        }
        if names.contains("Cargo.toml") {
            let name = firstMatch(#"(?m)^\s*name\s*=\s*"([^"]+)""#, in: read("Cargo.toml"))
            return BuildPlan(name: "Cargo", build: "cargo build", clean: "cargo clean",
                             program: name.map { path + "/target/debug/" + $0 }, folder: path)
        }
        if names.contains("go.mod") {
            return BuildPlan(name: "Go module", build: "go build -gcflags=all='-N -l' -o .codeforge/debug-binary .",
                             clean: "go clean && rm -rf .codeforge", program: path + "/.codeforge/debug-binary", folder: path)
        }
        if names.contains("CMakeLists.txt") {
            return BuildPlan(name: "CMake", build: "cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build",
                             clean: "rm -rf build", folder: path)
        }
        if names.contains(where: { $0.hasSuffix(".xcodeproj") }) {
            return BuildPlan(name: "Xcode project", build: "xcodebuild -configuration Debug build", clean: "xcodebuild clean", folder: path)
        }
        if names.contains("Makefile") || names.contains("makefile") {
            return BuildPlan(name: "Make", build: "make", clean: "make clean", folder: path)
        }
        if names.contains("package.json"), read("package.json").contains("\"build\"") {
            return BuildPlan(name: "npm", build: "npm run build", folder: path)
        }
        if names.contains("tsconfig.json") {
            return BuildPlan(name: "TypeScript", build: "npx --yes tsc", folder: path)
        }
        return nil
    }

    /// Builds just one file (with debug information when it compiles to a program).
    public static func singleFile(_ file: URL, languageId: String, outputDirectory: URL) -> BuildPlan? {
        let templates: [String: String] = [
            "c": "clang -std=c17 -g -O0 -Wall {file} -o {out}",
            "cpp": "clang++ -std=c++20 -g -O0 -Wall {file} -o {out}",
            "objc": "clang -g -O0 -fobjc-arc -framework Foundation {file} -o {out}",
            "swift": "swiftc -g -Onone {file} -o {out}",
            "rust": "rustc -g {file} -o {out}",
            "go": "go build -gcflags=all='-N -l' -o {out} {file}",
            "python": "python3 -m py_compile {file}",
            "java": "javac -d {dir} {file}",
            "typescript": "npx --yes tsc --noEmit {file}",
        ]
        guard let template = templates[languageId] else { return nil }
        let compiles = ["c", "cpp", "objc", "swift", "rust", "go"].contains(languageId)
        let program = outputDirectory.appendingPathComponent(file.deletingPathExtension().lastPathComponent).path
        return BuildPlan(name: file.lastPathComponent,
                         build: CommandTemplate.expand(template, file: file, outputDirectory: outputDirectory),
                         program: compiles ? program : nil, folder: file.deletingLastPathComponent().path)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }
}
