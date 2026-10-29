import AppKit
import CodeForgeKit

private extension NSToolbarItem.Identifier {
    static let files = Self("files")
    static let newProject = Self("newProject")
    static let open = Self("open")
    static let saveAll = Self("saveAll")
    static let start = Self("start")
    static let stop = Self("stop")
    static let panel = Self("panel")
}

/// The main window: editor tabs, explorer, bottom panel (Output, Error List, Terminal) and status bar.
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
    private let startPage = StartPage()
    private let panel = BottomPanel()
    private var console: ConsoleView { panel.output }
    private let statusBar = StatusBar()
    private let startButton = NSButton()
    private let runStatus = NSTextField(labelWithString: "")
    private let cursorStatus = NSTextField(labelWithString: "")
    private let languageMenu = NSPopUpButton()
    private let runner = Runner()
    private var untitledCount = 0
    private var isRunning = false
    private var runFolder: URL?
    private var pendingClone: URL?
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
        innerSplit.addArrangedSubview(panel)
        innerSplit.setHoldingPriority(.init(260), forSubviewAt: 1)

        outerSplit.isVertical = true
        outerSplit.dividerStyle = .thin
        outerSplit.delegate = self
        arrangeExplorer()

        for field in [runStatus, cursorStatus] {
            field.font = .systemFont(ofSize: 11)
            field.textColor = .white
            field.lineBreakMode = .byTruncatingTail
        }
        runStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        languageMenu.isBordered = false
        languageMenu.font = .systemFont(ofSize: 11)
        languageMenu.contentTintColor = .white
        languageMenu.controlSize = .small
        languageMenu.addItems(withTitles: ([Languages.plainText] + Languages.all).map(\.name))
        for (item, language) in zip(languageMenu.itemArray, [Languages.plainText] + Languages.all) {
            item.representedObject = language.id
        }
        languageMenu.target = self
        languageMenu.action = #selector(languageChosen(_:))
        let status = statusBar
        let items = NSStackView(views: [runStatus, NSView(), cursorStatus, languageMenu])
        items.spacing = 14
        items.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)
        items.translatesAutoresizingMaskIntoConstraints = false
        status.addSubview(items)
        NSLayoutConstraint.activate([
            items.topAnchor.constraint(equalTo: status.topAnchor),
            items.bottomAnchor.constraint(equalTo: status.bottomAnchor),
            items.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            items.trailingAnchor.constraint(equalTo: status.trailingAnchor),
        ])

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
            status.heightAnchor.constraint(equalToConstant: 22),
        ])
        window?.contentView = root
        explorer.isHidden = defaults.bool(forKey: "explorerHidden")
        panel.isHidden = defaults.bool(forKey: "consoleHidden")
    }

    private var explorerOnRight: Bool { defaults.object(forKey: "explorerOnRight") as? Bool ?? true }

    /// Puts the explorer on the right (like Visual Studio's Solution Explorer) or the left.
    private func arrangeExplorer() {
        outerSplit.arrangedSubviews.forEach { outerSplit.removeArrangedSubview($0); $0.removeFromSuperview() }
        let views: [NSView] = explorerOnRight ? [innerSplit, explorer] : [explorer, innerSplit]
        views.forEach(outerSplit.addArrangedSubview)
        outerSplit.setHoldingPriority(.init(250), forSubviewAt: explorerOnRight ? 0 : 1)
        outerSplit.setHoldingPriority(.init(260), forSubviewAt: explorerOnRight ? 1 : 0)
    }

    private func placeExplorerDivider() {
        guard !explorer.isHidden else { return }
        let width = defaults.double(forKey: "explorerWidth").clamped(150, 500, default: 260)
        outerSplit.setPosition(explorerOnRight ? outerSplit.bounds.width - width : width, ofDividerAt: 0)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard !didPlaceDividers else { return }
        didPlaceDividers = true
        window?.contentView?.layoutSubtreeIfNeeded()
        placeDividers()
    }

    private func placeDividers() {
        // Read before moving anything: each move saves the sizes it produces.
        let panelHeight = defaults.double(forKey: "consoleHeight").clamped(80, 800, default: 220)
        placeExplorerDivider()
        if !panel.isHidden { innerSplit.setPosition(innerSplit.bounds.height - panelHeight, ofDividerAt: 0) }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        guard splitView === outerSplit else { return max(proposed, 120) }
        return explorerOnRight ? splitView.bounds.width - 500 : 150
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        guard splitView === outerSplit else { return splitView.bounds.height - 80 }
        return explorerOnRight ? splitView.bounds.width - 150 : min(500, splitView.bounds.width - 300)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard didPlaceDividers else { return }
        if !explorer.isHidden { defaults.set(Double(explorer.frame.width), forKey: "explorerWidth") }
        if !panel.isHidden { defaults.set(Double(panel.frame.height), forKey: "consoleHeight") }
    }

    private func buildToolbar() {
        let toolbar = NSToolbar(identifier: "CodeForgeToolbar2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified

        startButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Start")
        startButton.imagePosition = .imageLeading
        startButton.bezelStyle = .texturedRounded
        startButton.contentTintColor = .systemGreen
        startButton.font = .systemFont(ofSize: 12, weight: .medium)
        startButton.target = self
        startButton.action = #selector(runActiveFile(_:))
        startButton.toolTip = "Start (⌘R)"
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newProject, .open, .saveAll, .flexibleSpace, .start, .stop, .flexibleSpace, .panel, .files]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == .start {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "Start"
            item.view = startButton
            return item
        }
        let specs: [NSToolbarItem.Identifier: (String, String, Selector)] = [
            .files: ("Explorer", explorerOnRight ? "sidebar.right" : "sidebar.left", #selector(toggleExplorer(_:))),
            .newProject: ("New Project", "plus.rectangle.on.folder", #selector(newProject(_:))),
            .open: ("Open", "folder", #selector(openDocument(_:))),
            .saveAll: ("Save All", "square.and.arrow.down.on.square", #selector(saveAllDocuments(_:))),
            .stop: ("Stop", "stop.fill", #selector(stopRunning(_:))),
            .panel: ("Panel", "rectangle.bottomthird.inset.filled", #selector(toggleConsole(_:))),
        ]
        guard let (label, symbol, action) = specs[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        if id == .stop { item.image = item.image?.withSymbolConfiguration(.init(paletteColors: [.systemRed])) }
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
        panel.onHide = { [weak self] in self?.setConsoleVisible(false) }
        panel.errors.onOpen = { [weak self] url, diagnostic in self?.open(url, line: diagnostic.line, column: diagnostic.column) }
        startPage.onOpenRecent = { [weak self] in self?.open($0) }
        startPage.onNewProject = { [weak self] in self?.newProject(nil) }
        startPage.onOpen = { [weak self] in self?.openDocument(nil) }
        startPage.onClone = { [weak self] in self?.cloneRepository(nil) }
        startPage.onNewFile = { [weak self] in self?.newDocument(nil) }
        runner.onExit = { [weak self] status, seconds in self?.runFinished(status: status, seconds: seconds) }
    }

    @objc private func appDidBecomeActive() {
        explorer.reload()
    }

    // MARK: Documents

    /// Opens a file and moves the cursor to a 1-based line (and column).
    func open(_ url: URL, line: Int, column: Int? = nil) {
        open(url)
        guard let current, current.url?.standardizedFileURL == url.standardizedFileURL else { return }
        current.reveal(line: line, column: column)
    }

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
        panel.terminal.directory = url ?? FileManager.default.homeDirectoryForCurrentUser
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
        if current == nil { startPage.reload() }
        let content: NSView = current?.scrollView ?? startPage
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
        updateRunChrome()
    }

    /// The Start button names what ⌘R will run; the status bar is orange while running, purple with no folder.
    private func updateRunChrome() {
        let custom = customCommandKey.flatMap { defaults.string(forKey: $0) }
        startButton.title = " " + (custom != nil ? workspaceURL!.lastPathComponent : current?.displayName ?? "Start")
        startButton.isEnabled = !isRunning && (custom != nil || current != nil)
        statusBar.color = isRunning ? Theme.statusBusy : (workspaceURL == nil ? Theme.statusIdle : Theme.accent)
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
        placeExplorerDivider()
    }

    @objc func toggleConsole(_ sender: Any?) {
        setConsoleVisible(panel.isHidden)
    }

    private func setConsoleVisible(_ visible: Bool) {
        guard panel.isHidden == visible else { return }
        panel.isHidden = !visible
        defaults.set(!visible, forKey: "consoleHidden")
        innerSplit.adjustSubviews()
        if visible {
            let height = defaults.double(forKey: "consoleHeight").clamped(80, 800, default: 220)
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
        panel.show(.output)
        console.clear(nil)
        console.append("$ \(command)\n", .info)
        runStatus.stringValue = "Running…"
        runFolder = folder
        isRunning = true
        documents.forEach { $0.setDiagnostics([]) }
        runner.run(command, in: folder)
        updateRunChrome()
    }

    private func runFinished(status: Int32, seconds: TimeInterval) {
        let time = String(format: "%.2fs", seconds)
        console.append("\n[Finished with exit code \(status) in \(time)]\n", status == 0 ? .info : .error)
        if status == 127, let hint = runningLanguage?.installHint {
            console.append("A required tool wasn't found. \(hint)\n", .info)
        }
        isRunning = false
        let diagnostics = DiagnosticParser.parse(console.text)
        let folder = runFolder ?? workspaceURL ?? FileManager.default.homeDirectoryForCurrentUser
        panel.errors.set(diagnostics, folder: folder)
        panel.updateTabTitles()
        for document in documents {
            guard let url = document.url?.standardizedFileURL else { continue }
            document.setDiagnostics(diagnostics.filter { $0.url(relativeTo: folder).standardizedFileURL == url })
        }
        let errorCount = diagnostics.filter { $0.severity == .error }.count
        if status != 0, errorCount > 0 { panel.show(.errors) }
        if status == 0 {
            runStatus.stringValue = "Finished in \(time)"
        } else {
            runStatus.stringValue = errorCount > 0 ? "Failed — \(errorCount) error\(errorCount == 1 ? "" : "s")" : "Failed (exit code \(status))"
        }
        updateRunChrome()
        if let clone = pendingClone {
            pendingClone = nil
            if status == 0 { setWorkspace(clone) }
        }
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
        updateRunChrome()
    }

    // MARK: Projects

    @objc func newProject(_ sender: Any?) {
        guard let window else { return }
        NewProjectSheet { [weak self] template, name, location in
            guard let self else { return }
            do {
                let folder = try ProjectTemplates.create(template, named: name, in: location)
                if let command = template.runCommand { defaults.set(command, forKey: "runCommand:" + folder.path) }
                setWorkspace(folder)
                open(folder.appendingPathComponent(ProjectTemplates.mainFile(of: template, named: name)))
            } catch {
                Prompt.show("Couldn't create the project", message: error.localizedDescription)
            }
        }.show(in: window)
    }

    @objc func cloneRepository(_ sender: Any?) {
        guard let address = Prompt.ask("Clone a repository", message: "Enter the repository URL, for example https://github.com/owner/project.git",
                                       confirm: "Continue")?.trimmingCharacters(in: .whitespaces), !address.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Clone Here"
        panel.message = "Choose the folder to put the repository in."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        var name = (address as NSString).lastPathComponent
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        pendingClone = parent.appendingPathComponent(name)
        start("git clone --progress \(CommandTemplate.shellQuote(address))", in: parent)
    }

    @objc func stopRunning(_ sender: Any?) {
        runner.stop()
    }

    @objc func clearConsole(_ sender: Any?) {
        console.clear(nil)
    }

    @objc func focusConsoleInput(_ sender: Any?) {
        setConsoleVisible(true)
        panel.show(.output)
        console.focusInput()
    }

    @objc func showOutput(_ sender: Any?) { showPanelTab(.output) }
    @objc func showErrorList(_ sender: Any?) { showPanelTab(.errors) }
    @objc func showTerminal(_ sender: Any?) { showPanelTab(.terminal) }

    private func showPanelTab(_ tab: BottomPanel.Tab) {
        setConsoleVisible(true)
        panel.show(tab)
    }

    @objc func toggleExplorerSide(_ sender: Any?) {
        defaults.set(!explorerOnRight, forKey: "explorerOnRight")
        arrangeExplorer()
        outerSplit.layoutSubtreeIfNeeded()
        placeExplorerDivider()
        if let toolbar = window?.toolbar, let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == .files }) {
            toolbar.items[index].image = NSImage(systemSymbolName: explorerOnRight ? "sidebar.right" : "sidebar.left", accessibilityDescription: "Explorer")
        }
    }

    func stopAll() {
        runner.stop()
        panel.terminal.stop()
    }

    // MARK: Validation

    private func isEnabled(_ action: Selector?) -> Bool {
        switch action {
        case #selector(stopRunning(_:)): runner.isRunning
        case #selector(runActiveFile(_:)): !isRunning
        case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)): current != nil
        case #selector(saveAllDocuments(_:)): documents.contains { $0.isDirty }
        case #selector(closeFolder(_:)), #selector(editRunCommand(_:)): workspaceURL != nil
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)): documents.count > 1
        default: true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleExplorer(_:)) { menuItem.title = explorer.isHidden ? "Show Explorer" : "Hide Explorer" }
        if menuItem.action == #selector(toggleConsole(_:)) { menuItem.title = panel.isHidden ? "Show Panel" : "Hide Panel" }
        if menuItem.action == #selector(toggleExplorerSide(_:)) { menuItem.title = explorerOnRight ? "Move Explorer to Left" : "Move Explorer to Right" }
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
        stopAll()
    }
}

/// The colored bar at the bottom of the window.
final class StatusBar: NSView {
    var color: NSColor = Theme.accent { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

private extension Double {
    /// Clamps a stored value, using `fallback` when nothing was stored (0).
    func clamped(_ low: Double, _ high: Double, default fallback: Double) -> Double {
        self == 0 ? fallback : Swift.min(Swift.max(self, low), high)
    }
}
