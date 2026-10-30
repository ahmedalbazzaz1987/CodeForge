import AppKit
import CodeForgeKit

private extension NSToolbarItem.Identifier {
    static let files = Self("files")
    static let newProject = Self("newProject")
    static let open = Self("open")
    static let saveAll = Self("saveAll")
    static let start = Self("start")
    static let debug = Self("debug")
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
    private lazy var sidebar = SidebarView(explorer: explorer)
    private var git: GitChangesView { sidebar.git }
    private let toolbox = ToolboxView()
    private let properties = PropertiesView()
    /// Solution Explorer / Git Changes above the Properties window, like Visual Studio's right-hand column.
    private let explorerPane = NSSplitView()
    private var designHosts: [ObjectIdentifier: DesignHost] = [:]
    private var pendingPropertiesUpdate: DispatchWorkItem?
    private let branchButton = NSButton()
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
    private let intelliSense = IntelliSense()
    private let intelliButton = NSButton()
    private var runDiagnostics: [Diagnostic] = []
    private var liveDiagnostics: [URL: [Diagnostic]] = [:]
    private var pendingInstall: LanguageServerSpec?
    private var afterBuild: (() -> Void)?
    private var debugSession: DebugSession?
    private var selectedFrame: DebugSession.Frame?
    private lazy var debugBar = DebugBar(target: self)
    private var debugBarHeight: NSLayoutConstraint!
    /// Breakpoint lines (1-based) per file path; saved between launches.
    private var breakpoints: [String: Set<Int>] = [:]
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
        debugBarHeight = debugBar.heightAnchor.constraint(equalToConstant: 0)
        debugBar.isHidden = true
        for view in [tabBar, debugBar, editorHost] {
            view.translatesAutoresizingMaskIntoConstraints = false
            editorArea.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: editorArea.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 30),
            debugBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            debugBar.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            debugBar.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            debugBarHeight,
            editorHost.topAnchor.constraint(equalTo: debugBar.bottomAnchor),
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

        explorerPane.isVertical = false
        explorerPane.dividerStyle = .thin
        explorerPane.delegate = self
        explorerPane.addArrangedSubview(sidebar)
        explorerPane.addArrangedSubview(properties)
        explorerPane.setHoldingPriority(.init(260), forSubviewAt: 1)

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
        intelliButton.isBordered = false
        intelliButton.font = .systemFont(ofSize: 11)
        intelliButton.contentTintColor = .white
        intelliButton.target = self
        intelliButton.action = #selector(intelliButtonClicked(_:))
        branchButton.isBordered = false
        branchButton.font = .systemFont(ofSize: 11)
        branchButton.contentTintColor = .white
        branchButton.imagePosition = .imageLeading
        branchButton.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Branch")
        branchButton.target = self
        branchButton.action = #selector(showGitChanges(_:))
        branchButton.isHidden = true
        let items = NSStackView(views: [runStatus, NSView(), intelliButton, cursorStatus, languageMenu, branchButton])
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
        explorerPane.isHidden = defaults.bool(forKey: "explorerHidden")
        toolbox.isHidden = defaults.bool(forKey: "toolboxHidden")
        properties.isHidden = defaults.bool(forKey: "propertiesHidden")
        panel.isHidden = defaults.bool(forKey: "consoleHidden")
    }

    private var explorerOnRight: Bool { defaults.object(forKey: "explorerOnRight") as? Bool ?? true }

    /// [Toolbox | editor | Solution Explorer + Properties], like Visual Studio; mirrored when the explorer is on the left.
    private func arrangeExplorer() {
        outerSplit.arrangedSubviews.forEach { outerSplit.removeArrangedSubview($0); $0.removeFromSuperview() }
        let views: [NSView] = explorerOnRight ? [toolbox, innerSplit, explorerPane] : [explorerPane, innerSplit, toolbox]
        views.forEach(outerSplit.addArrangedSubview)
        for (index, view) in views.enumerated() {
            outerSplit.setHoldingPriority(view === innerSplit ? .init(250) : .init(260), forSubviewAt: index)
        }
    }

    /// Sets a side pane's width: the first divider for the left pane, the second for the right one.
    private func place(_ pane: NSView, width: Double) {
        guard !pane.isHidden, let index = outerSplit.arrangedSubviews.firstIndex(of: pane) else { return }
        if index == 0 {
            outerSplit.setPosition(width, ofDividerAt: 0)
        } else {
            outerSplit.setPosition(outerSplit.bounds.width - width, ofDividerAt: 1)
        }
    }

    private func placeExplorerDivider() {
        place(explorerPane, width: defaults.double(forKey: "explorerWidth").clamped(150, 500, default: 270))
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
        let explorerWidth = defaults.double(forKey: "explorerWidth").clamped(150, 500, default: 270)
        let toolboxWidth = defaults.double(forKey: "toolboxWidth").clamped(150, 400, default: 210)
        let propertiesHeight = defaults.double(forKey: "propertiesHeight").clamped(120, 700, default: 260)
        place(toolbox, width: toolboxWidth)
        place(explorerPane, width: explorerWidth)
        if !panel.isHidden { innerSplit.setPosition(innerSplit.bounds.height - panelHeight, ofDividerAt: 0) }
        if !properties.isHidden { explorerPane.setPosition(explorerPane.bounds.height - propertiesHeight, ofDividerAt: 0) }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        guard splitView === outerSplit else { return max(proposed, 120) }
        let views = splitView.arrangedSubviews
        if index == 0 { return views[0].isHidden ? proposed : 150 }
        return views[2].isHidden ? proposed : splitView.bounds.width - 500
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        guard splitView === outerSplit else { return splitView.bounds.height - 80 }
        let views = splitView.arrangedSubviews
        if index == 0 { return views[0].isHidden ? proposed : 450 }
        return views[2].isHidden ? proposed : splitView.bounds.width - 150
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard didPlaceDividers else { return }
        if !toolbox.isHidden { defaults.set(Double(toolbox.frame.width), forKey: "toolboxWidth") }
        if !properties.isHidden, !explorerPane.isHidden { defaults.set(Double(properties.frame.height), forKey: "propertiesHeight") }
        if !explorerPane.isHidden { defaults.set(Double(explorerPane.frame.width), forKey: "explorerWidth") }
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
        [.newProject, .open, .saveAll, .flexibleSpace, .start, .debug, .stop, .flexibleSpace, .panel, .files]
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
            .debug: ("Debug", "ladybug", #selector(startDebugging(_:))),
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
        runner.onOutput = { [weak self] text, kind in
            self?.console.append(text, kind)
            self?.openBrowserIfServerStarted(text)
        }
        panel.onHide = { [weak self] in self?.setConsoleVisible(false) }
        panel.references.onOpen = { [weak self] url, line, column in self?.open(url, line: line, column: column) }
        intelliSense.document = { [weak self] textView in self?.documents.first { $0.textView === textView } }
        intelliSense.onOpenLocation = { [weak self] url, line, column in self?.open(url, line: line, column: column) }
        intelliSense.onStatus = { [weak self] in self?.runStatus.stringValue = $0 }
        intelliSense.onReferences = { [weak self] word, locations in
            guard let self else { return }
            panel.references.set(title: word, locations)
            showPanelTab(.references)
        }
        LanguageServerManager.shared.onDiagnostics = { [weak self] url, diagnostics in
            self?.liveDiagnostics[url.standardizedFileURL] = diagnostics
            self?.refreshDiagnostics()
        }
        panel.errors.onOpen = { [weak self] url, diagnostic in self?.open(url, line: diagnostic.line, column: diagnostic.column) }
        git.onOpenFile = { [weak self] in self?.open($0) }
        git.onShowText = { [weak self] title, text, language in self?.openReadOnly(title: title, text: text, languageId: language) }
        git.onMessage = { [weak self] in self?.runStatus.stringValue = $0 }
        git.onStatusChange = { [weak self] status in self?.updateBranchButton(status) }
        toolbox.onInsert = { [weak self] item in
            guard let self, let current, current.textView.isEditable else { return NSSound.beep() }
            if let host = designHosts[ObjectIdentifier(current)], host.mode == .design { host.setMode(.split) }
            current.textView.insertSnippet(item)
        }
        properties.onChangeAttribute = { [weak self] index, name, value in self?.changeAttribute(index, name: name, value: value) }
        startPage.onOpenRecent = { [weak self] in self?.open($0) }
        startPage.onNewProject = { [weak self] in self?.newProject(nil) }
        startPage.onOpen = { [weak self] in self?.openDocument(nil) }
        startPage.onClone = { [weak self] in self?.cloneRepository(nil) }
        startPage.onNewFile = { [weak self] in self?.newDocument(nil) }
        runner.onExit = { [weak self] status, seconds in self?.runFinished(status: status, seconds: seconds) }
    }

    @objc private func appDidBecomeActive() {
        explorer.reload()
        git.refresh()
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
        documents.forEach(attachLanguageServer)
        panel.terminal.directory = url ?? FileManager.default.homeDirectoryForCurrentUser
        git.folder = url
        if let url {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            if explorerPane.isHidden { toggleExplorer(nil) }
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
        document.textView.assistant = intelliSense
        if let path = url?.standardizedFileURL.path { document.ruler.breakpoints = breakpoints[path] ?? [] }
        document.ruler.onToggleBreakpoint = { [weak self, weak document] line in
            guard let document else { return }
            self?.toggleBreakpoint(in: document, line: line)
        }
        document.onStateChange = { [weak self, weak document] in
            guard let self, let document else { return }
            // A new file name or language may need a different language server.
            if document.session?.url != document.url?.standardizedFileURL
                || document.session.map({ !$0.server.spec.languages.contains(document.language.id) }) == true
                || (document.session == nil && document.url != nil && !triedSessions.contains(ObjectIdentifier(document))) {
                attachLanguageServer(document)
            }
            refreshChrome()
        }
        attachLanguageServer(document)
        document.onSelectionChange = { [weak self, weak document] in
            if document === self?.current {
                self?.updateCursorStatus()
                self?.schedulePropertiesUpdate()
            }
        }
        document.onTextChange = { [weak self, weak document] in
            guard let self, let document else { return }
            designHosts[ObjectIdentifier(document)]?.textChanged()
        }
        return document
    }

    private func select(_ index: Int) {
        selectedIndex = documents.indices.contains(index) ? index : -1
        editorHost.subviews.forEach { $0.removeFromSuperview() }
        if current == nil { startPage.reload() }
        let content: NSView = current.map { contentView(for: $0) } ?? startPage
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
        toolbox.show(language: current?.language)
        updateProperties()
        refreshChrome()
    }

    /// HTML pages get the Design / Split / Source views; everything else is just the editor.
    private func contentView(for document: EditorDocument) -> NSView {
        guard document.language.id == "html", document.url.map({ ["html", "htm", "xhtml"].contains($0.pathExtension.lowercased()) }) ?? true else {
            if let host = designHosts.removeValue(forKey: ObjectIdentifier(document)) {
                document.scrollView.removeFromSuperview()
                host.removeFromSuperview()
            }
            return document.scrollView
        }
        if let host = designHosts[ObjectIdentifier(document)] { return host }
        let host = DesignHost(document: document)
        host.onSelectElement = { [weak self, weak document] tag, index in
            guard let document else { return }
            self?.selectElement(tag, index: index, in: document)
        }
        designHosts[ObjectIdentifier(document)] = host
        return host
    }

    /// Clicking an element in the design view puts the cursor in its tag (index = its place among tags with that name).
    private func selectElement(_ tag: String, index: Int, in document: EditorDocument) {
        let text = document.textView.string as NSString
        guard index >= 0, let regex = try? NSRegularExpression(pattern: "<" + NSRegularExpression.escapedPattern(for: tag) + #"(?=[\s/>])"#, options: .caseInsensitive) else { return }
        let matches = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        guard matches.indices.contains(index) else { return }
        let location = matches[index].range.location + 1
        document.textView.setSelectedRange(NSRange(location: location, length: 0))
        document.textView.scrollRangeToVisible(document.textView.selectedRange())
        updateProperties()
    }

    // MARK: Toolbox and Properties

    private func schedulePropertiesUpdate() {
        pendingPropertiesUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateProperties() }
        pendingPropertiesUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// The element at the cursor in HTML and Razor files; otherwise the file's details.
    private func updateProperties() {
        guard !properties.isHidden else { return }
        guard let current else { return properties.showNothing() }
        if ["html", "razor"].contains(current.language.id),
           let tag = HTMLTag.at(current.textView.selectedRange().location, in: current.textView.string) {
            properties.show(tag: tag)
        } else {
            properties.show(file: current)
        }
    }

    /// Rewrites the tag at the cursor after a change in the Properties window (one undoable edit).
    private func changeAttribute(_ index: Int, name: String?, value: String?) {
        guard let current, let textView = Optional(current.textView),
              var tag = HTMLTag.at(textView.selectedRange().location, in: textView.string) else { return }
        if index >= tag.attributes.count {
            guard let name else { return }
            tag.attributes.append((name, value ?? ""))
        } else if let name {
            tag.attributes[index] = (name, value)
        } else {
            tag.attributes.remove(at: index)
        }
        let replacement = tag.source
        guard textView.shouldChangeText(in: tag.range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: tag.range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: tag.range.location + 1, length: 0))
        updateProperties()
    }

    @objc func toggleToolbox(_ sender: Any?) {
        toolbox.isHidden.toggle()
        defaults.set(toolbox.isHidden, forKey: "toolboxHidden")
        outerSplit.adjustSubviews()
        place(toolbox, width: defaults.double(forKey: "toolboxWidth").clamped(150, 400, default: 210))
    }

    @objc func toggleProperties(_ sender: Any?) {
        properties.isHidden.toggle()
        defaults.set(properties.isHidden, forKey: "propertiesHidden")
        explorerPane.adjustSubviews()
        if !properties.isHidden {
            let height = defaults.double(forKey: "propertiesHeight").clamped(120, 700, default: 260)
            explorerPane.setPosition(explorerPane.bounds.height - height, ofDividerAt: 0)
            updateProperties()
        }
    }

    private var triedSessions = Set<ObjectIdentifier>()

    /// Connects a document to its language server for IntelliSense, if one is installed.
    private func attachLanguageServer(_ document: EditorDocument) {
        triedSessions.insert(ObjectIdentifier(document))
        guard let url = document.url?.standardizedFileURL else { document.session = nil; return }
        let root = workspaceURL.flatMap { url.path.hasPrefix($0.path + "/") ? $0 : nil } ?? url.deletingLastPathComponent()
        guard let server = LanguageServerManager.shared.server(for: document.language, root: root) else {
            document.session = nil
            return
        }
        if document.session?.server === server, document.session?.url == url { return }
        document.session = LanguageSession(document: document, server: server, url: url)
        // Give the server a moment to read the project before asking for CodeLens data.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak document] in
            if let document { self?.updateCodeLens(document) }
        }
    }

    /// Shows build/run errors and live language-server errors together.
    private func refreshDiagnostics() {
        let live = liveDiagnostics.values.flatMap { $0 }
        let folder = runFolder ?? workspaceURL ?? FileManager.default.homeDirectoryForCurrentUser
        // A build error that the language server also reports is listed once.
        let liveKeys = Set(live.map { "\($0.url(relativeTo: folder).standardizedFileURL.path):\($0.line):\($0.message.lowercased())" })
        let fromRunOnly = runDiagnostics.filter { !liveKeys.contains("\($0.url(relativeTo: folder).standardizedFileURL.path):\($0.line):\($0.message.lowercased())") }
        panel.errors.set(fromRunOnly + live, folder: folder)
        panel.updateTabTitles()
        for document in documents {
            guard let url = document.url?.standardizedFileURL else { continue }
            let fromRun = runDiagnostics.filter { $0.url(relativeTo: folder).standardizedFileURL == url }
            document.setDiagnostics(fromRun + (liveDiagnostics[url] ?? []))
        }
    }

    /// Returns false if the user cancelled.
    @discardableResult
    private func closeDocument(at index: Int) -> Bool {
        guard documents.indices.contains(index) else { return true }
        guard confirmDiscard(documents[index]) else { return false }
        documents[index].session = nil
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
            git.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak document] in
                if let document { self?.updateCodeLens(document) }
            }
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
        updateIntelliSenseStatus()
        updateRunChrome()
    }

    /// The Start button names what ⌘R will run; the status bar is orange while running, purple with no folder.
    private func updateRunChrome() {
        let custom = customCommandKey.flatMap { defaults.string(forKey: $0) }
        let project = custom == nil ? projectRunPlan : nil
        startButton.title = " " + (custom != nil ? workspaceURL!.lastPathComponent
            : project.map { _ in workspaceURL!.lastPathComponent } ?? current?.displayName ?? "Start")
        startButton.toolTip = project.map { "Start \($0.name): \($0.run ?? "") (⌘R)" } ?? "Start (⌘R)"
        startButton.isEnabled = !isRunning && (custom != nil || current != nil)
        let debugging = debugSession != nil
        statusBar.color = isRunning || debugging ? Theme.statusBusy : (workspaceURL == nil ? Theme.statusIdle : Theme.accent)
        startButton.isEnabled = startButton.isEnabled && !debugging
        window?.toolbar?.validateVisibleItems()
    }

    /// "IntelliSense: SourceKit-LSP", or an offer to install the server for this language.
    private func updateIntelliSenseStatus() {
        guard let current, let spec = LanguageServerSpecs.spec(forLanguage: current.language.id) else {
            intelliButton.isHidden = true
            return
        }
        intelliButton.isHidden = false
        if current.session != nil {
            intelliButton.title = "IntelliSense: \(spec.name)"
            intelliButton.toolTip = "Completions (⌃Space), hover info, Go to Definition (F12), Find All References (⇧F12), Rename (F2)"
        } else if current.url == nil {
            intelliButton.title = "IntelliSense: save the file first"
            intelliButton.toolTip = nil
        } else if LanguageServerManager.shared.installCommand(for: spec) != nil {
            intelliButton.title = "Install \(current.language.name) IntelliSense…"
            intelliButton.toolTip = "Installs \(spec.name) into CodeForge's own folder"
        } else {
            intelliButton.title = "IntelliSense: \(spec.name) not found"
            intelliButton.toolTip = spec.installHint
        }
    }

    @objc private func intelliButtonClicked(_ sender: Any?) {
        guard let current, let spec = LanguageServerSpecs.spec(forLanguage: current.language.id), current.session == nil else { return }
        guard let command = LanguageServerManager.shared.installCommand(for: spec) else {
            return Prompt.show("\(spec.name) isn't installed", message: spec.installHint, style: .informational)
        }
        let message = spec.dotnetTool != nil
            ? "CodeForge will use the .NET SDK to download \(spec.name) into its own folder (about 30 MB)."
            : "CodeForge will run npm to download \(spec.npmPackages.joined(separator: ", ")) into its own folder (about 50 MB). You need Node.js (brew install node)."
        guard Prompt.confirm("Install \(spec.name)?", message: message, button: "Install") else { return }
        pendingInstall = spec
        start(command, in: FileManager.default.homeDirectoryForCurrentUser)
    }

    @objc func goToDefinition(_ sender: Any?) {
        guard let current else { return }
        intelliSense.textView(current.textView, goToDefinitionAt: current.textView.selectedRange().location)
    }

    @objc func findAllReferences(_ sender: Any?) {
        if let current { intelliSense.findReferences(in: current.textView) }
    }

    @objc func renameSymbol(_ sender: Any?) {
        if let current { intelliSense.rename(in: current.textView, documents: documents) }
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
        if let saved = defaults.dictionary(forKey: "breakpoints") as? [String: [Int]] {
            breakpoints = saved.mapValues(Set.init)
        }
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
        explorerPane.isHidden.toggle()
        defaults.set(explorerPane.isHidden, forKey: "explorerHidden")
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
        // Like Visual Studio's startup project: Start runs the whole project when the file belongs to it.
        if let plan = projectRunPlan, let run = plan.run {
            saveAllDocuments(nil)
            runningLanguage = nil
            return start(run, in: URL(fileURLWithPath: plan.folder))
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
    private var openedBrowserForRun = false

    /// The detected project, when Start should run it instead of the current file.
    private var projectRunPlan: BuildPlan? {
        guard let workspaceURL, let plan = BuildSystem.detect(in: workspaceURL), plan.run != nil else { return nil }
        guard let current else { return plan }
        return plan.languages.contains(current.language.id) ? plan : nil
    }

    /// ASP.NET (and other web servers) print the address they listen on; open it once, like Visual Studio does.
    private func openBrowserIfServerStarted(_ text: String) {
        guard !openedBrowserForRun, let range = text.range(of: #"Now listening on: (http://[^\s]+)"#, options: .regularExpression) else { return }
        let address = text[range].replacingOccurrences(of: "Now listening on: ", with: "")
        guard let url = URL(string: address.replacingOccurrences(of: "[::]", with: "localhost").replacingOccurrences(of: "0.0.0.0", with: "localhost")) else { return }
        openedBrowserForRun = true
        console.append("Opening \(url.absoluteString) in your browser…\n", .info)
        #if DEBUG
        if ProcessInfo.processInfo.environment["CF_NO_BROWSER"] != nil { return }
        #endif
        NSWorkspace.shared.open(url)
    }

    private func start(_ command: String, in folder: URL) {
        runningLanguage = defaults.string(forKey: customCommandKey ?? "")?.isEmpty == false ? nil : current?.language
        setConsoleVisible(true)
        panel.show(.output)
        console.clear(nil)
        console.append("$ \(command)\n", .info)
        runStatus.stringValue = "Running…"
        runFolder = folder
        openedBrowserForRun = false
        isRunning = true
        runDiagnostics = []
        refreshDiagnostics()
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
        runDiagnostics = diagnostics
        refreshDiagnostics()
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
        if let next = afterBuild {
            afterBuild = nil
            if status == 0 { next() }
        }
        git.refresh()
        if let spec = pendingInstall {
            pendingInstall = nil
            if status == 0 {
                console.append("\n\(spec.name) is installed. IntelliSense is on for \(spec.languages.joined(separator: ", ")) files.\n", .info)
                documents.filter { spec.languages.contains($0.language.id) }.forEach(attachLanguageServer)
                refreshChrome()
            }
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
            if let command = ProjectTemplates.creationCommand(for: template, named: name) {
                // .NET templates come from `dotnet new`; open the project once it has been created.
                let folder = location.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: folder.path) else {
                    return Prompt.show("“\(name)” already exists", message: "Choose a different name or location.")
                }
                afterBuild = { [weak self] in
                    self?.setWorkspace(folder)
                    self?.open(folder.appendingPathComponent(ProjectTemplates.mainFile(of: template, named: name)))
                }
                runningLanguage = Languages.language(id: "csharp")
                start(command, in: location)
                runStatus.stringValue = "Creating \(template.name)…"
                return
            }
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

    // MARK: Build

    private func buildKey(_ name: String) -> String? { workspaceURL.map { name + ":" + $0.path } }

    private var outputDirectory: URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CodeForge").appendingPathComponent("build")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The project's custom build command, its detected build system, or the current file on its own.
    private func buildPlan() -> BuildPlan? {
        if let workspaceURL, let key = buildKey("buildCommand"), let command = defaults.string(forKey: key) {
            return BuildPlan(name: "custom command", build: command, program: nil, folder: workspaceURL.path)
        }
        if let workspaceURL, let plan = BuildSystem.detect(in: workspaceURL) { return plan }
        guard let current, let file = current.url else { return nil }
        return BuildSystem.singleFile(file, languageId: current.language.id, outputDirectory: outputDirectory)
    }

    @objc func buildProject(_ sender: Any?) {
        build { [weak self] in self?.runStatus.stringValue = "Build succeeded" }
    }

    private func build(then next: @escaping () -> Void) {
        saveAllDocuments(nil)
        if let current, current.url == nil { guard saveAs(current) else { return } }
        guard let plan = buildPlan() else {
            return Prompt.show("Nothing to build", message: "Open a project folder or a source file, or set a build command with Build ▸ Set Build Command….")
        }
        afterBuild = next
        start(plan.build, in: URL(fileURLWithPath: plan.folder))
        runStatus.stringValue = "Building \(plan.name)…"
    }

    @objc func cleanProject(_ sender: Any?) {
        guard let plan = buildPlan(), let clean = plan.clean else {
            return Prompt.show("Nothing to clean", message: "This project type has no clean step.")
        }
        start(clean, in: URL(fileURLWithPath: plan.folder))
    }

    @objc func editBuildCommand(_ sender: Any?) {
        guard let key = buildKey("buildCommand") else {
            return Prompt.show("Open a folder first", message: "A build command is saved for each project folder.")
        }
        let detected = workspaceURL.flatMap(BuildSystem.detect(in:))
        let message = "Runs in the project folder for Build (⇧⌘B) and before debugging. Leave it empty to use "
            + (detected.map { "the detected \($0.name) build: \($0.build)" } ?? "the current file's compiler") + "."
        guard let command = Prompt.ask("Build Command", message: message, defaultValue: defaults.string(forKey: key) ?? "", confirm: "Save") else { return }
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        trimmed.isEmpty ? defaults.removeObject(forKey: key) : defaults.set(trimmed, forKey: key)
    }

    // MARK: Debug

    @objc func startDebugging(_ sender: Any?) {
        if let debugSession, debugSession.state == .paused { return debugSession.resume() }
        guard debugSession == nil, !isRunning else { return }
        if current?.language.id == "python" { return startPythonDebugging() }
        if let language = current?.language.id, ["javascript", "typescript", "ruby", "php", "shell"].contains(language), buildPlan()?.program == nil {
            return Prompt.show("Debugging isn't available for \(current!.language.name) yet",
                               message: "CodeForge debugs Python, and compiled programs (C, C++, Objective-C, Swift, Rust and Go) with LLDB. Use Start (⌘R) to run this file.")
        }
        build { [weak self] in self?.launchDebugger() }
    }

    /// Python runs under debugpy; it's installed (once, with the user's OK) the first time.
    private func startPythonDebugging() {
        guard let document = current else { return }
        guard document.url != nil || saveAs(document), let file = document.url else { return }
        saveAllDocuments(nil)
        let folder = workspaceURL.flatMap { file.path.hasPrefix($0.path + "/") ? $0 : nil } ?? file.deletingLastPathComponent()
        let launch = { [weak self] in
            guard let self, let configuration = DebugConfiguration.python(file: file, folder: folder) else {
                return Prompt.show("Couldn't start the Python debugger", message: "CodeForge needs python3 and the debugpy package.")
            }
            startSession(configuration, title: file.lastPathComponent)
        }
        if PythonDebugging.isInstalled { return launch() }
        guard let command = PythonDebugging.installCommand else {
            return Prompt.show("Python wasn't found", message: "Install Python 3 (for example: brew install python), then try again.")
        }
        guard Prompt.confirm("Install the Python debugger?", message: "CodeForge will use pip to download debugpy (about 20 MB) into its own folder. This happens once.",
                             button: "Install") else { return }
        afterBuild = launch
        start(command, in: FileManager.default.homeDirectoryForCurrentUser)
        runStatus.stringValue = "Installing debugpy…"
    }

    private func launchDebugger() {
        let customProgram = buildKey("debugProgram").flatMap { defaults.string(forKey: $0) }
        guard let path = customProgram ?? buildPlan()?.program, FileManager.default.isExecutableFile(atPath: path) else {
            return chooseDebugProgram(thenStart: true)
        }
        let folder = workspaceURL ?? URL(fileURLWithPath: path).deletingLastPathComponent()
        guard let configuration = DebugConfiguration.lldb(program: URL(fileURLWithPath: path), folder: folder) else {
            return Prompt.show("Couldn't start the debugger", message: "CodeForge uses lldb-dap from Xcode. Install Xcode, then run: xcode-select -s /Applications/Xcode.app")
        }
        startSession(configuration, title: path)
    }

    private func startSession(_ configuration: DebugConfiguration, title: String) {
        let session = DebugSession(configuration)
        session.breakpoints = { [weak self] in
            Dictionary(uniqueKeysWithValues: (self?.breakpoints ?? [:]).map { (URL(fileURLWithPath: $0.key), $0.value) })
        }
        session.onOutput = { [weak self] text, kind in self?.console.append(text, kind) }
        session.onStopped = { [weak self] in self?.debuggerStopped() }
        session.onStateChange = { [weak self] in self?.debugStateChanged() }
        console.append("\nDebugging \(title)\n", .info)
        guard session.start() else {
            return Prompt.show("Couldn't start the debugger", message: "The debug adapter (\(configuration.adapter.lastPathComponent)) didn't start.")
        }
        debugSession = session
        panel.debug.session = session
        panel.debug.onSelectFrame = { [weak self] frame in self?.selectFrame(frame) }
        panel.debug.onEvaluate = { [weak self] expression in
            self?.debugSession?.evaluate(expression, frame: self?.selectedFrame?.id) { self?.panel.debug.showResult($0) }
        }
        debugBar.isHidden = false
        debugBarHeight.constant = 30
        debugStateChanged()
    }

    private func debuggerStopped() {
        guard let session = debugSession else { return }
        selectFrame(session.frames.first { $0.file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false } ?? session.frames.first)
        showPanelTab(.debug)
        NSApp.activate()
    }

    private func selectFrame(_ frame: DebugSession.Frame?) {
        guard let session = debugSession, let frame else { return }
        selectedFrame = frame
        documents.forEach { $0.setExecutionLine(nil) }
        if let file = frame.file, FileManager.default.fileExists(atPath: file.path) {
            open(file)
            current?.setExecutionLine(frame.line)
        }
        session.locals(frame: frame.id) { [weak self] variables in
            guard let self else { return }
            panel.debug.show(frames: session.frames, selected: session.frames.firstIndex { $0.id == frame.id } ?? 0, variables: variables)
        }
    }

    private func debugStateChanged() {
        guard let session = debugSession else { return }
        debugBar.update(session.state, reason: session.stopReason)
        if session.state == .running { documents.forEach { $0.setExecutionLine(nil) } }
        if session.state == .ended {
            debugSession = nil
            selectedFrame = nil
            documents.forEach { $0.setExecutionLine(nil) }
            panel.debug.clear()
            debugBar.isHidden = true
            debugBarHeight.constant = 0
            runStatus.stringValue = "Debugging ended"
        } else {
            runStatus.stringValue = session.state == .paused ? "Paused" : "Debugging…"
        }
        updateRunChrome()
    }

    @objc func stopDebugging(_ sender: Any?) { debugSession?.stop() }
    @objc func debugContinue(_ sender: Any?) { debugSession?.resume() }
    @objc func debugPause(_ sender: Any?) { debugSession?.pause() }
    @objc func debugStepOver(_ sender: Any?) { debugSession?.stepOver() }
    @objc func debugStepInto(_ sender: Any?) { debugSession?.stepInto() }
    @objc func debugStepOut(_ sender: Any?) { debugSession?.stepOut() }

    @objc func setDebugProgram(_ sender: Any?) {
        chooseDebugProgram(thenStart: false)
    }

    private func chooseDebugProgram(thenStart: Bool) {
        guard let key = buildKey("debugProgram") else {
            return Prompt.show("No program to debug", message: "The build didn't produce a program CodeForge could find. Open the project folder, or debug a single C, C++, Swift or Rust file.")
        }
        let panel = NSOpenPanel()
        panel.message = "Choose the program to debug. CodeForge remembers it for this folder."
        panel.directoryURL = workspaceURL
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(url.path, forKey: key)
        if thenStart { launchDebugger() }
    }

    @objc func toggleBreakpointAtCursor(_ sender: Any?) {
        guard let current else { return }
        toggleBreakpoint(in: current, line: current.cursorPosition.line)
    }

    private func toggleBreakpoint(in document: EditorDocument, line: Int) {
        guard let url = document.url?.standardizedFileURL else { return NSSound.beep() }
        var lines = breakpoints[url.path] ?? []
        if lines.contains(line) { lines.remove(line) } else { lines.insert(line) }
        breakpoints[url.path] = lines.isEmpty ? nil : lines
        document.ruler.breakpoints = lines
        debugSession?.sendBreakpoints(for: url, lines: lines)
        saveBreakpoints()
    }

    @objc func deleteAllBreakpoints(_ sender: Any?) {
        for (path, _) in breakpoints { debugSession?.sendBreakpoints(for: URL(fileURLWithPath: path), lines: []) }
        breakpoints = [:]
        documents.forEach { $0.ruler.breakpoints = [] }
        saveBreakpoints()
    }

    private func saveBreakpoints() {
        defaults.set(breakpoints.mapValues { Array($0) }, forKey: "breakpoints")
    }

    // MARK: Git and CodeLens

    @objc func showGitChanges(_ sender: Any?) {
        if explorerPane.isHidden { toggleExplorer(nil) }
        sidebar.show(1)
    }

    @objc func showGitHistory(_ sender: Any?) {
        git.showHistory()
    }

    private func updateBranchButton(_ status: GitStatus?) {
        guard let status else { branchButton.isHidden = true; return }
        var title = " " + status.branch
        if status.ahead > 0 { title += " ↑\(status.ahead)" }
        if status.behind > 0 { title += " ↓\(status.behind)" }
        if !status.changes.isEmpty { title += "  ✎\(status.changes.count)" }
        branchButton.title = title
        branchButton.toolTip = "Git: \(status.changes.count) changed file\(status.changes.count == 1 ? "" : "s"). Click to open Git Changes."
        branchButton.isHidden = false
    }

    /// Opens text that isn't a file (a diff, the history) in a read-only tab.
    private func openReadOnly(title: String, text: String, languageId: String) {
        if let index = documents.firstIndex(where: { $0.url == nil && $0.displayName == title }) {
            documents.remove(at: index)
        }
        let document = EditorDocument(url: nil, text: text, fontSize: fontSize, untitledName: title)
        document.language = Languages.language(id: languageId) ?? Languages.plainText
        document.textView.isEditable = false
        document.onStateChange = { [weak self] in self?.refreshChrome() }
        documents.append(document)
        select(documents.count - 1)
    }

    private var showsCodeLens: Bool { defaults.object(forKey: "showCodeLens") as? Bool ?? true }

    @objc func toggleCodeLens(_ sender: Any?) {
        defaults.set(!showsCodeLens, forKey: "showCodeLens")
        documents.forEach(updateCodeLens)
    }

    /// CodeLens: "3 references | Ahmed, 2 days ago" after each function and type, from the language server and git blame.
    private func updateCodeLens(_ document: EditorDocument) {
        guard showsCodeLens, !document.isDirty, let session = document.session, let url = document.url else {
            document.textView.lenses = [:]
            return
        }
        let countsReferences = session.server.spec.id != "sourcekit-lsp" || workspaceURL.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".build").path) } == true
        session.symbols { [weak document] symbols in
            guard let document, !document.isDirty else { return }
            let symbols = Array(symbols.prefix(60))
            Git.run(["blame", "--line-porcelain", "--", url.lastPathComponent], in: url.deletingLastPathComponent()) { [weak document] result in
                guard let document, !document.isDirty else { return }
                let blame = result.succeeded ? GitBlame.parse(result.output) : [:]
                var lenses: [Int: String] = [:]
                var remaining = symbols.count
                func finish() {
                    remaining -= 1
                    if remaining <= 0, !document.isDirty { document.textView.lenses = lenses }
                }
                guard !symbols.isEmpty else { return document.textView.lenses = [:] }
                for symbol in symbols {
                    var parts: [String] = []
                    if let change = GitBlame.latest(in: blame, lines: symbol.line...max(symbol.line, symbol.endLine)) {
                        parts.append(change.isUncommitted ? "Not committed yet" : "\(change.author), \(RelativeTime.describe(change.time))")
                    }
                    guard countsReferences else {
                        if !parts.isEmpty { lenses[symbol.line] = parts.joined(separator: "  |  ") }
                        finish()
                        continue
                    }
                    session.referenceCount(line: symbol.line, character: symbol.character) { count in
                        parts.insert("\(count) reference\(count == 1 ? "" : "s")", at: 0)
                        lenses[symbol.line] = parts.joined(separator: "  |  ")
                        finish()
                    }
                }
            }
        }
    }

    #if DEBUG
    func documentForProbe(_ textView: CodeTextView) -> EditorDocument? { documents.first { $0.textView === textView } }
    func diagnosticsForProbe() -> [String] { liveDiagnostics.values.flatMap { $0 }.map { "\($0.line):\($0.column ?? 0) \($0.message)" } }
    #endif

    func stopAll() {
        debugSession?.stop()
        runner.stop()
        panel.terminal.stop()
        documents.forEach { $0.session = nil }
        LanguageServerManager.shared.stopAll()
    }

    // MARK: Validation

    private func isEnabled(_ action: Selector?) -> Bool {
        switch action {
        case #selector(stopRunning(_:)): runner.isRunning
        case #selector(runActiveFile(_:)): !isRunning && debugSession == nil
        case #selector(startDebugging(_:)): (!isRunning && debugSession == nil) || debugSession?.state == .paused
        case #selector(stopDebugging(_:)): debugSession != nil
        case #selector(debugContinue(_:)), #selector(debugStepOver(_:)), #selector(debugStepInto(_:)), #selector(debugStepOut(_:)):
            debugSession?.state == .paused
        case #selector(debugPause(_:)): debugSession?.state == .running
        case #selector(setDebugProgram(_:)), #selector(editBuildCommand(_:)), #selector(showGitChanges(_:)): workspaceURL != nil
        case #selector(showGitHistory(_:)): git.status != nil
        case #selector(deleteAllBreakpoints(_:)): !breakpoints.isEmpty
        case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)): current != nil
        case #selector(goToDefinition(_:)), #selector(findAllReferences(_:)), #selector(renameSymbol(_:)): current?.session != nil
        case #selector(saveAllDocuments(_:)): documents.contains { $0.isDirty }
        case #selector(closeFolder(_:)), #selector(editRunCommand(_:)): workspaceURL != nil
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)): documents.count > 1
        default: true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleExplorer(_:)) { menuItem.title = explorerPane.isHidden ? "Show Explorer" : "Hide Explorer" }
        if menuItem.action == #selector(toggleConsole(_:)) { menuItem.title = panel.isHidden ? "Show Panel" : "Hide Panel" }
        if menuItem.action == #selector(startDebugging(_:)) { menuItem.title = debugSession?.state == .paused ? "Continue" : "Start Debugging" }
        if menuItem.action == #selector(toggleCodeLens(_:)) { menuItem.state = showsCodeLens ? .on : .off }
        if menuItem.action == #selector(toggleToolbox(_:)) { menuItem.title = toolbox.isHidden ? "Show Toolbox" : "Hide Toolbox" }
        if menuItem.action == #selector(toggleProperties(_:)) { menuItem.title = properties.isHidden ? "Show Properties Window" : "Hide Properties Window" }
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
