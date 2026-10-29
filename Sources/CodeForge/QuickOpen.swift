import AppKit
import CodeForgeKit

/// ⌘P: type part of a file name to open it.
final class QuickOpen: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let root: URL
    private let onPick: (URL) -> Void
    private let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380), styleMask: [.titled], backing: .buffered, defer: true)
    private let field = NSSearchField()
    private let table = NSTableView()
    private var files: [String] = []
    private var results: [String] = []
    private static let skipped: Set<String> = [".git", ".build", ".swiftpm", "node_modules", "DerivedData", "Pods", "__pycache__", ".venv", "venv", "target", "dist", "build"]
    private static var current: QuickOpen?   // keeps the sheet alive while it is shown

    init(root: URL, onPick: @escaping (URL) -> Void) {
        self.root = root
        self.onPick = onPick
        super.init()
        field.placeholderString = "Search files by name"
        field.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 22
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(pick)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let content = NSView()
        for view in [field, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        sheet.contentView = content
    }

    func show(in window: NSWindow) {
        files = Self.listFiles(in: root)
        filter()
        Self.current = self
        window.beginSheet(sheet) { _ in Self.current = nil }
        sheet.makeFirstResponder(field)
    }

    static func listFiles(in root: URL, limit: Int = 50_000) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]) else { return [] }
        let prefix = root.path.count + 1
        var files: [String] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skipped.contains(url.lastPathComponent) { enumerator.skipDescendants() }
            } else if url.lastPathComponent != ".DS_Store" {
                files.append(String(url.path.dropFirst(prefix)))
                if files.count >= limit { break }
            }
        }
        return files
    }

    private func filter() {
        let query = field.stringValue.replacingOccurrences(of: " ", with: "")
        if query.isEmpty {
            results = Array(files.sorted { $0.count < $1.count }.prefix(200))
        } else {
            results = files.compactMap { path in FuzzyMatch.score(query, path).map { (path, $0) } }
                .sorted { $0.1 > $1.1 }
                .prefix(200)
                .map(\.0)
        }
        table.reloadData()
        if !results.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    @objc private func pick() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        let picked = results.indices.contains(row) ? root.appendingPathComponent(results[row]) : nil
        close()
        if let picked { onPick(picked) }
    }

    private func close() {
        sheet.sheetParent?.endSheet(sheet)
    }

    func controlTextDidChange(_ notification: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            let delta = selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = min(max(table.selectedRow + delta, 0), results.count - 1)
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        case #selector(NSResponder.insertNewline(_:)): pick()
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("row"), owner: self) as? NSTextField
            ?? NSTextField(labelWithString: "")
        label.identifier = NSUserInterfaceItemIdentifier("row")
        label.lineBreakMode = .byTruncatingMiddle
        let path = results[row] as NSString
        let text = NSMutableAttributedString(string: path.lastPathComponent, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let folder = path.deletingLastPathComponent
        if !folder.isEmpty {
            text.append(NSAttributedString(string: "  " + folder, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        label.attributedStringValue = text
        return label
    }
}
