import AppKit
import CodeForgeKit

/// Runs git commands in a folder, off the main thread.
enum Git {
    struct Result {
        let status: Int32
        let output: String
        let error: String
        var succeeded: Bool { status == 0 }
    }

    static func run(_ arguments: [String], in folder: URL, completion: @escaping (Result) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runNow(arguments, in: folder)
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func runNow(_ arguments: [String], in folder: URL) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        var environment = LanguageServerManager.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"   // fail instead of waiting for a password nobody can type
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { return Result(status: -1, output: "", error: error.localizedDescription) }
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: outData, as: UTF8.self),
                      error: String(decoding: errData, as: UTF8.self))
    }
}

/// The right sidebar: Explorer and Git Changes, switched with a segmented control.
final class SidebarView: NSView {
    let explorer: FileTreeView
    let git = GitChangesView()
    private let switcher = NSSegmentedControl(labels: ["Explorer", "Git Changes"], trackingMode: .selectOne, target: nil, action: nil)
    private let content = NSView()

    init(explorer: FileTreeView) {
        self.explorer = explorer
        super.init(frame: .zero)
        switcher.target = self
        switcher.action = #selector(switched)
        switcher.selectedSegment = 0
        switcher.controlSize = .small
        switcher.segmentDistribution = .fillEqually
        for view in [switcher, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            switcher.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            switcher.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            switcher.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: switcher.bottomAnchor, constant: 4),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        show(0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var showsGit: Bool { switcher.selectedSegment == 1 }

    func show(_ index: Int) {
        switcher.selectedSegment = index
        content.subviews.forEach { $0.removeFromSuperview() }
        let view: NSView = index == 0 ? explorer : git
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        if index == 1 { git.refresh() }
    }

    @objc private func switched() { show(switcher.selectedSegment) }

    override func draw(_ dirtyRect: NSRect) {
        Theme.sidebar.setFill()
        bounds.fill()
    }
}

/// Git Changes: branch, commit message, staged and unstaged files, and sync with the remote.
final class GitChangesView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    var folder: URL? { didSet { refresh() } }
    /// Opens a read-only tab (title, text, language id).
    var onShowText: ((String, String, String) -> Void)?
    var onOpenFile: ((URL) -> Void)?
    var onStatusChange: ((GitStatus?) -> Void)?
    var onMessage: ((String) -> Void)?

    private(set) var status: GitStatus?
    private var isRepository = false
    private var rows: [Row] = []
    private enum Row { case header(String), change(GitChange) }

    private let branchMenu = NSPopUpButton()
    private let syncLabel = NSTextField(labelWithString: "")
    private let message = NSTextView()
    private let commitButton = NSButton(title: "Commit All", target: nil, action: nil)
    private let table = NSTableView()
    private let content = NSStackView()
    private let notRepository = NSStackView()
    private var busy = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        branchMenu.controlSize = .small
        branchMenu.font = .systemFont(ofSize: 11)
        branchMenu.target = self
        branchMenu.action = #selector(branchChosen)
        syncLabel.font = .systemFont(ofSize: 11)
        syncLabel.textColor = .secondaryLabelColor
        syncLabel.lineBreakMode = .byTruncatingTail
        syncLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let fetch = FileTreeView.iconButton("arrow.triangle.2.circlepath", "Fetch", #selector(fetch), self)
        let pull = FileTreeView.iconButton("arrow.down", "Pull", #selector(pull), self)
        let push = FileTreeView.iconButton("arrow.up", "Push", #selector(push), self)
        let history = FileTreeView.iconButton("clock.arrow.circlepath", "View History", #selector(showHistory), self)
        let refreshButton = FileTreeView.iconButton("arrow.clockwise", "Refresh", #selector(refreshClicked), self)
        let branchRow = NSStackView(views: [branchMenu, syncLabel, NSView(), fetch, pull, push, history, refreshButton])
        branchRow.spacing = 8

        message.font = .systemFont(ofSize: 12)
        message.isRichText = false
        message.delegate = self
        message.textContainerInset = NSSize(width: 4, height: 4)
        message.backgroundColor = Theme.background
        let messageScroll = NSScrollView()
        messageScroll.documentView = message
        messageScroll.hasVerticalScroller = true
        messageScroll.borderType = .bezelBorder
        message.autoresizingMask = [.width]
        message.isVerticallyResizable = true
        message.textContainer?.widthTracksTextView = true
        let placeholder = NSTextField(labelWithString: "Enter a message")
        placeholder.textColor = .placeholderTextColor
        placeholder.font = .systemFont(ofSize: 12)
        placeholder.identifier = NSUserInterfaceItemIdentifier("placeholder")

        commitButton.target = self
        commitButton.action = #selector(commit)
        commitButton.controlSize = .small
        commitButton.bezelColor = Theme.accent
        commitButton.keyEquivalent = ""

        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("change")))
        table.headerView = nil
        table.rowHeight = 22
        table.style = .plain
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openDiff)
        let menu = NSMenu()
        menu.addItem(withTitle: "Open File", action: #selector(openFile), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Compare with Unmodified", action: #selector(openDiff), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Undo Changes…", action: #selector(discardChanges), keyEquivalent: "").target = self
        table.menu = menu
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.drawsBackground = false

        content.setViews([branchRow, messageScroll, commitButton, tableScroll], in: .top)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 0, right: 8)
        messageScroll.addSubview(placeholder)
        NSLayoutConstraint.activate([
            branchRow.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -18),
            messageScroll.widthAnchor.constraint(equalTo: branchRow.widthAnchor),
            messageScroll.heightAnchor.constraint(equalToConstant: 58),
            commitButton.widthAnchor.constraint(equalTo: branchRow.widthAnchor),
            tableScroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            branchMenu.widthAnchor.constraint(lessThanOrEqualToConstant: 140),
            branchMenu.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
        placeholder.frame.origin = NSPoint(x: 8, y: 6)   // the scroll view is flipped

        let note = NSTextField(wrappingLabelWithString: "This folder isn't a Git repository yet.")
        note.textColor = .secondaryLabelColor
        note.alignment = .center
        let create = NSButton(title: "Create Git Repository", target: self, action: #selector(initRepository))
        notRepository.setViews([note, create], in: .center)
        notRepository.orientation = .vertical
        notRepository.spacing = 10

        for view in [content, notRepository] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            notRepository.centerXAnchor.constraint(equalTo: centerXAnchor),
            notRepository.centerYAnchor.constraint(equalTo: centerYAnchor),
            notRepository.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
        ])
        showRepositoryState()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func textDidChange(_ notification: Notification) {
        message.enclosingScrollView?.subviews.first { $0.identifier?.rawValue == "placeholder" }?.isHidden = !message.string.isEmpty
    }

    // MARK: Status

    @objc private func refreshClicked() { refresh() }

    func refresh() {
        guard let folder else {
            status = nil
            isRepository = false
            showRepositoryState()
            onStatusChange?(nil)
            return
        }
        Git.run(["status", "--porcelain=v1", "--branch", "--untracked-files=all"], in: folder) { [weak self] result in
            guard let self, self.folder == folder else { return }
            isRepository = result.succeeded
            status = result.succeeded ? GitStatus.parse(result.output) : nil
            showRepositoryState()
            onStatusChange?(status)
        }
        Git.run(["branch", "--format=%(refname:short)"], in: folder) { [weak self] result in
            guard let self, result.succeeded else { return }
            let branches = result.output.split(separator: "\n").map(String.init)
            branchMenu.removeAllItems()
            branchMenu.addItems(withTitles: branches.isEmpty ? [status?.branch ?? "main"] : branches)
            branchMenu.menu?.addItem(.separator())
            branchMenu.addItem(withTitle: "New Branch…")
            if let branch = status?.branch { branchMenu.selectItem(withTitle: branch) }
        }
    }

    private func showRepositoryState() {
        content.isHidden = !isRepository
        notRepository.isHidden = isRepository || folder == nil
        guard let status else { rows = []; table.reloadData(); return }
        let staged = status.changes.filter(\.isStaged)
        let unstaged = status.changes.filter { !$0.isStaged || $0.unstaged != " " }
        rows = []
        if !staged.isEmpty { rows += [.header("Staged Changes (\(staged.count))")] + staged.map(Row.change) }
        if !unstaged.isEmpty {
            rows += [.header("Changes (\(unstaged.count))")]
            rows += unstaged.map { Row.change(GitChange(staged: $0.isUntracked ? "?" : " ", unstaged: $0.isUntracked ? "?" : $0.unstaged,
                                                         path: $0.path, originalPath: $0.originalPath)) }
        }
        if rows.isEmpty { rows = [.header("No changes")] }
        table.reloadData()
        commitButton.title = staged.isEmpty ? "Commit All" : "Commit Staged (\(staged.count))"
        commitButton.isEnabled = !status.changes.isEmpty
        var sync: [String] = []
        if status.ahead > 0 { sync.append("↑\(status.ahead)") }
        if status.behind > 0 { sync.append("↓\(status.behind)") }
        syncLabel.stringValue = status.upstream == nil ? "no remote branch" : sync.joined(separator: " ")
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        !self.tableView(tableView, isGroupRow: row)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let label = NSTextField(labelWithString: title.uppercased())
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        case .change(let change):
            let letter = NSTextField(labelWithString: change.letter)
            letter.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
            letter.textColor = switch change.letter {
            case "A", "U": .systemGreen
            case "D", "!": .systemRed
            case "R": .systemBlue
            default: .systemOrange
            }
            let name = NSTextField(labelWithString: (change.path as NSString).lastPathComponent)
            name.font = .systemFont(ofSize: 12)
            name.lineBreakMode = .byTruncatingMiddle
            let folder = NSTextField(labelWithString: (change.path as NSString).deletingLastPathComponent)
            folder.font = .systemFont(ofSize: 10)
            folder.textColor = .secondaryLabelColor
            folder.lineBreakMode = .byTruncatingHead
            folder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let staged = change.isStaged
            let toggle = FileTreeView.iconButton(staged ? "minus" : "plus", staged ? "Unstage" : "Stage", #selector(toggleStage(_:)), self)
            toggle.tag = row
            let stack = NSStackView(views: [letter, name, folder, NSView(), toggle])
            stack.spacing = 6
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 6)
            letter.widthAnchor.constraint(equalToConstant: 12).isActive = true
            stack.toolTip = change.originalPath.map { "\($0) → \(change.path)" } ?? change.path
            return stack
        }
    }

    private func change(at row: Int) -> GitChange? {
        guard rows.indices.contains(row), case .change(let change) = rows[row] else { return nil }
        return change
    }

    private var clickedChange: GitChange? {
        change(at: table.clickedRow >= 0 ? table.clickedRow : table.selectedRow)
    }

    // MARK: Actions

    private func git(_ arguments: [String], success: String? = nil, then: (() -> Void)? = nil) {
        guard let folder, !busy else { return }
        busy = true
        Git.run(arguments, in: folder) { [weak self] result in
            guard let self else { return }
            busy = false
            if result.succeeded {
                if let success { onMessage?(success) }
                then?()
            } else {
                let text = (result.error.isEmpty ? result.output : result.error).trimmingCharacters(in: .whitespacesAndNewlines)
                Prompt.show("git \(arguments.first ?? "") failed", message: text.isEmpty ? "Exit code \(result.status)" : text)
            }
            refresh()
        }
    }

    @objc private func toggleStage(_ sender: NSButton) {
        guard let change = change(at: sender.tag) else { return }
        if change.isStaged {
            git(["restore", "--staged", "--", change.path])
        } else {
            git(["add", "--", change.path])
        }
    }

    @objc private func commit() {
        let text = message.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            window?.makeFirstResponder(message)
            return NSSound.beep()
        }
        let hasStaged = status?.changes.contains(where: \.isStaged) ?? false
        let commitMessage = text
        let doCommit: () -> Void = { [weak self] in
            self?.git(["commit", "-m", commitMessage], success: "Committed: \(commitMessage.components(separatedBy: "\n")[0])") {
                self?.message.string = ""
                self?.textDidChange(Notification(name: NSText.didChangeNotification))
            }
        }
        if hasStaged {
            doCommit()
        } else {
            git(["add", "-A"], then: doCommit)
        }
    }

    @objc private func fetch() { git(["fetch", "--prune"], success: "Fetched") }
    @objc private func pull() { git(["pull", "--ff-only"], success: "Pulled") }

    @objc private func push() {
        guard let status else { return }
        if status.upstream == nil {
            git(["push", "--set-upstream", "origin", status.branch], success: "Pushed \(status.branch) to origin")
        } else {
            git(["push"], success: "Pushed")
        }
    }

    @objc private func branchChosen() {
        guard let title = branchMenu.titleOfSelectedItem, title != status?.branch else { return }
        if title == "New Branch…" {
            branchMenu.selectItem(withTitle: status?.branch ?? "")
            guard let name = Prompt.ask("New Branch", message: "The new branch starts from \(status?.branch ?? "the current commit") and becomes the current branch.",
                                        confirm: "Create")?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
            git(["switch", "-c", name], success: "Created and switched to \(name)")
        } else {
            git(["switch", title], success: "Switched to \(title)")
        }
    }

    @objc private func initRepository() {
        git(["init"], success: "Created a Git repository")
    }

    @objc private func openFile() {
        guard let change = clickedChange, let folder else { return }
        onOpenFile?(folder.appendingPathComponent(change.path))
    }

    @objc private func openDiff() {
        guard let change = clickedChange, let folder else { return }
        if change.isUntracked {
            onOpenFile?(folder.appendingPathComponent(change.path))
            return
        }
        let arguments = change.isStaged ? ["diff", "--cached", "--", change.path] : ["diff", "--", change.path]
        Git.run(arguments, in: folder) { [weak self] result in
            let text = result.output.isEmpty ? "No differences." : result.output
            self?.onShowText?("\((change.path as NSString).lastPathComponent) (changes)", text, "diff")
        }
    }

    @objc private func discardChanges() {
        guard let change = clickedChange else { return }
        let name = (change.path as NSString).lastPathComponent
        guard Prompt.confirm("Undo the changes to “\(name)”?", message: change.isUntracked
                             ? "The new file will be moved to the Trash." : "Your edits since the last commit will be lost.", button: "Undo Changes") else { return }
        if change.isUntracked, let folder {
            try? FileManager.default.trashItem(at: folder.appendingPathComponent(change.path), resultingItemURL: nil)
            refresh()
        } else {
            git(["restore", "--staged", "--worktree", "--", change.path], success: "Undid changes to \(name)")
        }
    }

    @objc func showHistory() {
        guard let folder else { return }
        Git.run(["log", "--graph", "--date=relative", "-n", "300", "--pretty=format:%h  %ad  %an%d%n    %s"], in: folder) { [weak self] result in
            self?.onShowText?("History — \(self?.status?.branch ?? "")", result.succeeded ? result.output : result.error, "text")
        }
    }
}
