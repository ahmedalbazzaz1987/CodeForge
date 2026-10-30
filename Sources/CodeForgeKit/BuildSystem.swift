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
    /// Runs the whole project (Start), when the project type has a standard way to do it.
    public let run: String?
    /// Languages that belong to the project: Start runs the project for these files, and the file itself otherwise.
    public let languages: [String]

    public init(name: String, build: String, clean: String? = nil, program: String? = nil, folder: String,
                run: String? = nil, languages: [String] = []) {
        self.name = name
        self.build = build
        self.clean = clean
        self.program = program
        self.folder = folder
        self.run = run
        self.languages = languages
    }
}

/// Visual Studio's solution configurations.
public enum BuildConfiguration: String, CaseIterable, Sendable {
    case debug = "Debug"
    case release = "Release"
}

public enum BuildSystem {
    /// The plan with its build and run commands switched to a configuration (Debug is the default everywhere).
    public static func plan(_ plan: BuildPlan, for configuration: BuildConfiguration) -> BuildPlan {
        guard configuration == .release else { return plan }
        func release(_ command: String?) -> String? {
            guard let command else { return nil }
            let rules: [(String, String)] = [
                ("dotnet build", "dotnet build -c Release"), ("dotnet run", "dotnet run -c Release"),
                ("swift build", "swift build -c release"), ("swift run", "swift run -c release"),
                ("cargo build", "cargo build --release"), ("cargo run", "cargo run --release"),
                ("cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug", "cmake -S . -B build -DCMAKE_BUILD_TYPE=Release"),
                ("xcodebuild -configuration Debug", "xcodebuild -configuration Release"),
            ]
            for (debug, optimized) in rules where command.hasPrefix(debug) {
                return optimized + command.dropFirst(debug.count)
            }
            return command
        }
        return BuildPlan(name: plan.name, build: release(plan.build) ?? plan.build, clean: plan.clean,
                         program: plan.program?.replacingOccurrences(of: "/.build/debug/", with: "/.build/release/")
                            .replacingOccurrences(of: "/target/debug/", with: "/target/release/"),
                         folder: plan.folder, run: release(plan.run), languages: plan.languages)
    }

    /// The command that runs a project's tests (Test ▸ Run All Tests), if the project type has one.
    public static func testCommand(in folder: URL) -> String? {
        let fm = FileManager.default
        let names = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        if names.contains(where: { $0.hasSuffix(".sln") || $0.hasSuffix(".slnx") || $0.hasSuffix(".csproj") || $0.hasSuffix(".vbproj") || $0.hasSuffix(".fsproj") }) {
            return "dotnet test"
        }
        if names.contains("Package.swift") { return "swift test" }
        if names.contains("Cargo.toml") { return "cargo test" }
        if names.contains("go.mod") { return "go test ./..." }
        if names.contains("package.json"),
           let manifest = try? String(contentsOf: folder.appendingPathComponent("package.json"), encoding: .utf8), manifest.contains("\"test\"") {
            return "npm test"
        }
        let pythonTests = names.contains("tests") || names.contains("test") || names.contains("pytest.ini")
            || names.contains(where: { $0.hasPrefix("test_") && $0.hasSuffix(".py") })
        if pythonTests { return "python3 -m pytest 2>/dev/null || python3 -m unittest discover -v" }
        if names.contains("Makefile"), let makefile = try? String(contentsOf: folder.appendingPathComponent("Makefile"), encoding: .utf8),
           makefile.range(of: #"(?m)^test:"#, options: .regularExpression) != nil {
            return "make test"
        }
        return nil
    }

    /// Recognizes the project in a folder from the files at its top level.
    public static func detect(in folder: URL) -> BuildPlan? {
        let fm = FileManager.default
        let names = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        func read(_ name: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "" }
        let path = folder.path

        let dotnetProject = names.sorted().first { [".csproj", ".vbproj", ".fsproj"].contains(where: $0.hasSuffix) }
        let solution = names.sorted().first { $0.hasSuffix(".sln") || $0.hasSuffix(".slnx") }
        if dotnetProject != nil || solution != nil {
            // `dotnet run` needs a project; with only a solution here, use the first project in a subfolder.
            var runTarget = ""
            if dotnetProject == nil, let project = firstProject(below: folder) { runTarget = " --project " + CommandTemplate.shellQuote(project) }
            let name = ((dotnetProject ?? solution)! as NSString).deletingPathExtension
            return BuildPlan(name: ".NET (\(name))", build: "dotnet build", clean: "dotnet clean", folder: path,
                             run: "dotnet run" + runTarget, languages: ["csharp", "vb", "fsharp", "razor", "html", "css", "javascript", "json"])
        }
        if names.contains("Package.swift") {
            let manifest = read("Package.swift")
            let product = firstMatch(#"\.executable(?:Target)?\(\s*name:\s*"([^"]+)""#, in: manifest)
                ?? firstMatch(#"Package\(\s*name:\s*"([^"]+)""#, in: manifest)
            return BuildPlan(name: "Swift package", build: "swift build", clean: "swift package clean",
                             program: product.map { path + "/.build/debug/" + $0 }, folder: path, run: "swift run", languages: ["swift"])
        }
        if names.contains("Cargo.toml") {
            let name = firstMatch(#"(?m)^\s*name\s*=\s*"([^"]+)""#, in: read("Cargo.toml"))
            return BuildPlan(name: "Cargo", build: "cargo build", clean: "cargo clean",
                             program: name.map { path + "/target/debug/" + $0 }, folder: path, run: "cargo run", languages: ["rust"])
        }
        if names.contains("go.mod") {
            return BuildPlan(name: "Go module", build: "go build -gcflags=all='-N -l' -o .codeforge/debug-binary .",
                             clean: "go clean && rm -rf .codeforge", program: path + "/.codeforge/debug-binary", folder: path,
                             run: "go run .", languages: ["go"])
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
        if names.contains("package.json") {
            let manifest = read("package.json")
            let hasBuild = manifest.contains("\"build\""), hasStart = manifest.contains("\"start\"")
            if hasBuild || hasStart {
                return BuildPlan(name: "npm", build: hasBuild ? "npm run build" : "npm install", folder: path,
                                 run: hasStart ? "npm start" : nil, languages: ["javascript", "typescript", "json", "html", "css"])
            }
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

    private static func firstProject(below folder: URL) -> String? {
        let fm = FileManager.default
        for sub in ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where !sub.hasPrefix(".") {
            let files = (try? fm.contentsOfDirectory(atPath: folder.appendingPathComponent(sub).path)) ?? []
            if let project = files.sorted().first(where: { $0.hasSuffix(".csproj") || $0.hasSuffix(".vbproj") || $0.hasSuffix(".fsproj") }) {
                return sub + "/" + project
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }
}
