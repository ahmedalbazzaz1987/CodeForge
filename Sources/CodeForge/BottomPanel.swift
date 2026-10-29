import AppKit
import CodeForgeKit

/// The docked panel under the editor: Output, Error List and Terminal tabs.
final class BottomPanel: NSView {
    enum Tab: Int, CaseIterable {
        case output, errors, terminal
        var title: String { ["Output", "Error List", "Terminal"][rawValue] }
    }

    let output = ConsoleView()
    let errors = ErrorListView()
    let terminal = TerminalView()
    var onHide: (() -> Void)?
    private(set) var selected: Tab = .output
    private var tabButtons: [NSButton] = []
    private let content = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        for tab in Tab.allCases {
            let button = NSButton(title: tab.title, target: self, action: #selector(tabClicked(_:)))
            button.tag = tab.rawValue
            button.isBordered = false
            button.font = .systemFont(ofSize: 11, weight: .medium)
            tabButtons.append(button)
        }
        let clear = FileTreeView.iconButton("trash", "Clear", #selector(clearCurrent), self)
        let hide = FileTreeView.iconButton("xmark", "Hide Panel", #selector(hideClicked), self)
        let header = NSStackView(views: tabButtons + [NSView(), clear, hide])
        header.spacing = 16
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)

        for view in [header, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 28),
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        show(.output)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ tab: Tab) {
        selected = tab
        content.subviews.forEach { $0.removeFromSuperview() }
        let view: NSView = [output, errors, terminal][tab.rawValue]
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        if tab == .terminal { terminal.startIfNeeded() }
        updateTabTitles()
        needsDisplay = true
    }

    func updateTabTitles() {
        for button in tabButtons {
            let tab = Tab(rawValue: button.tag)!
            var title = tab.title
            if tab == .errors, errors.count > 0 { title += "  \(errors.count)" }
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: tab == selected ? .semibold : .regular),
                .foregroundColor: tab == selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ])
        }
    }

    @objc private func tabClicked(_ sender: NSButton) { show(Tab(rawValue: sender.tag)!) }
    @objc private func hideClicked() { onHide?() }

    @objc private func clearCurrent() {
        switch selected {
        case .output: output.clear(nil)
        case .errors: errors.set([], folder: nil)
        case .terminal: terminal.clear()
        }
        updateTabTitles()
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        Theme.separator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        // Underline the selected tab.
        if let button = tabButtons.first(where: { $0.tag == selected.rawValue }) {
            let frame = convert(button.bounds, from: button)
            Theme.accent.setFill()
            NSRect(x: frame.minX, y: bounds.maxY - 28, width: frame.width, height: 2).fill()
        }
    }

    override var isFlipped: Bool { false }
}

/// The Error List tab: errors and warnings parsed from the last run. Double-click to go to the line.
final class ErrorListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onOpen: ((URL, Diagnostic) -> Void)?
    private(set) var diagnostics: [Diagnostic] = []
    private var folder: URL?
    private let table = NSTableView()
    private let empty = NSTextField(labelWithString: "No errors or warnings.")

    var count: Int { diagnostics.count }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (id, title, width) in [("icon", "", 24.0), ("message", "Description", 520.0), ("file", "File", 180.0), ("line", "Line", 50.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "icon" ? 24 : 40
            table.addTableColumn(column)
        }
        table.style = .plain
        table.rowHeight = 20
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        empty.textColor = .secondaryLabelColor
        for view in [scroll, empty] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func set(_ diagnostics: [Diagnostic], folder: URL?) {
        self.diagnostics = diagnostics
        self.folder = folder
        empty.isHidden = !diagnostics.isEmpty
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { diagnostics.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let diagnostic = diagnostics[row]
        switch column?.identifier.rawValue {
        case "icon":
            let isError = diagnostic.severity == .error
            let image = NSImageView(image: NSImage(systemSymbolName: isError ? "xmark.circle.fill" : "exclamationmark.triangle.fill",
                                                   accessibilityDescription: diagnostic.severity.rawValue)!)
            image.contentTintColor = isError ? Theme.errorRed : Theme.warningYellow
            return image
        case "message": return label(diagnostic.message)
        case "file": return label((diagnostic.file as NSString).lastPathComponent, secondary: true)
        default: return label("\(diagnostic.line)", secondary: true)
        }
    }

    private func label(_ text: String, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = text
        return field
    }

    @objc private func openSelected() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard diagnostics.indices.contains(row), let folder else { return }
        onOpen?(diagnostics[row].url(relativeTo: folder), diagnostics[row])
    }
}

/// The Terminal tab: a zsh session for one-line commands (`git status`, `npm install`, `ls`, …).
/// It has no pseudo-terminal, so full-screen programs such as vim or top don't work here.
final class TerminalView: NSView {
    private let scroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { scroll.documentView as! NSTextView }
    private let prompt = NSTextField(labelWithString: "%")
    private let input = NSTextField()
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var shell: Process?
    private var stdin: FileHandle?
    private var history: [String] = []
    private var historyIndex = 0
    private var pending = ""
    private static let marker = "\u{1E}CWD:"
    var directory: URL = FileManager.default.homeDirectoryForCurrentUser {
        didSet { if shell != nil, oldValue != directory { send("cd \(CommandTemplate.shellQuote(directory.path))", echo: false) } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        textView.isEditable = false
        textView.font = font
        textView.backgroundColor = Theme.background
        textView.textContainerInset = NSSize(width: 6, height: 6)
        scroll.borderType = .noBorder
        prompt.font = font
        prompt.textColor = Theme.accent
        input.font = font
        input.isBordered = false
        input.focusRingType = .none
        input.drawsBackground = false
        input.placeholderString = "Type a command and press Return (↑ for history)"
        input.target = self
        input.action = #selector(submit)
        input.delegate = self
        let interrupt = FileTreeView.iconButton("stop.circle", "Interrupt (Ctrl-C)", #selector(interruptCommand), self)
        let row = NSStackView(views: [prompt, input, interrupt])
        row.spacing = 6
        let separator = NSBox()
        separator.boxType = .separator
        for view in [scroll, separator, row] {
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
            row.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
    }

    func startIfNeeded() {
        window?.makeFirstResponder(input)
        guard shell == nil || shell?.isRunning == false else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l"]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["PAGER"] = "cat"
        environment["GIT_PAGER"] = "cat"
        process.environment = environment
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = input
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.receive(text) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.append("\n[Shell exited — press Return to start a new one]\n", color: .secondaryLabelColor) }
        }
        do {
            try process.run()
            shell = process
            stdin = input.fileHandleForWriting
            send("", echo: false)   // prints the first prompt
        } catch {
            append("Couldn't start zsh: \(error.localizedDescription)\n", color: .systemRed)
        }
    }

    func clear() { textView.string = "" }

    private func send(_ command: String, echo: Bool) {
        if echo { append("\(prompt.stringValue) \(command)\n", color: Theme.accent) }
        let line = command + "\nprintf '\\n\(Self.marker)%s\\n' \"$PWD\"\n"
        try? stdin?.write(contentsOf: Data(line.utf8))
    }

    /// Splits out the marker lines that report the shell's current folder after each command.
    private func receive(_ text: String) {
        pending += text
        while let range = pending.range(of: Self.marker) {
            guard let end = pending[range.upperBound...].firstIndex(of: "\n") else { break }
            var before = String(pending[..<range.lowerBound])
            if before.hasSuffix("\n") { before.removeLast() }   // the newline printf added
            append(before, color: Theme.text)
            let cwd = String(pending[range.upperBound..<end])
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            prompt.stringValue = (cwd == home ? "~" : (cwd as NSString).lastPathComponent) + " %"
            pending = String(pending[pending.index(after: end)...])
        }
        // Show output that can't be part of a marker right away.
        if !pending.contains("\u{1E}") {
            append(pending, color: Theme.text)
            pending = ""
        }
    }

    private func append(_ text: String, color: NSColor) {
        guard !text.isEmpty, let storage = textView.textStorage else { return }
        storage.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        if storage.length > 1_000_000 { storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - 800_000)) }
        textView.scrollToEndOfDocument(nil)
    }

    @objc private func submit() {
        let command = input.stringValue
        input.stringValue = ""
        if shell?.isRunning != true { startIfNeeded() }
        if command == "clear" { return clear() }
        if !command.isEmpty, history.last != command { history.append(command) }
        historyIndex = history.count
        send(command, echo: true)
    }

    @objc private func interruptCommand() {
        guard let shell, shell.isRunning else { return }
        // Interrupt what the shell is running, not the shell itself.
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        ps.arguments = ["-INT", "-P", String(shell.processIdentifier)]
        try? ps.run()
        append("^C\n", color: .secondaryLabelColor)
    }

    func stop() { shell?.terminate() }

    var inputField: NSTextField { input }
}

extension TerminalView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !history.isEmpty else { return false }
        if selector == #selector(NSResponder.moveUp(_:)) {
            historyIndex = max(historyIndex - 1, 0)
        } else if selector == #selector(NSResponder.moveDown(_:)) {
            historyIndex = min(historyIndex + 1, history.count)
        } else {
            return false
        }
        input.stringValue = historyIndex < history.count ? history[historyIndex] : ""
        input.currentEditor()?.moveToEndOfDocument(nil)
        return true
    }
}
