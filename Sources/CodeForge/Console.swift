import AppKit

/// The Output tab: program output, with a field for typing input to the running program.
final class ConsoleView: NSView {
    enum Kind { case output, error, info, input }

    var onInput: ((String) -> Void)?
    private let scroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { scroll.documentView as! NSTextView }
    private let input = NSTextField()
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    override init(frame: NSRect) {
        super.init(frame: frame)
        textView.isEditable = false
        textView.isRichText = false
        textView.font = font
        textView.backgroundColor = Theme.background
        textView.textContainerInset = NSSize(width: 6, height: 6)
        scroll.borderType = .noBorder

        input.placeholderString = "Input for the running program — press Return to send"
        input.font = font
        input.isBordered = false
        input.focusRingType = .none
        input.drawsBackground = false
        input.target = self
        input.action = #selector(sendInput)

        let separator = NSBox()
        separator.boxType = .separator
        for view in [scroll, separator, input] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            input.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            input.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            input.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            input.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
    }

    var text: String { textView.string }

    func append(_ text: String, _ kind: Kind = .output) {
        guard let storage = textView.textStorage else { return }
        let color: NSColor = switch kind {
        case .output: Theme.text
        case .error: .systemRed
        case .info: Theme.gutterText
        case .input: .systemGreen
        }
        let clip = scroll.contentView
        let atBottom = clip.bounds.maxY >= textView.bounds.maxY - 20
        storage.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        if storage.length > 2_000_000 {   // keep memory bounded for chatty programs
            storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - 1_500_000))
        }
        if atBottom { textView.scrollToEndOfDocument(nil) }
    }

    @objc func clear(_ sender: Any?) {
        textView.string = ""
    }

    func focusInput() {
        window?.makeFirstResponder(input)
    }

    @objc private func sendInput() {
        let line = input.stringValue
        input.stringValue = ""
        onInput?(line)
    }
}

/// Runs a shell command and streams its output.
final class Runner {
    var onOutput: ((String, ConsoleView.Kind) -> Void)?
    var onExit: ((Int32, TimeInterval) -> Void)?
    private var process: Process?
    private var stdin: FileHandle?
    private var started = Date()

    var isRunning: Bool { process?.isRunning ?? false }

    func run(_ command: String, in directory: URL) {
        stop()
        let process = Process()
        // A login shell picks up the user's PATH (Homebrew, nvm, pyenv, …).
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment

        let output = Pipe(), errors = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input
        stream(output, as: .output)
        stream(errors, as: .error)
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            // Let the last output chunks reach the main queue first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let self, self.process === finished else { return }
                self.process = nil
                self.stdin = nil
                self.onExit?(status, Date().timeIntervalSince(self.started))
            }
        }
        do {
            started = Date()
            try process.run()
            self.process = process
            stdin = input.fileHandleForWriting
        } catch {
            onOutput?("Couldn't start the command: \(error.localizedDescription)\n", .error)
        }
    }

    func send(_ line: String) {
        guard let stdin else { return }
        try? stdin.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Stops the command and everything it started.
    func stop() {
        guard let process, process.isRunning else { return }
        let pids = descendants(of: process.processIdentifier)
        process.terminate()
        for pid in pids { kill(pid, SIGTERM) }
    }

    private func stream(_ pipe: Pipe, as kind: ConsoleView.Kind) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = Runner.stripTerminalCodes(String(decoding: data, as: UTF8.self))
            DispatchQueue.main.async { self?.onOutput?(text, kind) }
        }
    }

    private static let terminalCodes = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]")

    /// Removes color and cursor escape codes that tools print even without a terminal.
    static func stripTerminalCodes(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        return terminalCodes.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }

    private func descendants(of root: pid_t) -> [pid_t] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-A", "-o", "pid=,ppid="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        var children: [pid_t: [pid_t]] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ").compactMap { pid_t($0) }
            if fields.count == 2 { children[fields[1], default: []].append(fields[0]) }
        }
        var result: [pid_t] = []
        var queue = [root]
        while let pid = queue.popLast() {
            for child in children[pid] ?? [] {
                result.append(child)
                queue.append(child)
            }
        }
        return result
    }
}
