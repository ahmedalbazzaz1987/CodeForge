import AppKit
import CodeForgeKit

/// Talks to a Debug Adapter Protocol server (Xcode's `lldb-dap`) over its stdin and stdout.
final class DebugAdapter {
    var onEvent: ((String, [String: Any]) -> Void)?
    var onExit: (() -> Void)?
    private let process = Process()
    private var stdin: FileHandle?
    private var buffer = LSPMessageBuffer()   // DAP uses the same Content-Length framing as LSP
    private var sequence = 1
    private var pending: [Int: ([String: Any]) -> Void] = [:]

    static func executable() -> URL? {
        let finder = Process()
        finder.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        finder.arguments = ["--find", "lldb-dap"]
        let pipe = Pipe()
        finder.standardOutput = pipe
        finder.standardError = FileHandle.nullDevice
        guard (try? finder.run()) != nil else { return nil }
        let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        finder.waitUntilExit()
        return finder.terminationStatus == 0 && !path.isEmpty ? URL(fileURLWithPath: path) : nil
    }

    func start(_ executable: URL, arguments: [String] = [], environment: [String: String]? = nil) -> Bool {
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.onExit?() } }
        guard (try? process.run()) != nil else { return false }
        stdin = input.fileHandleForWriting
        return true
    }

    func request(_ command: String, _ arguments: [String: Any] = [:], completion: (([String: Any]) -> Void)? = nil) {
        let seq = sequence
        sequence += 1
        if let completion { pending[seq] = completion }
        write(["seq": seq, "type": "request", "command": command, "arguments": arguments])
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    private func write(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        try? stdin?.write(contentsOf: LSPMessageBuffer.frame(data))
    }

    private func receive(_ data: Data) {
        for body in buffer.append(data) {
            guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { continue }
            switch message["type"] as? String {
            case "response":
                if let seq = message["request_seq"] as? Int { pending.removeValue(forKey: seq)?(message) }
            case "event":
                onEvent?(message["event"] as? String ?? "", message["body"] as? [String: Any] ?? [:])
            case "request":
                // Reverse requests (e.g. runInTerminal) aren't supported; say so.
                write(["seq": sequence, "type": "response", "request_seq": message["seq"] ?? 0, "success": false,
                       "command": message["command"] ?? "", "message": "not supported"])
                sequence += 1
            default: break
            }
        }
    }
}

/// Which debug adapter to start and how to launch the program with it.
struct DebugConfiguration {
    let adapter: URL
    var adapterArguments: [String] = []
    var environment: [String: String]?
    let adapterID: String
    let launch: [String: Any]
    /// LLDB needs macOS's permission to control another process; debugpy doesn't.
    var needsDeveloperAccess = false

    /// Compiled programs (C, C++, Objective-C, Swift, Rust, Go) with Xcode's lldb-dap.
    static func lldb(program: URL, folder: URL) -> DebugConfiguration? {
        guard let adapter = DebugAdapter.executable() else { return nil }
        return DebugConfiguration(adapter: adapter, adapterID: "lldb-dap",
                                  launch: ["program": program.path, "args": [String](), "cwd": folder.path, "stopOnEntry": false],
                                  needsDeveloperAccess: true)
    }

    /// Python scripts with debugpy, installed into CodeForge's own folder.
    static func python(file: URL, folder: URL) -> DebugConfiguration? {
        guard let python = PythonDebugging.python, PythonDebugging.isInstalled else { return nil }
        var environment = LanguageServerManager.environment
        environment["PYTHONPATH"] = PythonDebugging.installDirectory.path
        return DebugConfiguration(adapter: python, adapterArguments: ["-m", "debugpy.adapter"], environment: environment, adapterID: "debugpy",
                                  launch: ["type": "python", "request": "launch", "program": file.path, "cwd": folder.path,
                                           "python": python.path, "console": "internalConsole", "justMyCode": true,
                                           "redirectOutput": true, "stopOnEntry": false, "env": ["PYTHONUNBUFFERED": "1"]])
    }
}

/// Finding Python and installing debugpy for Python debugging.
enum PythonDebugging {
    static let installDirectory = LanguageServerManager.installDirectory.deletingLastPathComponent().appendingPathComponent("debugpy")

    static var python: URL? {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installDirectory.appendingPathComponent("debugpy/__init__.py").path)
    }

    /// Installs debugpy for the same Python that will run the program.
    static var installCommand: String? {
        python.map { "\(CommandTemplate.shellQuote($0.path)) -m pip install --disable-pip-version-check --upgrade --target \(CommandTemplate.shellQuote(installDirectory.path)) debugpy" }
    }
}

/// One debugging run: launches the program under a debug adapter and tracks where it stopped.
final class DebugSession {
    struct Frame {
        let id: Int
        let name: String
        let file: URL?
        let line: Int
    }

    enum State { case starting, running, paused, ended }

    private let adapter = DebugAdapter()
    private(set) var state: State = .starting { didSet { onStateChange?() } }
    private(set) var threadId = 0
    private(set) var frames: [Frame] = []
    private(set) var stopReason = ""
    let configuration: DebugConfiguration
    var breakpoints: () -> [URL: Set<Int>] = { [:] }

    var onStateChange: (() -> Void)?
    var onOutput: ((String, ConsoleView.Kind) -> Void)?
    var onStopped: (() -> Void)?

    init(_ configuration: DebugConfiguration) {
        self.configuration = configuration
    }

    func start() -> Bool {
        guard adapter.start(configuration.adapter, arguments: configuration.adapterArguments, environment: configuration.environment) else { return false }
        adapter.onEvent = { [weak self] event, body in self?.handle(event, body) }
        adapter.onExit = { [weak self] in self?.state = .ended }
        adapter.request("initialize", [
            "clientID": "codeforge", "clientName": "CodeForge", "adapterID": configuration.adapterID,
            "linesStartAt1": true, "columnsStartAt1": true, "pathFormat": "path",
            "supportsVariableType": true, "supportsRunInTerminalRequest": false,
        ])
        // macOS asks for permission the first time a debugger controls a program; explain if the launch stalls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, state == .starting, configuration.needsDeveloperAccess else { return }
            onOutput?("""

                The debugger is waiting for macOS to allow it to control the program.
                • Look for a password prompt (“Developer Tools Access”) and approve it, or
                • run this once in Terminal, then start debugging again:  sudo DevToolsSecurity -enable

                """, .error)
        }
        adapter.request("launch", configuration.launch) { [weak self] response in
            if response["success"] as? Bool == false {
                self?.onOutput?("Couldn't start debugging: \(response["message"] as? String ?? "unknown error")\n", .error)
                self?.stop()
            }
        }
        return true
    }

    private func handle(_ event: String, _ body: [String: Any]) {
        switch event {
        case "initialized":
            sendAllBreakpoints()
            adapter.request("configurationDone")
            state = .running
        case "stopped":
            threadId = body["threadId"] as? Int ?? threadId
            stopReason = body["description"] as? String ?? body["reason"] as? String ?? "paused"
            loadFrames()
        case "continued":
            frames = []
            state = .running
        case "output":
            guard let text = body["output"] as? String else { return }
            let category = body["category"] as? String ?? "console"
            if category == "telemetry" { return }   // adapter-internal events (debugpy sends "ptvsd", "debugpy")
            onOutput?(text, category == "stderr" ? .error : category == "stdout" ? .output : .info)
        case "exited":
            let code = body["exitCode"] as? Int ?? 0
            onOutput?("\n[Program exited with code \(code)]\n", code == 0 ? .info : .error)
        case "terminated":
            stop()
        default: break
        }
    }

    private func loadFrames() {
        adapter.request("stackTrace", ["threadId": threadId, "startFrame": 0, "levels": 60]) { [weak self] response in
            guard let self else { return }
            let list = (response["body"] as? [String: Any])?["stackFrames"] as? [[String: Any]] ?? []
            frames = list.map { frame in
                let path = (frame["source"] as? [String: Any])?["path"] as? String
                return Frame(id: frame["id"] as? Int ?? 0, name: frame["name"] as? String ?? "?",
                             file: path.map { URL(fileURLWithPath: $0) }, line: frame["line"] as? Int ?? 0)
            }
            state = .paused
            onStopped?()
        }
    }

    func sendBreakpoints(for file: URL, lines: Set<Int>) {
        guard state != .ended else { return }
        adapter.request("setBreakpoints", [
            "source": ["path": file.path, "name": file.lastPathComponent],
            "breakpoints": lines.sorted().map { ["line": $0] },
        ])
    }

    private func sendAllBreakpoints() {
        for (file, lines) in breakpoints() { sendBreakpoints(for: file, lines: lines) }
    }

    /// The variables in a frame's first scope (usually "Locals").
    func locals(frame: Int, completion: @escaping ([Variable]) -> Void) {
        adapter.request("scopes", ["frameId": frame]) { [weak self] response in
            let scopes = (response["body"] as? [String: Any])?["scopes"] as? [[String: Any]] ?? []
            guard let reference = scopes.first?["variablesReference"] as? Int, reference > 0 else { return completion([]) }
            self?.variables(reference, completion: completion)
        }
    }

    func variables(_ reference: Int, completion: @escaping ([Variable]) -> Void) {
        adapter.request("variables", ["variablesReference": reference]) { response in
            let list = (response["body"] as? [String: Any])?["variables"] as? [[String: Any]] ?? []
            completion(list.map { Variable(name: $0["name"] as? String ?? "", value: $0["value"] as? String ?? "",
                                           type: $0["type"] as? String ?? "", reference: $0["variablesReference"] as? Int ?? 0) })
        }
    }

    func evaluate(_ expression: String, frame: Int?, completion: @escaping (String) -> Void) {
        // "watch" evaluates the text as an expression and returns just the value ("30", not "(int) $0 = 30").
        var arguments: [String: Any] = ["expression": expression, "context": "watch"]
        if let frame { arguments["frameId"] = frame }
        adapter.request("evaluate", arguments) { response in
            if response["success"] as? Bool == false {
                completion("error: " + (response["message"] as? String ?? "can't evaluate"))
            } else {
                completion((response["body"] as? [String: Any])?["result"] as? String ?? "")
            }
        }
    }

    func resume() { command("continue") }
    func stepOver() { command("next") }
    func stepInto() { command("stepIn") }
    func stepOut() { command("stepOut") }
    func pause() { adapter.request("pause", ["threadId": threadId]) }

    private func command(_ name: String) {
        guard state == .paused else { return }
        state = .running
        frames = []
        adapter.request(name, ["threadId": threadId])
    }

    func stop() {
        guard state != .ended else { return }
        adapter.request("disconnect", ["terminateDebuggee": true])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [adapter] in adapter.terminate() }
        state = .ended
    }
}

/// A variable shown in the Locals tree. `reference` > 0 means it has children.
final class Variable {
    let name: String
    let value: String
    let type: String
    let reference: Int
    var children: [Variable]?

    init(name: String, value: String, type: String, reference: Int) {
        self.name = name
        self.value = value
        self.type = type
        self.reference = reference
    }
}

/// The Debug tab: Locals on the left, Call Stack on the right, and an expression field.
final class DebugPanel: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    weak var session: DebugSession?
    var onSelectFrame: ((DebugSession.Frame) -> Void)?
    var onEvaluate: ((String) -> Void)?
    private let locals = NSOutlineView()
    private let stack = NSTableView()
    private let expression = NSTextField()
    private let result = NSTextField(labelWithString: "")
    private var variables: [Variable] = []
    private var frames: [DebugSession.Frame] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (id, title, width) in [("name", "Name", 160.0), ("value", "Value", 220.0), ("type", "Type", 120.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            locals.addTableColumn(column)
            if id == "name" { locals.outlineTableColumn = column }
        }
        locals.style = .plain
        locals.rowHeight = 19
        locals.usesAlternatingRowBackgroundColors = true
        locals.dataSource = self
        locals.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("frame"))
        column.title = "Call Stack"
        stack.addTableColumn(column)
        stack.style = .plain
        stack.rowHeight = 19
        stack.dataSource = self
        stack.delegate = self
        stack.target = self
        stack.action = #selector(frameClicked)

        expression.placeholderString = "Expression to evaluate, for example: count * 2"
        expression.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        expression.target = self
        expression.action = #selector(evaluate)

        let localsScroll = NSScrollView(), stackScroll = NSScrollView()
        localsScroll.documentView = locals
        localsScroll.hasVerticalScroller = true
        stackScroll.documentView = stack
        stackScroll.hasVerticalScroller = true
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(localsScroll)
        split.addArrangedSubview(stackScroll)
        result.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        result.textColor = Theme.accent
        result.lineBreakMode = .byTruncatingTail
        result.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let evaluateButton = NSButton(title: "Evaluate", target: self, action: #selector(evaluate))
        evaluateButton.controlSize = .small
        for view in [split, expression, evaluateButton, result] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: topAnchor),
            split.leadingAnchor.constraint(equalTo: leadingAnchor),
            split.trailingAnchor.constraint(equalTo: trailingAnchor),
            expression.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 4),
            expression.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            expression.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            evaluateButton.leadingAnchor.constraint(equalTo: expression.trailingAnchor, constant: 6),
            evaluateButton.centerYAnchor.constraint(equalTo: expression.centerYAnchor),
            result.leadingAnchor.constraint(equalTo: evaluateButton.trailingAnchor, constant: 10),
            result.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            result.centerYAnchor.constraint(equalTo: expression.centerYAnchor),
            expression.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            localsScroll.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(frames: [DebugSession.Frame], selected: Int, variables: [Variable]) {
        self.frames = frames
        self.variables = variables
        stack.reloadData()
        if frames.indices.contains(selected) { stack.selectRowIndexes([selected], byExtendingSelection: false) }
        locals.reloadData()
    }

    func showResult(_ text: String) {
        result.stringValue = "= " + text
        result.toolTip = text
    }

    func clear() {
        result.stringValue = ""
        show(frames: [], selected: -1, variables: [])
    }

    @objc private func frameClicked() {
        guard frames.indices.contains(stack.selectedRow) else { return }
        onSelectFrame?(frames[stack.selectedRow])
    }

    @objc private func evaluate() {
        let text = expression.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onEvaluate?(text)
    }

    // Locals

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let variable = item as? Variable else { return variables.count }
        return variable.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Variable)?.children?[index] ?? variables[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        ((item as? Variable)?.reference ?? 0) > 0
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let variable = notification.userInfo?["NSObject"] as? Variable, variable.children == nil else { return }
        variable.children = []
        session?.variables(variable.reference) { [weak self] children in
            variable.children = children
            self?.locals.reloadItem(variable, reloadChildren: true)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let variable = item as? Variable else { return nil }
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "name": text = variable.name
        case "value": text = variable.value
        default: text = variable.type
        }
        let field = NSTextField(labelWithString: text)
        field.font = tableColumn?.identifier.rawValue == "type" ? .systemFont(ofSize: 11) : .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        field.textColor = tableColumn?.identifier.rawValue == "type" ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = text
        return field
    }

    // Call stack

    func numberOfRows(in tableView: NSTableView) -> Int { frames.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let frame = frames[row]
        let location = frame.file.map { " — \($0.lastPathComponent):\(frame.line)" } ?? ""
        let field = NSTextField(labelWithString: frame.name + location)
        field.font = .systemFont(ofSize: 12)
        field.textColor = frame.file == nil ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

/// The strip of debug buttons shown above the editor while debugging.
final class DebugBar: NSView {
    private let status = NSTextField(labelWithString: "")
    private let continueButton: NSButton
    private let pauseButton: NSButton
    private var stepButtons: [NSButton] = []

    init(target: AnyObject) {
        func button(_ symbol: String, _ tip: String, _ action: String, _ color: NSColor? = nil) -> NSButton {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: target, action: NSSelectorFromString(action))
            button.isBordered = false
            button.toolTip = tip
            button.contentTintColor = color ?? .labelColor
            return button
        }
        continueButton = button("play.fill", "Continue (F5)", "debugContinue:", .systemGreen)
        pauseButton = button("pause.fill", "Pause", "debugPause:")
        stepButtons = [
            button("arrow.uturn.right", "Step Over (F10)", "debugStepOver:"),
            button("arrow.down.to.line", "Step Into (F11)", "debugStepInto:"),
            button("arrow.up.to.line", "Step Out (⇧F11)", "debugStepOut:"),
        ]
        super.init(frame: .zero)
        let stop = button("stop.fill", "Stop Debugging (⇧F5)", "stopDebugging:", .systemRed)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [continueButton, pauseButton] + stepButtons + [stop, status])
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(_ state: DebugSession.State, reason: String) {
        let paused = state == .paused
        continueButton.isEnabled = paused
        pauseButton.isEnabled = state == .running
        stepButtons.forEach { $0.isEnabled = paused }
        status.stringValue = switch state {
        case .starting: "Starting…"
        case .running: "Running"
        case .paused: "Paused — " + reason
        case .ended: "Ended"
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        Theme.statusBusy.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
    }
}
