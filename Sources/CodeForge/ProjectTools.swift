import AppKit
import CodeForgeKit

/// Project ▸ Add New Item…: choose a file template and a name.
final class AddItemSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430), styleMask: [.titled], backing: .buffered, defer: true)
    private let table = NSTableView()
    private let nameField = NSTextField()
    private let folderLabel = NSTextField(labelWithString: "")
    private let onCreate: (ItemTemplate, String) -> Void
    private static var current: AddItemSheet?

    /// `preferredExtension` picks the first template of the same kind (a VB.NET project starts on "Class (.vb)").
    init(folder: URL, preferredExtension: String? = nil, onCreate: @escaping (ItemTemplate, String) -> Void) {
        self.onCreate = onCreate
        super.init()
        let title = NSTextField(labelWithString: "Add New Item")
        title.font = .systemFont(ofSize: 18)
        folderLabel.stringValue = "In: " + folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.font = .systemFont(ofSize: 11)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        for (id, name, width) in [("name", "Template", 300.0), ("group", "Type", 120.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = name
            column.width = width
            table.addTableColumn(column)
        }
        table.rowHeight = 24
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let nameRow = NSStackView(views: [NSTextField(labelWithString: "Name:"), nameField])
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let add = NSButton(title: "Add", target: self, action: #selector(add))
        add.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, add])
        let stack = NSStackView(views: [title, folderLabel, scroll, nameRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            nameRow.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            folderLabel.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor),
        ])
        window.contentView = content
        let preferred = ItemTemplates.all.firstIndex { $0.fileExtension == preferredExtension?.lowercased() } ?? 0
        table.selectRowIndexes([preferred], byExtendingSelection: false)
        table.scrollRowToVisible(preferred)
        updateName()
    }

    func show(in parent: NSWindow) {
        Self.current = self
        parent.beginSheet(window) { _ in Self.current = nil }
        window.makeFirstResponder(nameField)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { ItemTemplates.all.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let template = ItemTemplates.all[row]
        if tableColumn?.identifier.rawValue == "group" {
            let label = NSTextField(labelWithString: template.group)
            label.textColor = .secondaryLabelColor
            return label
        }
        let label = NSTextField(labelWithString: template.name)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let ext = NSTextField(labelWithString: "." + template.fileExtension)
        ext.textColor = Theme.accent
        ext.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        return NSStackView(views: [label, ext])
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateName() }

    /// Suggests "Class1.vb" etc. while the name hasn't been edited.
    private var suggested = ""
    private func updateName() {
        guard ItemTemplates.all.indices.contains(table.selectedRow) else { return }
        let template = ItemTemplates.all[table.selectedRow]
        if nameField.stringValue.isEmpty || nameField.stringValue == suggested {
            suggested = template.defaultName + "." + template.fileExtension
            nameField.stringValue = suggested
        }
    }

    @objc private func cancel() { window.sheetParent?.endSheet(window) }

    @objc private func add() {
        guard ItemTemplates.all.indices.contains(table.selectedRow) else { return NSSound.beep() }
        let template = ItemTemplates.all[table.selectedRow]
        let name = ItemTemplates.fileName(nameField.stringValue, for: template)
        guard !name.contains("/") else { return NSSound.beep() }
        window.sheetParent?.endSheet(window)
        onCreate(template, name)
    }
}

/// Tools ▸ Options…: appearance, editor and environment settings.
final class OptionsWindow: NSObject {
    static let shared = OptionsWindow()
    var onChange: (() -> Void)?
    private lazy var window: NSWindow = makeWindow()
    private let appearance = NSPopUpButton()
    private let fontSize = NSStepper()
    private let fontLabel = NSTextField(labelWithString: "")
    private let codeLens = NSButton(checkboxWithTitle: "Show CodeLens (references and last change)", target: nil, action: nil)
    private let explorerSide = NSPopUpButton()
    private let autoUpdate = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
    private let restoreSession = NSButton(checkboxWithTitle: "Reopen the last folder and files at launch", target: nil, action: nil)

    private let defaults = UserDefaults.standard

    func show() {
        load()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 330), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Options"
        window.isReleasedWhenClosed = false
        appearance.addItems(withTitles: ["Use System Setting", "Light", "Dark"])
        explorerSide.addItems(withTitles: ["Right (like Visual Studio)", "Left"])
        fontSize.minValue = 9
        fontSize.maxValue = 32
        for control in [appearance, explorerSide] as [NSControl] + [fontSize, codeLens, autoUpdate, restoreSession] {
            control.target = self
            control.action = #selector(changed)
        }
        func section(_ title: String) -> NSTextField {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            return label
        }
        let grid = NSGridView(views: [
            [section("Environment"), NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Color theme:"), appearance],
            [NSTextField(labelWithString: "Solution Explorer:"), explorerSide],
            [NSGridCell.emptyContentView, autoUpdate],
            [NSGridCell.emptyContentView, restoreSession],
            [section("Text Editor"), NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Font size:"), NSStackView(views: [fontLabel, fontSize])],
            [NSGridCell.emptyContentView, codeLens],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.row(at: 5).topPadding = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])
        window.contentView = content
        return window
    }

    private func load() {
        appearance.selectItem(at: ["system", "light", "dark"].firstIndex(of: defaults.string(forKey: "appearance") ?? "system") ?? 0)
        explorerSide.selectItem(at: (defaults.object(forKey: "explorerOnRight") as? Bool ?? true) ? 0 : 1)
        let size = defaults.double(forKey: "fontSize") == 0 ? 13 : defaults.double(forKey: "fontSize")
        fontSize.doubleValue = size
        fontLabel.stringValue = "\(Int(size)) pt"
        codeLens.state = (defaults.object(forKey: "showCodeLens") as? Bool ?? true) ? .on : .off
        autoUpdate.state = (defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true) ? .on : .off
        restoreSession.state = (defaults.object(forKey: "restoreSession") as? Bool ?? true) ? .on : .off
    }

    @objc private func changed() {
        defaults.set(["system", "light", "dark"][max(appearance.indexOfSelectedItem, 0)], forKey: "appearance")
        defaults.set(explorerSide.indexOfSelectedItem == 0, forKey: "explorerOnRight")
        defaults.set(fontSize.doubleValue, forKey: "fontSize")
        fontLabel.stringValue = "\(Int(fontSize.doubleValue)) pt"
        defaults.set(codeLens.state == .on, forKey: "showCodeLens")
        defaults.set(autoUpdate.state == .on, forKey: "autoCheckUpdates")
        defaults.set(restoreSession.state == .on, forKey: "restoreSession")
        Self.applyAppearance()
        onChange?()
    }

    static func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
