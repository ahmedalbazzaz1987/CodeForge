import AppKit
import CodeForgeKit
import Darwin

/// The Output tab: program output, with a field for typing input to the running program.
final class ConsoleView: NSView {
    enum Kind {
        case output, error, warning, info, input

        init(_ line: OutputLineKind) {
            self = switch line {
            case .normal: .output
            case .error: .error
            case .warning: .warning
            }
        }
    }

    var onInput: ((String) -> Void)?
    private let scroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { scroll.documentView as! NSTextView }
    private let input = NSTextField()
    private let inputRow = InputRow()
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

        // The whole row takes the click: a thin text field alone is easy to miss, and Return then goes to the editor.
        let prompt = NSTextField(labelWithString: "›")
        prompt.font = font
        prompt.textColor = Theme.accent
        inputRow.onClick = { [weak self] in self?.focusInput() }
        let separator = NSBox()
        separator.boxType = .separator
        for view in [prompt, input] {
            view.translatesAutoresizingMaskIntoConstraints = false
            inputRow.addSubview(view)
        }
        for view in [scroll, separator, inputRow] {
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
            inputRow.topAnchor.constraint(equalTo: separator.bottomAnchor),
            inputRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: bottomAnchor),
            inputRow.heightAnchor.constraint(equalToConstant: 28),
            prompt.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor, constant: 10),
            prompt.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            input.leadingAnchor.constraint(equalTo: prompt.trailingAnchor, constant: 6),
            input.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -10),
            input.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// A text view laid out while the panel was hidden can keep a narrow width, and the output wraps early.
    override func layout() {
        super.layout()
        let width = scroll.contentSize.width
        if width > 0, abs(textView.frame.width - width) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
    }

    var text: String { textView.string }

    #if DEBUG
    func inputRowPoint(x: CGFloat) -> NSPoint { inputRow.convert(NSPoint(x: x, y: inputRow.bounds.midY), to: nil) }
    /// The lines shown in red or yellow, to check the coloring.
    var debugColoredLines: [String] {
        guard let storage = textView.textStorage else { return [] }
        var lines: [String] = []
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let name = color == .systemRed ? "RED" : color == Theme.warningYellow ? "YELLOW" : nil
            if let name { lines.append(name + ": " + storage.attributedSubstring(from: range).string.prefix(90).trimmingCharacters(in: .newlines)) }
        }
        return lines
    }
    var debugFrames: String { "self \(frame) scroll \(scroll.frame) text \(textView.frame) container \(textView.textContainer?.size ?? .zero)" }
    #endif

    func append(_ text: String, _ kind: Kind = .output) {
        guard let storage = textView.textStorage else { return }
        let color: NSColor = switch kind {
        case .output: Theme.text
        case .error: .systemRed
        case .warning: Theme.warningYellow
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

    /// True while the cursor sits in an empty Input field, so nothing is lost by moving it away.
    var isWaitingInInput: Bool { input.currentEditor() != nil && input.stringValue.isEmpty }

    @objc private func sendInput() {
        let line = input.stringValue
        input.stringValue = ""
        onInput?(line)
    }
}

/// The row around the Input field: a click anywhere in it puts the cursor in the field.
private final class InputRow: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Finds out whether a program is installed, without running it. Knowing before a run gives a clear message instead of
/// a failed command (or macOS's own "Unable to locate a Java Runtime").
enum ToolCheck {
    private static var found = Set<String>()

    static func isAvailable(_ tool: String) -> Bool {
        if found.contains(tool) { return true }
        var available: Bool
        if tool == "java" || tool == "javac" {
            // /usr/bin/java is always there on a Mac, as a stub that only prints that no Java is installed.
            available = succeeds("/usr/libexec/java_home", [])
        } else {
            let folders = (LanguageServerManager.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            available = folders.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + tool) }
            // Installed where only the login shell knows (nvm, pyenv…), or a shell builtin.
            if !available { available = succeeds("/bin/zsh", ["-l", "-c", "command -v \(CommandTemplate.shellQuote(tool))"]) }
        }
        if available { found.insert(tool) }
        return available
    }

    private static func succeeds(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

/// Runs a shell command on a pseudo-terminal and streams its output.
///
/// With a terminal, programs flush every line (so nothing is lost if they crash), and stdout and stderr arrive in the
/// order they were written. The two can't be told apart, so `OutputClassifier` colors lines by what they say.
final class Runner {
    var onOutput: ((String, ConsoleView.Kind) -> Void)?
    var onExit: ((Int32, TimeInterval) -> Void)?
    private var process: Process?
    private var master: Int32 = -1
    private var started = Date()
    private var generation = 0

    var isRunning: Bool { process?.isRunning ?? false }

    func run(_ command: String, in directory: URL) {
        stop()
        var masterFD: Int32 = -1, slaveFD: Int32 = -1
        var size = winsize(ws_row: 50, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&masterFD, &slaveFD, nil, nil, &size) == 0 else {
            onOutput?("Couldn't open a terminal for the command.\n", .error)
            return
        }
        // No echo of what the Input field sends, and no \r added to line ends.
        var settings = termios()
        tcgetattr(slaveFD, &settings)
        settings.c_oflag &= ~tcflag_t(OPOST)
        settings.c_lflag &= ~tcflag_t(ECHO | ECHOE | ECHOK | ECHONL | ECHOCTL)
        tcsetattr(slaveFD, TCSANOW, &settings)

        let process = Process()
        // A login shell picks up the user's PATH (Homebrew, nvm, pyenv, …).
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        // A terminal, but one that doesn't draw: no colors, progress bars or pagers.
        for (name, value) in ["TERM": "dumb", "NO_COLOR": "1", "CLICOLOR": "0", "FORCE_COLOR": "0", "PAGER": "cat", "GIT_PAGER": "cat",
                              "MSBUILDTERMINALLOGGER": "off", "CARGO_TERM_COLOR": "never", "CARGO_TERM_PROGRESS_WHEN": "never",
                              "npm_config_progress": "false", "npm_config_color": "false"] {
            environment[name] = value
        }
        process.environment = environment
        let terminal = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        process.standardOutput = terminal
        process.standardError = terminal
        process.standardInput = terminal

        generation += 1
        let finishedReading = DispatchSemaphore(value: 0)
        read(from: masterFD, generation: generation, finished: finishedReading)
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            // Show everything the program wrote before saying it ended (something it left running can hold
            // the terminal open, so don't wait long).
            DispatchQueue.global().async {
                _ = finishedReading.wait(timeout: .now() + 0.5)
                DispatchQueue.main.async {
                    guard let self, self.process === finished else { return }
                    self.process = nil
                    self.master = -1
                    if finished.terminationReason == .uncaughtSignal, !self.wasStopped, let name = strsignal(status) {
                        self.onOutput?("The program crashed: \(String(cString: name)) (signal \(status)).\n", .error)
                    }
                    self.onExit?(status, Date().timeIntervalSince(self.started))
                }
            }
        }
        do {
            started = Date()
            wasStopped = false
            try process.run()
            self.process = process
            master = masterFD
            close(slaveFD)   // only the program holds it now, so reading ends when the program does
        } catch {
            close(slaveFD)
            close(masterFD)
            process.terminationHandler = nil
            onOutput?("Couldn't start the command: \(error.localizedDescription)\n", .error)
        }
    }

    func send(_ line: String) {
        guard master >= 0, isRunning else { return }
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
    }

    /// Stops the command and everything it started.
    /// True when the last program ended because of the Stop button, not on its own.
    private(set) var wasStopped = false

    func stop() {
        guard let process, process.isRunning else { return }
        wasStopped = true
        let pids = descendants(of: process.processIdentifier)
        process.terminate()
        for pid in pids { kill(pid, SIGTERM) }
    }

    /// Reads the terminal until the program closes it, passing on whole lines (colored by content) as they come, and
    /// unfinished lines too, because a prompt like "Your name? " must show before the program gets its answer.
    private func read(from fd: Int32, generation: Int, finished: DispatchSemaphore) {
        Thread.detachNewThread { [weak self] in
            var decoder = OutputDecoder()
            var buffer = [UInt8](repeating: 0, count: 16384)
            func show(_ pieces: [OutputDecoder.Piece]) {
                if pieces.isEmpty { return }
                DispatchQueue.main.async {
                    guard let self, self.generation == generation else { return }
                    for piece in pieces { self.onOutput?(Runner.stripTerminalCodes(piece.text), ConsoleView.Kind(piece.kind)) }
                }
            }
            while true {
                // Programs often write a line in pieces (dotnet does). Wait a moment for the rest, so the whole line
                // gets its color; if nothing comes it's probably a prompt, and it shows right away.
                var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                if decoder.hasPartialLine, poll(&ready, 1, 40) == 0 {
                    show(decoder.flushPartialLine())
                    continue
                }
                let count = Darwin.read(fd, &buffer, buffer.count)
                guard count > 0 else { break }
                show(decoder.append(Array(buffer[0..<count])))
            }
            close(fd)
            let rest = decoder.finish()
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                for piece in rest { self.onOutput?(Runner.stripTerminalCodes(piece.text), ConsoleView.Kind(piece.kind)) }
            }
            // Queued after the output above, so the exit message comes last.
            DispatchQueue.main.async { finished.signal() }
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
