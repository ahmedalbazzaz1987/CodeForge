import AppKit
import CodeForgeKit

private extension NSToolbarItem.Identifier {
    static let files = Self("files")
    static let run = Self("run")
    static let stop = Self("stop")
    static let console = Self("console")
}

/// The main window: explorer, tabs, editor, console and status bar.
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate, NSToolbarDelegate,
    NSMenuItemValidation, NSToolbarItemValidation
{
    private(set) var workspaceURL: URL?
    private var documents: [EditorDocument] = []
    private var selectedIndex = -1
    private var current: EditorDocument? { documents.indices.contains(selectedIndex) ? documents[selectedIndex] : nil }

    private let outerSplit = NSSplitView()
    private let innerSplit = NSSplitView()
    private let explorer = FileTreeView()
    private let tabBar = TabBarView()
    private let editorHost = NSView()
    private let welcome = NSStackView()
    private let console = ConsoleView()
    private let runStatus = NSTextField(labelWithString: "")
    private let cursorStatus = NSTextField(labelWithString: "")
    private let languageMenu = NSPopUpButton()
    private let runner = Runner()
    private var untitledCount = 0
    private var didPlaceDividers = false

    private let defaults = UserDefaults.standard
    private var fontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: "fontSize").clamped(9, 32, default: 13)) }
        set { defaults.set(Double(newValue), forKey: "fontSize") }
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 720, height: 420)
        window.title = "CodeForge"
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        buildLayout()
        buildToolbar()
        if !window.setFrameUsingName("CodeForgeMain") { window.center() }
        window.setFrameAutosaveName("CodeForgeMain")
        connectCallbacks()
        select(-1)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private func buildLayout() {
        let editorArea = NSView()
        for view in [tabBar, editorHost] {
            view.translatesAutoresizingMaskIntoConstraints = false
            editorArea.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: editorArea.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 30),
            editorHost.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            editorHost.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            editorHost.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            editorHost.bottomAnchor.constraint(equalTo: editorArea.bottomAnchor),
        ])

        innerSplit.isVertical = false
        innerSplit.dividerStyle = .thin
        innerSplit.delegate = self
        innerSplit.addArrangedSubview(editorArea)
        innerSplit.addArrangedSubview(console)
        innerSplit.setHoldingPriority(.init(260), forSubviewAt: 1)

        outerSplit.isVertical = true
        outerSplit.dividerStyle = .thin
        outerSplit.delegate = self
        outerSplit.addArrangedSubview(explorer)
        outerSplit.addArrangedSubview(innerSplit)
        outerSplit.setHoldingPriority(.init(260), forSubviewAt: 0)

        let title = NSTextField(labelWithString: "CodeForge")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .secondaryLabelColor
        let hint = NSTextField(labelWithString: "Open a folder or a file to start coding.")
        hint.textColor = .tertiaryLabelColor
        let buttons = NSStackView(views: [
            NSButton(title: "Open…", target: self, action: #selector(openDocument(_:))),
            NSButton(title: "New File", target: self, action: #selector(newDocument(_:))),
        ])
        let shortcuts = NSTextField(labelWithString: "⌘O  Open      ⌘P  Quick Open      ⌘R  Run      ⇧⌘Y  Console")
        shortcuts.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        shortcuts.textColor = .tertiaryLabelColor
        welcome.setViews([title, hint, buttons, shortcuts], in: .center)
        welcome.orientation = .vertical
        welcome.spacing = 12
        welcome.setCustomSpacing(24, after: buttons)

        for field in [runStatus, cursorStatus] {
            field.font = .systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
        }
        runStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        languageMenu.isBordered = false
        languageMenu.font = .systemFont(ofSize: 11)
        languageMenu.controlSize = .small
        languageMenu.addItems(withTitles: ([Languages.plainText] + Languages.all).map(\.name))
        for (item, language) in zip(languageMenu.itemArray, [Languages.plainText] + Languages.all) {
            item.representedObject = language.id
        }
        languageMenu.target = self
        languageMenu.action = #selector(languageChosen(_:))
        let status = NSStackView(views: [runStatus, NSView(), cursorStatus, languageMenu])
        status.spacing = 14
        status.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)

        let root = NSView()
        for view in [outerSplit, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            outerSplit.topAnchor.constraint(equalTo: root.topAnchor),
            outerSplit.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            outerSplit.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.topAnchor.constraint(equalTo: outerSplit.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 24),
        ])
        window?.contentView = root
        explorer.isHidden = defaults.bool(forKey: "explorerHidden")
        console.isHidden = defaults.bool(forKey: "consoleHidden")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard !didPlaceDividers else { return }
        didPlaceDividers = true
        window?.contentView?.layoutSubtreeIfNeeded()
        placeDividers()
    }

    private func placeDividers() {
        let sidebar = defaults.double(forKey: "explorerWidth").clamped(150, 500, default: 240)
        let consoleHeight = defaults.double(forKey: "consoleHeight").clamped(80, 800, default: 200)
        if !explorer.isHidden { outerSplit.setPosition(sidebar, ofDividerAt: 0) }
        if !console.isHidden { innerSplit.setPosition(innerSplit.bounds.height - consoleHeight, ofDividerAt: 0) }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        splitView === outerSplit ? 150 : max(proposed, 120)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        splitView === outerSplit ? min(500, splitView.bounds.width - 300) : splitView.bounds.height - 80
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard didPlaceDividers else { return }
        if !explorer.isHidden { defaults.set(Double(explorer.frame.width), forKey: "explorerWidth") }
        if !console.isHidden { defaults.set(Double(console.frame.height), forKey: "consoleHeight") }
    }

    private func buildToolbar() {
        let toolbar = NSToolbar(identifier: "CodeForgeToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.files, .flexibleSpace, .run, .stop, .console]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let specs: [NSToolbarItem.Identifier: (String, String, Selector)] = [
            .files: ("Explorer", "sidebar.left", #selector(toggleExplorer(_:))),
            .run: ("Run", "play.fill", #selector(runActiveFile(_:))),
            .stop: ("Stop", "stop.fill", #selector(stopRunning(_:))),
            .console: ("Console", "rectangle.bottomthird.inset.filled", #selector(toggleConsole(_:))),
        ]
        guard let (label, symbol, action) = specs[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    // MARK: Wiring

    private func connectCallbacks() {
        tabBar.onSelect = { [weak self] in self?.select($0) }
        tabBar.onClose = { [weak self] in _ = self?.closeDocument(at: $0) }
        explorer.onOpenFile = { [weak self] in self?.open($0) }
        explorer.onOpenFolder = { [weak self] in self?.openDocument(nil) }
        explorer.onRenamed = { [weak self] old, new in
            for document in self?.documents ?? [] {
                guard let url = document.url, url == old || url.path.hasPrefix(old.path + "/") else { continue }
                document.url = URL(fileURLWithPath: new.path + url.path.dropFirst(old.path.count))
                document.language = Languages.forFile(named: document.url!.lastPathComponent)
            }
            self?.refreshChrome()
        }
        explorer.onTrashed = { [weak self] trashed in
            guard let self else { return }
            for index in documents.indices.reversed() {
                if let url = documents[index].url, url == trashed || url.path.hasPrefix(trashed.path + "/") {
                    documents.remove(at: index)
                    if index <= selectedIndex { selectedIndex -= 1 }
                }
            }
            select(documents.isEmpty ? -1 : max(selectedIndex, 0))
        }
        console.onInput = { [weak self] line in
            guard let self else { return }
            console.append(line + "\n", .input)
            runner.send(line)
        }
        runner.onOutput = { [weak self] text, kind in self?.console.append(text, kind) }
        runner.onExit = { [weak self] status, seconds in self?.runFinished(status: status, seconds: seconds) }
    }

    @objc private func appDidBecomeActive() {
        explorer.reload()
    }

    // MARK: Documents

    /// Opens a file in a tab, or a folder as the workspace.
    func open(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            setWorkspace(url)
            return
        }
        let target = url.standardizedFileURL
        if let index = documents.firstIndex(where: { $0.url?.standardizedFileURL == target }) {
            return select(index)
        }
        do {
            let document = makeDocument(url: target, text: try EditorDocument.readText(target))
            documents.append(document)
            select(documents.count - 1)
            NSDocumentController.shared.noteNewRecentDocumentURL(target)
        } catch {
            Prompt.show("Couldn't open “\(url.lastPathComponent)”", message: error.localizedDescription)
        }
    }

    func setWorkspace(_ url: URL?) {
        workspaceURL = url
        explorer.setRoot(url)
        if let url {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            if explorer.isHidden { toggleExplorer(nil) }
        }
        refreshChrome()
        saveSession()
    }

    private func makeDocument(url: URL?, text: String) -> EditorDocument {
        var name = "Untitled"
        if url == nil {
            untitledCount += 1
            if untitledCount > 1 { name += " \(untitledCount)" }
        }
        let document = EditorDocument(url: url, text: text, fontSize: fontSize, untitledName: name)
        document.onStateChange = { [weak self] in self?.refreshChrome() }
        document.onSelectionChange = { [weak self, weak document] in
            if document === self?.current { self?.updateCursorStatus() }
        }
        return document
    }

    private func select(_ index: Int) {
        selectedIndex = documents.indices.contains(index) ? index : -1
        editorHost.subviews.forEach { $0.removeFromSuperview() }
        let content: NSView = current?.scrollView ?? welcome
        content.translatesAutoresizingMaskIntoConstraints = false
        editorHost.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: editorHost.topAnchor),
            content.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor),
        ])
        if let current {
            window?.makeFirstResponder(current.textView)
            if let url = current.url { explorer.select(url) }
        }
        refreshChrome()
    }

    /// Returns false if the user cancelled.
    @discardableResult
    private func closeDocument(at index: Int) -> Bool {
        guard documents.indices.contains(index) else { return true }
        guard confirmDiscard(documents[index]) else { return false }
        documents.remove(at: index)
        if index < selectedIndex || selectedIndex >= documents.count { selectedIndex -= 1 }
        select(selectedIndex)
        saveSession()
        return true
    }

    /// Asks to save a document with unsaved changes. Returns false if the user cancelled.
    private func confirmDiscard(_ document: EditorDocument) -> Bool {
        guard document.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to “\(document.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save(document)
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    /// Checks every unsaved document before the window closes or the app quits.
    func confirmCloseAll() -> Bool {
        for (index, document) in documents.enumerated() where document.isDirty {
            select(index)
            guard confirmDiscard(document) else { return false }
        }
        return true
    }

    @discardableResult
    private func save(_ document: EditorDocument) -> Bool {
        guard document.url != nil else { return saveAs(document) }
        do {
            try document.write()
            return true
        } catch {
            Prompt.show("Couldn't save “\(document.displayName)”", message: error.localizedDescription)
            return false
        }
    }

    private func saveAs(_ document: EditorDocument) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.url?.lastPathComponent ?? document.displayName
        panel.directoryURL = document.url?.deletingLastPathComponent() ?? workspaceURL
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let wasPlainText = document.language.id == Languages.plainText.id
        document.url = url
        if wasPlainText || document.language.id != Languages.forFile(named: url.lastPathComponent).id {
            document.language = Languages.forFile(named: url.lastPathComponent)
        }
        let saved = save(document)
        explorer.reload()
        saveSession()
        return saved
    }

    // MARK: Chrome

    private func refreshChrome() {
        tabBar.update(documents.map {
            TabBarView.Tab(title: $0.displayName, isDirty: $0.isDirty, toolTip: $0.url?.path)
        }, selected: selectedIndex)
        window?.title = current?.displayName ?? "CodeForge"
        window?.subtitle = workspaceURL?.lastPathComponent ?? ""
        window?.representedURL = current?.url
        window?.isDocumentEdited = current?.isDirty ?? false
        languageMenu.isHidden = current == nil
        if let id = current?.language.id, let item = languageMenu.itemArray.first(where: { $0.representedObject as? String == id }) {
            languageMenu.select(item)
        }
        updateCursorStatus()
        window?.toolbar?.validateVisibleItems()
    }

    private func updateCursorStatus() {
        guard let current else { return cursorStatus.stringValue = "" }
        let position = current.cursorPosition
        let selected = current.textView.selectedRange().length
        let indent = current.language.indentWithTabs ? "Tabs" : "Spaces: 4"
        cursorStatus.stringValue = "Ln \(position.line), Col \(position.column)" + (selected > 0 ? " (\(selected) selected)" : "") + "    \(indent)    UTF-8"
    }

    @objc private func languageChosen(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String, let language = Languages.language(id: id) else { return }
        current?.language = language
    }

    // MARK: Session

    func saveSession() {
        defaults.set(workspaceURL?.path, forKey: "workspace")
        defaults.set(documents.compactMap { $0.url?.path }, forKey: "openFiles")
        defaults.set(current?.url?.path, forKey: "selectedFile")
    }

    func restoreSession() {
        // Read everything first: opening the folder saves the (still empty) session.
        let files = defaults.stringArray(forKey: "openFiles") ?? []
        let selected = defaults.string(forKey: "selectedFile")
        if let path = defaults.string(forKey: "workspace"), FileManager.default.fileExists(atPath: path) {
            setWorkspace(URL(fileURLWithPath: path))
        }
        for path in files where FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path))
        }
        if let path = selected,
           let index = documents.firstIndex(where: { $0.url?.standardizedFileURL == URL(fileURLWithPath: path).standardizedFileURL }) {
            select(index)
        }
        saveSession()
    }

    // MARK: File menu

    @objc func newDocument(_ sender: Any?) {
        documents.append(makeDocument(url: nil, text: ""))
        select(documents.count - 1)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose a folder to open as a project, or files to edit."
        panel.directoryURL = workspaceURL
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open)
    }

    @objc func quickOpen(_ sender: Any?) {
        guard let workspaceURL, let window else { return openDocument(sender) }
        QuickOpen(root: workspaceURL) { [weak self] in self?.open($0) }.show(in: window)
    }

    @objc func saveDocument(_ sender: Any?) {
        if let current { save(current) }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        if let current { _ = saveAs(current) }
    }

    @objc func saveAllDocuments(_ sender: Any?) {
        for document in documents where document.isDirty { save(document) }
    }

    @objc func closeTab(_ sender: Any?) {
        if current != nil { closeDocument(at: selectedIndex) } else { window?.performClose(sender) }
    }

    @objc func closeFolder(_ sender: Any?) {
        setWorkspace(nil)
    }

    @objc func selectNextTab(_ sender: Any?) {
        if !documents.isEmpty { select((selectedIndex + 1) % documents.count) }
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        if !documents.isEmpty { select((selectedIndex - 1 + documents.count) % documents.count) }
    }

    // MARK: View menu

    @objc func toggleExplorer(_ sender: Any?) {
        explorer.isHidden.toggle()
        defaults.set(explorer.isHidden, forKey: "explorerHidden")
        outerSplit.adjustSubviews()
        if !explorer.isHidden { outerSplit.setPosition(defaults.double(forKey: "explorerWidth").clamped(150, 500, default: 240), ofDividerAt: 0) }
    }

    @objc func toggleConsole(_ sender: Any?) {
        setConsoleVisible(console.isHidden)
    }

    private func setConsoleVisible(_ visible: Bool) {
        guard console.isHidden == visible else { return }
        console.isHidden = !visible
        defaults.set(!visible, forKey: "consoleHidden")
        innerSplit.adjustSubviews()
        if visible {
            let height = defaults.double(forKey: "consoleHeight").clamped(80, 800, default: 200)
            innerSplit.setPosition(innerSplit.bounds.height - height, ofDividerAt: 0)
        }
    }

    @objc func increaseFontSize(_ sender: Any?) { setFontSize(fontSize + 1) }
    @objc func decreaseFontSize(_ sender: Any?) { setFontSize(fontSize - 1) }
    @objc func resetFontSize(_ sender: Any?) { setFontSize(13) }

    private func setFontSize(_ size: CGFloat) {
        fontSize = min(max(size, 9), 32)
        documents.forEach { $0.setFontSize(fontSize) }
    }

    // MARK: Run menu

    private var customCommandKey: String? { workspaceURL.map { "runCommand:" + $0.path } }

    /// Runs the project's custom command if one is set, otherwise the current file.
    @objc func runActiveFile(_ sender: Any?) {
        if let key = customCommandKey, let command = defaults.string(forKey: key), !command.isEmpty, let folder = workspaceURL {
            saveAllDocuments(nil)
            return start(command, in: folder)
        }
        guard let document = current else {
            return Prompt.show("Nothing to run", message: "Open a file, or choose Run ▸ Set Run Command… to run a command for this folder.")
        }
        guard document.url != nil || saveAs(document), let file = document.url else { return }
        if document.isDirty { guard save(document) else { return } }
        guard let template = document.language.runCommand else {
            return Prompt.show("CodeForge doesn't know how to run \(document.language.name) files",
                               message: "Choose Run ▸ Set Run Command… to enter the command for this folder.")
        }
        let output = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CodeForge").appendingPathComponent("build")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        start(CommandTemplate.expand(template, file: file, outputDirectory: output), in: file.deletingLastPathComponent())
    }

    private var runningLanguage: Language?

    private func start(_ command: String, in folder: URL) {
        runningLanguage = defaults.string(forKey: customCommandKey ?? "")?.isEmpty == false ? nil : current?.language
        setConsoleVisible(true)
        console.clear(nil)
        console.append("$ \(command)\n", .info)
        runStatus.stringValue = "Running…"
        runner.run(command, in: folder)
        window?.toolbar?.validateVisibleItems()
    }

    private func runFinished(status: Int32, seconds: TimeInterval) {
        let time = String(format: "%.2fs", seconds)
        console.append("\n[Finished with exit code \(status) in \(time)]\n", status == 0 ? .info : .error)
        if status == 127, let hint = runningLanguage?.installHint {
            console.append("A required tool wasn't found. \(hint)\n", .info)
        }
        runStatus.stringValue = status == 0 ? "Finished in \(time)" : "Failed (exit code \(status))"
        window?.toolbar?.validateVisibleItems()
    }

    @objc func editRunCommand(_ sender: Any?) {
        guard let key = customCommandKey else {
            return Prompt.show("Open a folder first", message: "A run command is saved for each project folder.")
        }
        let message = """
            This command runs in the project folder when you press ⌘R, for example `swift run`, `npm start`, \
            `make` or `python3 main.py`. Leave it empty to run the current file instead.
            """
        guard let command = Prompt.ask("Run Command for “\(workspaceURL!.lastPathComponent)”", message: message,
                                       defaultValue: defaults.string(forKey: key) ?? "", confirm: "Save") else { return }
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        trimmed.isEmpty ? defaults.removeObject(forKey: key) : defaults.set(trimmed, forKey: key)
    }

    @objc func stopRunning(_ sender: Any?) {
        runner.stop()
    }

    @objc func clearConsole(_ sender: Any?) {
        console.clear(nil)
    }

    @objc func focusConsoleInput(_ sender: Any?) {
        setConsoleVisible(true)
        console.focusInput()
    }

    func stopAll() {
        runner.stop()
    }

    // MARK: Validation

    private func isEnabled(_ action: Selector?) -> Bool {
        switch action {
        case #selector(stopRunning(_:)): runner.isRunning
        case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)): current != nil
        case #selector(saveAllDocuments(_:)): documents.contains { $0.isDirty }
        case #selector(closeFolder(_:)), #selector(editRunCommand(_:)): workspaceURL != nil
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)): documents.count > 1
        default: true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleExplorer(_:)) { menuItem.title = explorer.isHidden ? "Show Explorer" : "Hide Explorer" }
        if menuItem.action == #selector(toggleConsole(_:)) { menuItem.title = console.isHidden ? "Show Console" : "Hide Console" }
        return isEnabled(menuItem.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        isEnabled(item.action)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmCloseAll()
    }

    func windowWillClose(_ notification: Notification) {
        saveSession()
        runner.stop()
    }
}

private extension Double {
    /// Clamps a stored value, using `fallback` when nothing was stored (0).
    func clamped(_ low: Double, _ high: Double, default fallback: Double) -> Double {
        self == 0 ? fallback : Swift.min(Swift.max(self, low), high)
    }
}
