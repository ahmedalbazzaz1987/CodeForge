import AppKit
import UniformTypeIdentifiers

/// A file or folder in the explorer. Folder contents are read the first time they are needed.
final class FileNode {
    let url: URL
    let isDirectory: Bool
    private var loaded: [FileNode]?

    private static let hidden: Set<String> = [".DS_Store", ".git", ".build", ".swiftpm", "__pycache__", ".Trash"]

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var name: String { url.lastPathComponent }

    var children: [FileNode] {
        if let loaded { return loaded }
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let nodes = urls
            .filter { !Self.hidden.contains($0.lastPathComponent) }
            .map { FileNode(url: $0, isDirectory: (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
            .sorted { a, b in
                a.isDirectory != b.isDirectory ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        loaded = nodes
        return nodes
    }
}

/// The explorer sidebar: the open folder's files, with a context menu for file operations.
final class FileTreeView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    var onOpenFile: ((URL) -> Void)?
    var onOpenFolder: (() -> Void)?
    var onRenamed: ((URL, URL) -> Void)?
    var onTrashed: ((URL) -> Void)?

    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private let title = NSTextField(labelWithString: "")
    private let emptyState = NSStackView()
    private var root: FileNode?
    private var icons: [String: NSImage] = [:]
    private var suppressOpen = false

    var rootURL: URL? { root?.url }

    override init(frame: NSRect) {
        super.init(frame: frame)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        let newFile = Self.iconButton("doc.badge.plus", "New File", #selector(newFileFromHeader), self)
        let refresh = Self.iconButton("arrow.clockwise", "Refresh", #selector(reload), self)
        let header = NSStackView(views: [title, NSView(), newFile, refresh])
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)

        let hint = NSTextField(wrappingLabelWithString: "No folder is open.")
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        let open = NSButton(title: "Open Folder…", target: self, action: #selector(openFolderClicked))
        emptyState.setViews([hint, open], in: .center)
        emptyState.orientation = .vertical
        emptyState.spacing = 10

        for view in [header, scroll, emptyState] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 30),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyState.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyState.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
        ])
        setRoot(nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static func iconButton(_ symbol: String, _ tip: String, _ action: Selector, _ target: AnyObject?) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: target, action: action)
        button.isBordered = false
        button.toolTip = tip
        button.contentTintColor = .secondaryLabelColor
        return button
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.sidebar.setFill()
        bounds.fill()
    }

    func setRoot(_ url: URL?) {
        root = url.map { FileNode(url: $0, isDirectory: true) }
        title.stringValue = url?.lastPathComponent.uppercased() ?? "EXPLORER"
        emptyState.isHidden = url != nil
        scroll.isHidden = url == nil
        outline.reloadData()
    }

    /// Re-reads the folder from disk, keeping expanded folders expanded.
    @objc func reload() {
        guard let root else { return }
        let expanded = Set((0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? FileNode }.filter { outline.isItemExpanded($0) }.map(\.url))
        let selected = (outline.item(atRow: outline.selectedRow) as? FileNode)?.url
        self.root = FileNode(url: root.url, isDirectory: true)
        outline.reloadData()
        var row = 0
        while row < outline.numberOfRows {
            if let node = outline.item(atRow: row) as? FileNode, expanded.contains(node.url) { outline.expandItem(node) }
            row += 1
        }
        if let selected { select(selected) }
    }

    /// Expands the folders leading to `url` and selects it, without opening it again.
    func select(_ url: URL) {
        guard let root, url.path.hasPrefix(root.url.path + "/") else { return }
        var row = 0
        while row < outline.numberOfRows {
            guard let node = outline.item(atRow: row) as? FileNode else { break }
            if node.url == url {
                suppressOpen = true
                outline.selectRowIndexes([row], byExtendingSelection: false)
                outline.scrollRowToVisible(row)
                suppressOpen = false
                return
            }
            if node.isDirectory, url.path.hasPrefix(node.url.path + "/") { outline.expandItem(node) }
            row += 1
        }
    }

    // MARK: Data source and delegate

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? FileNode) ?? root)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? FileNode) ?? root)!.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier)
        cell.textField?.stringValue = node.name
        cell.imageView?.image = icon(for: node)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressOpen, let node = outline.item(atRow: outline.selectedRow) as? FileNode, !node.isDirectory else { return }
        onOpenFile?(node.url)
    }

    @objc private func doubleClicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? FileNode, node.isDirectory else { return }
        outline.isItemExpanded(node) ? outline.collapseItem(node) : outline.expandItem(node)
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let image = NSImageView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 12)
        for view in [image, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = image
        cell.textField = label
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func icon(for node: FileNode) -> NSImage {
        let key = node.isDirectory ? "/" : node.url.pathExtension.lowercased()
        if let cached = icons[key] { return cached }
        let type = node.isDirectory ? UTType.folder : (UTType(filenameExtension: key) ?? .plainText)
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: 16, height: 16)
        icons[key] = image
        return image
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard root != nil else { return }
        let node = outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as? FileNode : nil
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = node
        }
        add("New File…", #selector(newFile(_:)))
        add("New Folder…", #selector(newFolder(_:)))
        menu.addItem(.separator())
        if node != nil {
            add("Rename…", #selector(rename(_:)))
            add("Copy Path", #selector(copyPath(_:)))
        }
        add("Reveal in Finder", #selector(reveal(_:)))
        add("Open in Terminal", #selector(openInTerminal(_:)))
        if node != nil {
            menu.addItem(.separator())
            add("Move to Trash", #selector(moveToTrash(_:)))
        }
    }

    private func folder(for sender: Any?) -> URL? {
        guard let node = (sender as? NSMenuItem)?.representedObject as? FileNode else {
            if let selected = outline.item(atRow: outline.selectedRow) as? FileNode {
                return selected.isDirectory ? selected.url : selected.url.deletingLastPathComponent()
            }
            return root?.url
        }
        return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    @objc private func newFileFromHeader() { newFile(nil) }
    @objc private func openFolderClicked() { onOpenFolder?() }

    @objc func newFile(_ sender: Any?) {
        guard let folder = folder(for: sender), let url = askForNewItem(in: folder, kind: "File") else { return }
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            return Prompt.show("Couldn't create the file", message: url.path)
        }
        reload()
        select(url)
        onOpenFile?(url)
    }

    @objc private func newFolder(_ sender: Any?) {
        guard let folder = folder(for: sender), let url = askForNewItem(in: folder, kind: "Folder") else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            reload()
            select(url)
        } catch {
            Prompt.show("Couldn't create the folder", message: error.localizedDescription)
        }
    }

    private func askForNewItem(in folder: URL, kind: String) -> URL? {
        guard let name = Prompt.ask("New \(kind)", message: "In \(folder.lastPathComponent)", confirm: "Create")?
            .trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let url = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            Prompt.show("“\(name)” already exists", message: "Choose a different name.")
            return nil
        }
        return url
    }

    @objc private func rename(_ sender: Any?) {
        guard let node = (sender as? NSMenuItem)?.representedObject as? FileNode,
              let name = Prompt.ask("Rename", defaultValue: node.name, confirm: "Rename")?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, name != node.name else { return }
        let destination = node.url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: node.url, to: destination)
            onRenamed?(node.url, destination)
            reload()
        } catch {
            Prompt.show("Couldn't rename “\(node.name)”", message: error.localizedDescription)
        }
    }

    @objc private func copyPath(_ sender: Any?) {
        guard let node = (sender as? NSMenuItem)?.representedObject as? FileNode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }

    @objc private func reveal(_ sender: Any?) {
        let url = ((sender as? NSMenuItem)?.representedObject as? FileNode)?.url ?? root?.url
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc private func openInTerminal(_ sender: Any?) {
        guard let folder = folder(for: sender),
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func moveToTrash(_ sender: Any?) {
        guard let node = (sender as? NSMenuItem)?.representedObject as? FileNode,
              Prompt.confirm("Move “\(node.name)” to the Trash?", message: "You can restore it from the Trash in Finder.", button: "Move to Trash")
        else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            onTrashed?(node.url)
            reload()
        } catch {
            Prompt.show("Couldn't move “\(node.name)” to the Trash", message: error.localizedDescription)
        }
    }
}
