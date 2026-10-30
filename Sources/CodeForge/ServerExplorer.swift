import AppKit
import CodeForgeKit

/// The Query Results tab: rows from Server Explorer queries.
final class QueryResultsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let summary = NSTextField(labelWithString: "Run a query with Tools ▸ Execute Query (⇧⌘E), or double-click a table in Server Explorer.")
    private var result = QueryResult()

    override init(frame: NSRect) {
        super.init(frame: frame)
        table.style = .plain
        table.rowHeight = 20
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = true
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        summary.textColor = .secondaryLabelColor
        summary.font = .systemFont(ofSize: 11)
        summary.lineBreakMode = .byTruncatingTail
        for view in [summary, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            summary.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            summary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ result: QueryResult, title: String) {
        self.result = result
        table.tableColumns.forEach(table.removeTableColumn)
        let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        for (index, name) in result.columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)"))
            column.title = name
            // Wide enough for the title and the first rows' values.
            let widest = result.rows.prefix(100).map { ($0.indices.contains(index) ? $0[index] ?? "NULL" : "") as NSString }
                .map { $0.size(withAttributes: [.font: font]).width }.max() ?? 0
            column.width = min(max(widest, (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width) + 20, 360)
            table.addTableColumn(column)
        }
        summary.stringValue = "\(title) — \(result.message)"
        summary.textColor = .secondaryLabelColor
        table.reloadData()
    }

    func showError(_ message: String, title: String) {
        show(QueryResult(), title: title)
        summary.stringValue = "\(title) — \(message)"
        summary.textColor = Theme.errorRed
    }

    func clear() { show(QueryResult(message: "No results."), title: "Query Results") }

    func numberOfRows(in tableView: NSTableView) -> Int { result.rows.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let index = column.flatMap({ Int($0.identifier.rawValue) }), result.rows[row].indices.contains(index) else { return nil }
        let value = result.rows[row][index]
        let field = NSTextField(labelWithString: value ?? "NULL")
        field.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        field.textColor = value == nil ? .tertiaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = value
        return field
    }
}

/// Runs queries for Server Explorer: SQLite directly, servers through their command-line client.
enum DatabaseService {
    /// Passwords typed this session, by connection id. They're never saved.
    static var passwords: [String: String] = [:]

    static func run(_ sql: String, on connection: DataConnection, completion: @escaping (Result<QueryResult, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<QueryResult, Error>
            if connection.kind == .sqlite {
                result = Result { try SQLiteDatabase(path: (connection.location as NSString).expandingTildeInPath).execute(sql) }
            } else {
                result = runClient(sql, on: connection)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func tables(of connection: DataConnection, completion: @escaping (Result<[DatabaseTable], Error>) -> Void) {
        if connection.kind == .sqlite {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try SQLiteDatabase(path: (connection.location as NSString).expandingTildeInPath).tables() }
                DispatchQueue.main.async { completion(result) }
            }
            return
        }
        run(DatabaseClient.tablesQuery(connection.kind), on: connection) { result in
            completion(result.map { $0.rows.map { DatabaseTable(name: $0[0] ?? "", isView: ($0.count > 1 ? $0[1] ?? "" : "").uppercased().contains("VIEW")) } })
        }
    }

    static func columns(of table: String, in connection: DataConnection, completion: @escaping ([(name: String, type: String, isKey: Bool)]) -> Void) {
        run(DatabaseClient.columnsQuery(connection.kind, table: table), on: connection) { result in
            let rows = (try? result.get().rows) ?? []
            completion(rows.map { row in
                let value = { (i: Int) in row.indices.contains(i) ? row[i] ?? "" : "" }
                return (value(0), value(1), ["YES", "1"].contains(value(2).uppercased()))
            })
        }
    }

    private static func runClient(_ sql: String, on connection: DataConnection) -> Result<QueryResult, Error> {
        guard let (executable, arguments) = DatabaseClient.command(for: connection, sql: sql) else { return .failure(DatabaseError("Unsupported connection.")) }
        let environment = LanguageServerManager.environment
        let folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/homebrew/opt/libpq/bin", "/opt/homebrew/opt/mysql-client/bin", "/usr/local/opt/libpq/bin"]
        guard let path = folders.map({ $0 + "/" + executable }).first(where: FileManager.default.isExecutableFile) else {
            return .failure(DatabaseError("\(executable) wasn't found. \(connection.kind.installHint)"))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var env = environment
        if let variable = DatabaseClient.passwordVariable(connection.kind), let password = passwords[connection.id] { env[variable] = password }
        process.environment = env
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(error) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return .failure(DatabaseError(errorText.isEmpty ? "\(executable) failed (exit code \(process.terminationStatus))." : errorText))
        }
        return .success(DatabaseClient.parse(String(decoding: data, as: UTF8.self), kind: connection.kind))
    }
}

/// Server Explorer (⌥⌘S): data connections, their tables and views, and their columns.
final class ServerExplorerView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Node {
        enum Kind { case connection, folder, table, column }
        let kind: Kind
        let title: String
        let connection: DataConnection
        var table: DatabaseTable?
        var children: [Node]?      // nil until loaded
        var detail = ""

        init(_ kind: Kind, _ title: String, connection: DataConnection, table: DatabaseTable? = nil, children: [Node]? = nil) {
            self.kind = kind
            self.title = title
            self.connection = connection
            self.table = table
            self.children = children
        }
    }

    var onShowData: ((DataConnection, String) -> Void)?
    var onNewQuery: ((DataConnection) -> Void)?
    var onStatus: ((String) -> Void)?
    private(set) var connections: [DataConnection] = []
    private var roots: [Node] = []
    private let outline = NSOutlineView()
    private let empty = NSTextField(wrappingLabelWithString: "No data connections.\nClick + to connect to a SQLite file, PostgreSQL, MySQL or SQL Server.")

    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: "SERVER EXPLORER")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        let add = FileTreeView.iconButton("plus", "Add Connection…", #selector(addConnection), self)
        let query = FileTreeView.iconButton("doc.text.magnifyingglass", "New Query", #selector(newQuery), self)
        let refresh = FileTreeView.iconButton("arrow.clockwise", "Refresh", #selector(refreshSelected), self)
        let remove = FileTreeView.iconButton("minus", "Remove Connection", #selector(removeConnection), self)
        let header = NSStackView(views: [title, NSView(), add, query, refresh, remove])
        header.spacing = 6
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.menu = NSMenu()
        outline.menu?.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.font = .systemFont(ofSize: 12)
        for view in [header, scroll, empty] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        if let data = UserDefaults.standard.data(forKey: "dataConnections"), let saved = try? JSONDecoder().decode([DataConnection].self, from: data) {
            connections = saved
        }
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.sidebar.setFill()
        bounds.fill()
    }

    /// The connection of the selected row, or the only one there is.
    var selectedConnection: DataConnection? {
        (outline.item(atRow: outline.selectedRow) as? Node)?.connection ?? (connections.count == 1 ? connections[0] : nil)
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(connections), forKey: "dataConnections")
    }

    private func rebuild() {
        roots = connections.map { Node(.connection, $0.name, connection: $0) }
        outline.reloadData()
        empty.isHidden = !connections.isEmpty
    }

    /// Opens a connection's node (and its Tables folder).
    func expand(_ connection: DataConnection) {
        guard let node = roots.first(where: { $0.connection.id == connection.id }) else { return }
        outline.expandItem(node)
    }

    func add(_ connection: DataConnection) {
        connections.append(connection)
        save()
        rebuild()
        if let node = roots.last { outline.expandItem(node) }
    }

    @objc func addConnection() {
        guard let window else { return }
        AddConnectionSheet { [weak self] connection in self?.add(connection) }.show(in: window)
    }

    @objc private func newQuery() {
        guard let connection = selectedConnection else { return addConnection() }
        onNewQuery?(connection)
    }

    @objc private func removeConnection() {
        guard let node = outline.item(atRow: outline.selectedRow) as? Node else { return NSSound.beep() }
        guard Prompt.confirm("Remove “\(node.connection.name)”?", message: "Only the connection is removed from Server Explorer; the database isn't changed.", button: "Remove") else { return }
        connections.removeAll { $0.id == node.connection.id }
        save()
        rebuild()
    }

    @objc private func refreshSelected() {
        guard let node = outline.item(atRow: outline.selectedRow) as? Node else { return rebuild() }
        let root = roots.first { $0.connection.id == node.connection.id } ?? node
        root.children = nil
        outline.reloadItem(root, reloadChildren: true)
        outline.expandItem(root)
    }

    @objc private func doubleClicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? Node else { return }
        if node.kind == .table, let table = node.table { onShowData?(node.connection, table.name) }
    }

    /// Server databases may need a password; ask once per session.
    private func ensurePassword(_ connection: DataConnection) -> Bool {
        guard connection.kind != .sqlite, !connection.user.isEmpty, DatabaseService.passwords[connection.id] == nil else { return true }
        let alert = NSAlert()
        alert.messageText = "Password for \(connection.user)@\(connection.location)"
        alert.informativeText = "CodeForge keeps it only until you quit. Leave it empty if the server doesn't need one."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        DatabaseService.passwords[connection.id] = field.stringValue
        return true
    }

    func prepare(_ connection: DataConnection) -> Bool { ensurePassword(connection) }

    private func load(_ node: Node) {
        guard node.children == nil else { return }
        node.children = []
        switch node.kind {
        case .connection:
            guard ensurePassword(node.connection) else { node.children = nil; return }
            node.detail = "loading…"
            DatabaseService.tables(of: node.connection) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let tables):
                    let tableNodes = tables.filter { !$0.isView }.map { Node(.table, $0.name, connection: node.connection, table: $0, children: $0.columns.isEmpty ? nil : self.columnNodes($0, node.connection)) }
                    let viewNodes = tables.filter(\.isView).map { Node(.table, $0.name, connection: node.connection, table: $0, children: $0.columns.isEmpty ? nil : self.columnNodes($0, node.connection)) }
                    node.children = [Node(.folder, "Tables", connection: node.connection, children: tableNodes), Node(.folder, "Views", connection: node.connection, children: viewNodes)]
                    node.detail = node.connection.kind == .sqlite ? (node.connection.location as NSString).lastPathComponent : node.connection.kind.title
                case .failure(let error):
                    node.children = nil
                    node.detail = "not connected"
                    DatabaseService.passwords[node.connection.id] = nil
                    Prompt.show("Couldn't connect to “\(node.connection.name)”", message: error.localizedDescription)
                }
                outline.reloadItem(node, reloadChildren: true)
                if node.children != nil {
                    outline.expandItem(node)
                    if let tables = node.children?.first { self.outline.expandItem(tables) }
                }
            }
        case .table:
            guard let table = node.table else { return }
            DatabaseService.columns(of: table.name, in: node.connection) { [weak self] columns in
                var filled = table
                filled.columns = columns
                node.table = filled
                node.children = self?.columnNodes(filled, node.connection)
                self?.outline.reloadItem(node, reloadChildren: true)
                self?.outline.expandItem(node)
            }
        default:
            break
        }
    }

    private func columnNodes(_ table: DatabaseTable, _ connection: DataConnection) -> [Node] {
        table.columns.map { column in
            let node = Node(.column, column.name, connection: connection, children: [])
            node.detail = column.type + (column.isKey ? "  🔑" : "")
            return node
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return roots.count }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children?[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        return node.kind != .column && (node.children == nil || !(node.children?.isEmpty ?? true))
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? Node { load(node) }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let symbol: String
        switch node.kind {
        case .connection: symbol = node.connection.kind == .sqlite ? "cylinder" : "server.rack"
        case .folder: symbol = "folder"
        case .table: symbol = node.table?.isView == true ? "eye" : "tablecells"
        case .column: symbol = "line.3.horizontal"
        }
        let cell = NSTableCellView()
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = node.kind == .connection ? Theme.accent : .secondaryLabelColor
        let text = NSMutableAttributedString(string: node.title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: node.kind == .connection ? .medium : .regular)])
        if !node.detail.isEmpty {
            text.append(NSAttributedString(string: "  " + node.detail, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        let label = NSTextField(labelWithAttributedString: text)
        label.lineBreakMode = .byTruncatingTail
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
}

extension ServerExplorerView: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = outline.item(atRow: outline.clickedRow) as? Node else {
            menu.addItem(ActionItem(title: "Add Connection…") { [weak self] in self?.addConnection() })
            return
        }
        if node.kind == .table, let table = node.table {
            menu.addItem(ActionItem(title: "Show Table Data") { [weak self] in self?.onShowData?(node.connection, table.name) })
        }
        menu.addItem(ActionItem(title: "New Query") { [weak self] in self?.onNewQuery?(node.connection) })
        menu.addItem(ActionItem(title: "Refresh") { [weak self] in
            self?.outline.selectRowIndexes([self?.outline.clickedRow ?? 0], byExtendingSelection: false)
            self?.refreshSelected()
        })
        if node.kind == .connection {
            menu.addItem(.separator())
            menu.addItem(ActionItem(title: "Remove Connection") { [weak self] in
                self?.outline.selectRowIndexes([self?.outline.clickedRow ?? 0], byExtendingSelection: false)
                self?.removeConnection()
            })
        }
    }
}

/// Add Connection: a SQLite file, or a PostgreSQL, MySQL or SQL Server database.
final class AddConnectionSheet: NSObject {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 320), styleMask: [.titled], backing: .buffered, defer: true)
    private let kind = NSPopUpButton()
    private let name = NSTextField()
    private let file = NSTextField()
    private let host = NSTextField()
    private let port = NSTextField()
    private let database = NSTextField()
    private let user = NSTextField()
    private let password = NSSecureTextField()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private var rows: (file: NSGridRow?, server: [NSGridRow]) = (nil, [])
    private let onAdd: (DataConnection) -> Void
    private static var current: AddConnectionSheet?

    init(onAdd: @escaping (DataConnection) -> Void) {
        self.onAdd = onAdd
        super.init()
        kind.addItems(withTitles: DataConnection.Kind.allCases.map(\.title))
        kind.target = self
        kind.action = #selector(kindChanged)
        for field in [name, host, port, database, user, password] { field.widthAnchor.constraint(equalToConstant: 300).isActive = true }
        file.widthAnchor.constraint(equalToConstant: 160).isActive = true
        name.placeholderString = "Shown in Server Explorer"
        file.placeholderString = "/path/to/database.db"
        host.stringValue = "localhost"
        port.placeholderString = "default"
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        let browse = NSButton(title: "Browse…", target: self, action: #selector(browse))
        let create = NSButton(title: "New…", target: self, action: #selector(createFile))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Data source:"), kind],
            [NSTextField(labelWithString: "Name:"), name],
            [NSTextField(labelWithString: "Database file:"), NSStackView(views: [file, browse, create])],
            [NSTextField(labelWithString: "Server:"), host],
            [NSTextField(labelWithString: "Port:"), port],
            [NSTextField(labelWithString: "Database:"), database],
            [NSTextField(labelWithString: "User name:"), user],
            [NSTextField(labelWithString: "Password:"), password],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        rows = (grid.row(at: 2), (3...7).map { grid.row(at: $0) })
        let title = NSTextField(labelWithString: "Add Connection")
        title.font = .systemFont(ofSize: 18)
        let test = NSButton(title: "Test Connection", target: self, action: #selector(testConnection))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "Add", target: self, action: #selector(add))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [test, NSView(), cancel, ok])
        let stack = NSStackView(views: [title, grid, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: grid.widthAnchor),
            hint.widthAnchor.constraint(equalTo: grid.widthAnchor),
        ])
        window.contentView = content
        kindChanged()
    }

    func show(in parent: NSWindow) {
        Self.current = self
        parent.beginSheet(window) { _ in Self.current = nil }
    }

    private var selectedKind: DataConnection.Kind { DataConnection.Kind.allCases[max(kind.indexOfSelectedItem, 0)] }

    @objc private func kindChanged() {
        let isFile = selectedKind == .sqlite
        rows.file?.isHidden = !isFile
        rows.server.forEach { $0.isHidden = isFile }
        hint.stringValue = isFile ? "SQLite databases are built into macOS; nothing else is needed."
            : "CodeForge uses the \(selectedKind.client ?? "") command-line client. \(selectedKind.installHint) The password isn't saved."
        // Fit the sheet to the rows that are showing.
        if let content = window.contentView {
            content.layoutSubtreeIfNeeded()
            window.setContentSize(NSSize(width: max(content.fittingSize.width, 500), height: content.fittingSize.height))
        }
    }

    @objc private func browse() {
        let panel = NSOpenPanel()
        panel.message = "Choose a SQLite database file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        file.stringValue = url.path
        if name.stringValue.isEmpty { name.stringValue = url.deletingPathExtension().lastPathComponent }
    }

    @objc private func createFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Database.db"
        panel.message = "Create an empty SQLite database."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try SQLiteDatabase(path: url.path, create: true)
            file.stringValue = url.path
            if name.stringValue.isEmpty { name.stringValue = url.deletingPathExtension().lastPathComponent }
        } catch {
            Prompt.show("Couldn't create the database", message: error.localizedDescription)
        }
    }

    private func connection() -> DataConnection? {
        let kind = selectedKind
        if kind == .sqlite {
            let path = file.stringValue.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath) else {
                Prompt.show("Choose a database file", message: "Click Browse… to pick an existing SQLite file, or New… to create one.")
                return nil
            }
            let title = name.stringValue.isEmpty ? (path as NSString).lastPathComponent : name.stringValue
            return DataConnection(name: title, kind: .sqlite, location: path)
        }
        let server = host.stringValue.trimmingCharacters(in: .whitespaces)
        guard !server.isEmpty else { Prompt.show("Enter the server", message: "For a database on this Mac, use localhost."); return nil }
        let title = name.stringValue.isEmpty ? [database.stringValue, server].filter { !$0.isEmpty }.joined(separator: " on ") : name.stringValue
        return DataConnection(name: title, kind: kind, location: server, port: port.stringValue.trimmingCharacters(in: .whitespaces),
                              database: database.stringValue.trimmingCharacters(in: .whitespaces), user: user.stringValue.trimmingCharacters(in: .whitespaces))
    }

    @objc private func testConnection() {
        guard let connection = connection() else { return }
        if !password.stringValue.isEmpty { DatabaseService.passwords[connection.id] = password.stringValue }
        DatabaseService.run("SELECT 1", on: connection) { [weak self] result in
            DatabaseService.passwords[connection.id] = nil
            switch result {
            case .success: self?.hint.stringValue = "✓ Test connection succeeded."
            case .failure(let error): self?.hint.stringValue = "✗ " + error.localizedDescription
            }
        }
    }

    @objc private func cancel() { window.sheetParent?.endSheet(window) }

    @objc private func add() {
        guard let connection = connection() else { return }
        if !password.stringValue.isEmpty { DatabaseService.passwords[connection.id] = password.stringValue }
        window.sheetParent?.endSheet(window)
        onAdd(connection)
    }
}
