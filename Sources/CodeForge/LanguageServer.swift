import AppKit
import CodeForgeKit

/// A running language server, spoken to with JSON-RPC over its stdin and stdout.
final class LanguageServer {
    let spec: LanguageServerSpec
    let root: URL
    private let process = Process()
    private var stdin: FileHandle?
    private var buffer = LSPMessageBuffer()
    private var nextID = 1
    private var pending: [Int: (Any?) -> Void] = [:]
    private var queued: [[String: Any]] = []
    private var isReady = false
    private(set) var isRunning = false
    private(set) var triggerCharacters: Set<String> = ["."]
    /// The server waits to be asked for diagnostics (`textDocument/diagnostic`) instead of publishing them.
    private(set) var pullsDiagnostics = false
    private(set) var resolvesCodeActions = false
    private var readyActions: [() -> Void] = []

    /// (file, diagnostics) whenever the server publishes diagnostics.
    var onDiagnostics: ((URL, [Diagnostic]) -> Void)?

    init(spec: LanguageServerSpec, executable: URL, root: URL) {
        self.spec = spec
        self.root = root
        process.executableURL = executable
        process.arguments = spec.arguments
        process.currentDirectoryURL = root
        process.environment = LanguageServerManager.environment
    }

    func start() -> Bool {
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        #if DEBUG
        if let log = ProcessInfo.processInfo.environment["CF_LSP_STDERR"] {
            FileManager.default.createFile(atPath: log, contents: nil)
            process.standardError = FileHandle(forWritingAtPath: log)
        }
        #endif
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.isRunning = false }
        }
        do {
            try process.run()
        } catch {
            return false
        }
        stdin = input.fileHandleForWriting
        isRunning = true
        let rootURI = root.absoluteString
        let params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "rootUri": rootURI,
            "workspaceFolders": [["uri": rootURI, "name": root.lastPathComponent]],
            "clientInfo": ["name": "CodeForge"],
            "capabilities": [
                "general": ["positionEncodings": ["utf-16"]],
                "textDocument": [
                    "synchronization": ["didSave": true, "dynamicRegistration": false],
                    "completion": ["completionItem": ["snippetSupport": false, "documentationFormat": ["plaintext", "markdown"]]],
                    "hover": ["contentFormat": ["plaintext", "markdown"]],
                    "definition": ["linkSupport": true],
                    "references": [:],
                    "rename": ["prepareSupport": false],
                    "publishDiagnostics": ["relatedInformation": false],
                    "codeAction": [
                        "codeActionLiteralSupport": ["codeActionKind": ["valueSet": ["", "quickfix", "refactor", "refactor.extract", "refactor.inline", "refactor.rewrite", "source", "source.organizeImports"]]],
                        "resolveSupport": ["properties": ["edit"]], "dataSupport": true, "isPreferredSupport": true,
                    ],
                    "diagnostic": ["dynamicRegistration": false],
                ],
                "workspace": ["workspaceFolders": true, "configuration": true, "applyEdit": true,
                              "workspaceEdit": ["documentChanges": true], "executeCommand": ["dynamicRegistration": false]],
            ],
        ]
        write(["jsonrpc": "2.0", "id": 0, "method": "initialize", "params": params])
        pending[0] = { [weak self] result in
            guard let self else { return }
            let capabilities = (result as? [String: Any])?["capabilities"] as? [String: Any]
            if let characters = (capabilities?["completionProvider"] as? [String: Any])?["triggerCharacters"] as? [String] {
                triggerCharacters = Set(characters.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
            pullsDiagnostics = capabilities?["diagnosticProvider"] != nil
            resolvesCodeActions = (capabilities?["codeActionProvider"] as? [String: Any])?["resolveProvider"] as? Bool ?? false
            write(["jsonrpc": "2.0", "method": "initialized", "params": [String: Any]()])
            isReady = true
            queued.forEach(write)
            queued.removeAll()
            readyActions.forEach { $0() }
            readyActions.removeAll()
        }
        return true
    }

    func request(_ method: String, _ params: [String: Any], completion: @escaping (Any?) -> Void) {
        let id = nextID
        nextID += 1
        pending[id] = completion
        send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }

    /// Runs after the server has answered `initialize` (right away if it already has).
    func whenReady(_ action: @escaping () -> Void) {
        isReady ? action() : readyActions.append(action)
    }

    /// Asks a pull-diagnostics server for a file's problems and reports them like published ones.
    func pullDiagnostics(for url: URL) {
        guard pullsDiagnostics else { return }
        request("textDocument/diagnostic", ["textDocument": ["uri": url.absoluteString]]) { [weak self] result in
            guard let self, let items = (result as? [String: Any])?["items"] as? [[String: Any]] else { return }
            onDiagnostics?(url, Self.diagnostics(items, url: url))
        }
    }

    func notify(_ method: String, _ params: [String: Any]) {
        send(["jsonrpc": "2.0", "method": method, "params": params])
    }

    func shutdown() {
        guard isRunning else { return }
        request("shutdown", [:]) { [weak self] _ in
            self?.notify("exit", [:])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if self?.process.isRunning == true { self?.process.terminate() } }
        }
    }

    private func send(_ message: [String: Any]) {
        isReady ? write(message) : queued.append(message)
    }

    private func write(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        try? stdin?.write(contentsOf: LSPMessageBuffer.frame(data))
    }

    private func receive(_ data: Data) {
        for body in buffer.append(data) {
            guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { continue }
            let method = message["method"] as? String
            if let id = message["id"] as? Int, method == nil {
                pending.removeValue(forKey: id)?(message["result"] is NSNull ? nil : message["result"])
            } else if let method, let id = message["id"] {
                // A request from the server; answer the ones that need an answer.
                var result: Any = NSNull()
                if method == "workspace/configuration", let items = (message["params"] as? [String: Any])?["items"] as? [Any] {
                    result = Array(repeating: NSNull(), count: items.count)
                } else if method == "workspace/applyEdit", let edit = (message["params"] as? [String: Any])?["edit"] {
                    // Code actions that run a command send their changes back this way.
                    LanguageServerManager.shared.onApplyEdit?(LanguageSession.workspaceEdits(edit))
                    result = ["applied": true]
                }
                write(["jsonrpc": "2.0", "id": id, "result": result])
            } else if method == "textDocument/publishDiagnostics", let params = message["params"] as? [String: Any] {
                publishDiagnostics(params)
            }
        }
    }

    private func publishDiagnostics(_ params: [String: Any]) {
        guard let uri = params["uri"] as? String, let url = URL(string: uri), let items = params["diagnostics"] as? [[String: Any]] else { return }
        onDiagnostics?(url, Self.diagnostics(items, url: url))
    }

    private static func diagnostics(_ items: [[String: Any]], url: URL) -> [Diagnostic] {
        items.compactMap { item in
            let severity = item["severity"] as? Int ?? 1
            guard severity <= 2, let range = item["range"] as? [String: Any],
                  let start = range["start"] as? [String: Any], let end = range["end"] as? [String: Any],
                  let line = start["line"] as? Int, let character = start["character"] as? Int else { return nil }
            let message = (item["message"] as? String ?? "").components(separatedBy: "\n").first ?? ""
            return Diagnostic(severity: severity == 1 ? .error : .warning, message: message, file: url.path,
                              line: line + 1, column: character + 1,
                              endLine: (end["line"] as? Int).map { $0 + 1 }, endColumn: (end["character"] as? Int).map { $0 + 1 })
        }
    }
}

/// Starts one language server per kind and project folder, and finds the server executables.
final class LanguageServerManager {
    static let shared = LanguageServerManager()
    private var servers: [String: LanguageServer] = [:]
    private var xcrunCache: [String: URL?] = [:]
    var onDiagnostics: ((URL, [Diagnostic]) -> Void)?
    /// Applies edits a server asks for (`workspace/applyEdit`).
    var onApplyEdit: ((LanguageSession.Edits) -> Void)?

    /// Where CodeForge installs npm-based servers (Pyright, TypeScript).
    static let installDirectory: URL = {
        #if DEBUG
        if let folder = ProcessInfo.processInfo.environment["CF_SERVERS_DIR"] { return URL(fileURLWithPath: folder) }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CodeForge").appendingPathComponent("LanguageServers")
    }()

    private static let searchFolders: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [installDirectory.appendingPathComponent("node_modules/.bin").path, installDirectory.appendingPathComponent("dotnet-tools").path,
                "/opt/homebrew/bin", "/usr/local/bin", home + "/.dotnet/tools",
                home + "/.cargo/bin", home + "/go/bin", home + "/.local/bin", "/usr/bin"]
    }()

    /// Apps opened from Finder get a minimal PATH; servers written in Node need to find `node`.
    static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (searchFolders + [environment["PATH"] ?? ""]).joined(separator: ":")
        // .NET tools installed with Homebrew's SDK need to be told where the runtime is.
        if environment["DOTNET_ROOT"] == nil {
            environment["DOTNET_ROOT"] = ["/opt/homebrew/opt/dotnet/libexec", "/usr/local/share/dotnet", "/usr/local/opt/dotnet/libexec"]
                .first { FileManager.default.fileExists(atPath: $0) }
        }
        return environment
    }()

    func executable(for spec: LanguageServerSpec) -> URL? {
        for name in spec.executables {
            if spec.viaXcrun, let url = xcrunFind(name) { return url }
            for folder in spec.installedCopyOnly ? [Self.searchFolders[0]] : Self.searchFolders {
                let path = folder + "/" + name
                if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
            }
        }
        return nil
    }

    func server(for language: Language, root: URL) -> LanguageServer? {
        guard let spec = LanguageServerSpecs.spec(forLanguage: language.id) else { return nil }
        let key = spec.id + "|" + root.path
        if let server = servers[key], server.isRunning { return server }
        guard let executable = executable(for: spec) else { return nil }
        let server = LanguageServer(spec: spec, executable: executable, root: root)
        server.onDiagnostics = { [weak self] in self?.onDiagnostics?($0, $1) }
        guard server.start() else { return nil }
        servers[key] = server
        return server
    }

    func stopAll() {
        servers.values.forEach { $0.shutdown() }
        servers.removeAll()
    }

    /// The shell command that installs a server's npm packages, or nil if CodeForge can't install it.
    func installCommand(for spec: LanguageServerSpec) -> String? {
        if let tool = spec.dotnetTool {
            let folder = CommandTemplate.shellQuote(Self.installDirectory.appendingPathComponent("dotnet-tools").path)
            return "dotnet tool update --tool-path \(folder) \(tool) || dotnet tool install --tool-path \(folder) \(tool)"
        }
        guard !spec.npmPackages.isEmpty else { return nil }
        let folder = CommandTemplate.shellQuote(Self.installDirectory.path)
        return "mkdir -p \(folder) && cd \(folder) && npm install --no-fund --no-audit --loglevel=error " + spec.npmPackages.joined(separator: " ")
    }

    private func xcrunFind(_ name: String) -> URL? {
        if let cached = xcrunCache[name] { return cached }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var result: URL?
        if (try? process.run()) != nil {
            let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            process.waitUntilExit()
            if process.terminationStatus == 0, !path.isEmpty { result = URL(fileURLWithPath: path) }
        }
        xcrunCache[name] = result
        return result
    }
}
