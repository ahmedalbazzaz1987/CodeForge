import AppKit
import CodeForgeKit

enum SymbolIcons {
    static func image(for kind: CodeSymbol.Kind) -> NSImage? {
        let (name, color): (String, NSColor) = switch kind {
        case .namespace: ("curlybraces.square.fill", .systemGray)
        case .module: ("square.stack.3d.up.fill", .systemOrange)
        case .class: ("c.square.fill", .systemOrange)
        case .structure: ("s.square.fill", .systemTeal)
        case .interface: ("i.square.fill", .systemCyan)
        case .enumeration: ("e.square.fill", .systemYellow)
        case .method, .function: ("m.square.fill", .systemPurple)
        case .constructor: ("plus.square.fill", .systemPurple)
        case .property: ("p.square.fill", .systemBlue)
        case .field, .variable: ("f.square.fill", .systemBlue)
        case .constant: ("number.square.fill", .systemGray)
        case .event: ("bolt.square.fill", .systemYellow)
        case .enumMember: ("e.square", .systemYellow)
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: kind.title)?.withSymbolConfiguration(.init(paletteColors: [color]))
    }
}

/// A row in Class View or the Object Browser.
final class SymbolNode {
    let title: String
    let kind: CodeSymbol.Kind
    let symbol: CodeSymbol?
    let dotNetType: DotNetType?
    var children: [SymbolNode]

    init(title: String, kind: CodeSymbol.Kind, symbol: CodeSymbol? = nil, dotNetType: DotNetType? = nil, children: [SymbolNode] = []) {
        self.title = title
        self.kind = kind
        self.symbol = symbol
        self.dotNetType = dotNetType
        self.children = children
    }

    /// Namespaces → types → members, from the project's symbols. Top-level functions are grouped by file.
    static func tree(_ symbols: [CodeSymbol], filter: String = "") -> [SymbolNode] {
        let query = filter.lowercased()
        func matches(_ name: String) -> Bool { query.isEmpty || name.lowercased().contains(query) }
        var namespaces: [String: [SymbolNode]] = [:]
        let types = symbols.filter { $0.kind.isType }
        var seenTypes = Set<String>()
        for type in types {
            let key = (type.namespace ?? "") + "|" + type.name
            guard seenTypes.insert(key).inserted else { continue }   // partial classes: one node
            let members = symbols.filter { !$0.kind.isType && $0.container == type.name && $0.namespace == type.namespace }
                .sorted { ($0.kind == .constructor ? 0 : 1, $0.name.lowercased()) < ($1.kind == .constructor ? 0 : 1, $1.name.lowercased()) }
            let shown = matches(type.name) ? members : members.filter { matches($0.name) }
            guard matches(type.name) || !shown.isEmpty else { continue }
            let node = SymbolNode(title: type.name, kind: type.kind, symbol: type, children: shown.map { SymbolNode(title: $0.name, kind: $0.kind, symbol: $0) })
            namespaces[type.namespace ?? "", default: []].append(node)
        }
        var result: [SymbolNode] = namespaces.keys.sorted().map { name in
            let children = namespaces[name]!.sorted { $0.title.lowercased() < $1.title.lowercased() }
            return SymbolNode(title: name.isEmpty ? "(Global)" : name, kind: .namespace, children: children)
        }
        // Functions and variables outside any type (Python, JavaScript, C#'s top-level statements…), by file.
        var loose: [String: [CodeSymbol]] = [:]
        for symbol in symbols where !symbol.kind.isType && symbol.container == nil && symbol.kind != .namespace && matches(symbol.name) {
            loose[symbol.url?.lastPathComponent ?? "Untitled", default: []].append(symbol)
        }
        for file in loose.keys.sorted() {
            result.append(SymbolNode(title: file, kind: .module, children: loose[file]!.map { SymbolNode(title: $0.name, kind: $0.kind, symbol: $0) }))
        }
        if result.count == 1, result[0].kind == .namespace, result[0].title == "(Global)" { return result[0].children }
        return result
    }
}

/// Class View (⇧⌘C): the project's namespaces, classes and their members. Double-click to go to the code.
final class ClassView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    var onOpen: ((URL, Int) -> Void)?
    private var roots: [SymbolNode] = []
    private let outline = NSOutlineView()
    private let search = NSSearchField()
    private let status = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        search.placeholderString = "Search Class View"
        search.controlSize = .small
        search.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("symbol"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(openSelected)
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        status.alignment = .center
        status.lineBreakMode = .byWordWrapping
        for view in [search, scroll, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func reload() {
        let index = ProjectIndex.shared
        roots = SymbolNode.tree(index.symbols, filter: search.stringValue)
        outline.reloadData()
        // Show the first level open, or everything while searching.
        if search.stringValue.isEmpty {
            roots.forEach { outline.expandItem($0) }
        } else {
            outline.expandItem(nil, expandChildren: true)
        }
        status.isHidden = !roots.isEmpty
        status.stringValue = index.isIndexing ? "Reading the project…" : search.stringValue.isEmpty ? "Open a project folder to see its classes." : "No matches."
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SymbolNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SymbolNode)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? SymbolNode)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SymbolNode else { return nil }
        return Self.cell(for: node)
    }

    static func cell(for node: SymbolNode) -> NSView {
        let cell = NSTableCellView()
        let image = NSImageView(image: SymbolIcons.image(for: node.kind) ?? NSImage())
        let label = NSTextField(labelWithString: node.title)
        label.font = .systemFont(ofSize: 12, weight: node.kind.isType || node.kind == .namespace ? .medium : .regular)
        label.lineBreakMode = .byTruncatingTail
        if let type = node.symbol?.type, !node.kind.isType {
            let detail = NSMutableAttributedString(string: node.title, attributes: [.font: label.font!])
            detail.append(NSAttributedString(string: "  " + type, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            label.attributedStringValue = detail
        }
        cell.toolTip = node.symbol?.signature ?? node.dotNetType?.qualifiedName
        for view in [image, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func openSelected() {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard let node = outline.item(atRow: row) as? SymbolNode, let symbol = node.symbol, let url = symbol.url else { return }
        onOpen?(url, symbol.line)
    }
}

/// View ▸ Object Browser (⌥⌘J): the project's types and common .NET classes, their members and declarations.
final class ObjectBrowserWindow: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let shared = ObjectBrowserWindow()
    var onOpen: ((URL, Int) -> Void)?

    private lazy var window: NSWindow = makeWindow()
    private let search = NSSearchField()
    private let outline = NSOutlineView()
    private let members = NSTableView()
    private let details = NSTextView()
    private var roots: [SymbolNode] = []
    private var shownMembers: [(kind: CodeSymbol.Kind, name: String, signature: String, symbol: CodeSymbol?)] = []
    private var selectedNode: SymbolNode?

    func show() {
        _ = window
        reload()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: true)
        window.title = "Object Browser"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CodeForgeObjectBrowser")
        search.placeholderString = "Search types and members"
        search.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(openNode)

        let memberColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("member"))
        memberColumn.title = "Members"
        members.addTableColumn(memberColumn)
        members.headerView = nil
        members.style = .plain
        members.rowHeight = 20
        members.dataSource = self
        members.delegate = self
        members.target = self
        members.doubleAction = #selector(openMember)

        details.isEditable = false
        details.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        details.textContainerInset = NSSize(width: 8, height: 8)
        details.backgroundColor = Theme.sidebar

        func scroll(_ view: NSView) -> NSScrollView {
            let scroll = NSScrollView()
            scroll.documentView = view
            scroll.hasVerticalScroller = true
            scroll.borderType = .noBorder
            return scroll
        }
        let detailScroll = scroll(details)
        details.autoresizingMask = [.width]
        details.isVerticallyResizable = true
        let right = NSSplitView()
        right.isVertical = false
        right.dividerStyle = .thin
        right.addArrangedSubview(scroll(members))
        right.addArrangedSubview(detailScroll)
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(scroll(outline))
        split.addArrangedSubview(right)

        let content = NSView()
        for view in [search, split] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            search.widthAnchor.constraint(equalToConstant: 300),
            split.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.center()
        content.layoutSubtreeIfNeeded()
        split.setPosition(300, ofDividerAt: 0)
        right.setPosition(330, ofDividerAt: 0)
        return window
    }

    func reload() {
        guard window.isVisible || roots.isEmpty else { return refill() }
        refill()
    }

    private func refill() {
        let query = search.stringValue.lowercased()
        // The project's namespaces and types; members are listed on the right.
        func typesOnly(_ nodes: [SymbolNode]) -> [SymbolNode] {
            nodes.compactMap { node in
                if node.symbol == nil, node.kind == .namespace { return SymbolNode(title: node.title, kind: .namespace, children: typesOnly(node.children)) }
                return node.symbol.map { SymbolNode(title: node.title, kind: node.kind, symbol: $0) }
            }
        }
        let project = SymbolNode(title: "My Project", kind: .namespace, children: typesOnly(SymbolNode.tree(ProjectIndex.shared.symbols)))
        var byNamespace: [String: [SymbolNode]] = [:]
        for type in DotNetCatalog.types {
            byNamespace[type.namespace, default: []].append(SymbolNode(title: type.name, kind: type.kind, dotNetType: type))
        }
        let framework = SymbolNode(title: ".NET (common classes)", kind: .namespace, children: byNamespace.keys.sorted().map {
            SymbolNode(title: $0, kind: .namespace, children: byNamespace[$0]!.sorted { $0.title < $1.title })
        })
        roots = [project, framework]
        if !query.isEmpty {
            // Keep the types whose name, or one of whose members' names, contains the text.
            func keep(_ node: SymbolNode) -> SymbolNode? {
                if node.kind == .namespace {
                    let children = node.children.compactMap(keep)
                    return children.isEmpty ? nil : SymbolNode(title: node.title, kind: node.kind, children: children)
                }
                if node.title.lowercased().contains(query) { return node }
                let names = node.dotNetType?.members.map(\.name) ?? ProjectIndex.shared.symbols.filter { $0.container == node.title }.map(\.name)
                return names.contains { $0.lowercased().contains(query) } ? node : nil
            }
            roots = roots.compactMap(keep)
        }
        outline.reloadData()
        if query.isEmpty { roots.forEach { outline.expandItem($0) } } else { outline.expandItem(nil, expandChildren: true) }
        selectedNode = nil
        shownMembers = []
        members.reloadData()
        details.string = "Select a type to see its members."
    }

    func controlTextDidChange(_ obj: Notification) { refill() }

    // Types tree

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? SymbolNode)?.children.count ?? roots.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? SymbolNode)?.children[index] ?? roots[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? SymbolNode)?.children.isEmpty ?? true) }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        (item as? SymbolNode).map(ClassView.cell(for:))
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let node = outline.item(atRow: outline.selectedRow) as? SymbolNode, node.kind != .namespace || node.symbol != nil else { return }
        selectedNode = node
        let query = search.stringValue.lowercased()
        if let type = node.dotNetType {
            shownMembers = type.members.map { (($0.isMethod ? CodeSymbol.Kind.method : .property), $0.name, ($0.isShared ? "Shared " : "") + $0.signature, nil) }
            details.string = "\(type.kind.title) \(type.name)\n    Member of \(type.namespace)\n\n\(type.members.count) members in CodeForge's catalog of common .NET classes."
        } else if let symbol = node.symbol {
            shownMembers = ProjectIndex.shared.symbols.filter { $0.container == symbol.name && $0.namespace == symbol.namespace && !$0.kind.isType }
                .map { ($0.kind, $0.name, $0.signature, $0) }
            details.string = describe(symbol)
        }
        if !query.isEmpty, !(node.title.lowercased().contains(query)) {
            shownMembers = shownMembers.filter { $0.name.lowercased().contains(query) }
        }
        members.reloadData()
    }

    private func describe(_ symbol: CodeSymbol) -> String {
        var text = symbol.signature + "\n"
        text += "    \(symbol.kind.title)" + (symbol.container.map { " in \($0)" } ?? "") + (symbol.namespace.map { ", namespace \($0)" } ?? "") + "\n"
        if let type = symbol.type { text += "    Type: \(type)\n" }
        if let url = symbol.url { text += "\n\(url.lastPathComponent), line \(symbol.line)\nDouble-click to go to the code." }
        return text
    }

    // Members list

    func numberOfRows(in tableView: NSTableView) -> Int { shownMembers.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let member = shownMembers[row]
        return ClassView.cell(for: SymbolNode(title: member.signature, kind: member.kind, symbol: nil))
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard shownMembers.indices.contains(members.selectedRow) else { return }
        let member = shownMembers[members.selectedRow]
        if let symbol = member.symbol {
            details.string = describe(symbol)
        } else if let type = selectedNode?.dotNetType {
            details.string = member.signature + "\n    Member of \(type.qualifiedName)"
        }
    }

    @objc private func openNode() {
        guard let node = outline.item(atRow: outline.clickedRow) as? SymbolNode, let symbol = node.symbol, let url = symbol.url else { return }
        onOpen?(url, symbol.line)
    }

    @objc private func openMember() {
        guard shownMembers.indices.contains(members.clickedRow), let symbol = shownMembers[members.clickedRow].symbol, let url = symbol.url else { return }
        onOpen?(url, symbol.line)
    }
}
