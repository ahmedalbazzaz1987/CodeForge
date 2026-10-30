import AppKit
import CodeForgeKit

/// Tools ▸ Code Snippets Manager (⌃⌘B): browse, add, change and delete code snippets for each language.
final class SnippetsManagerWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    static let shared = SnippetsManagerWindow()

    private lazy var window: NSWindow = makeWindow()
    private let language = NSPopUpButton()
    private let table = NSTableView()
    private let titleField = NSTextField()
    private let shortcutField = NSTextField()
    private let summaryField = NSTextField()
    private let body = NSTextView()
    private let note = NSTextField(wrappingLabelWithString: "")
    private let removeButton = NSButton()
    private var snippets: [CodeSnippet] = []
    private var editing: CodeSnippet?
    private static let languages = ["vb", "csharp", "python", "javascript", "typescript", "swift", "html", "css", "cpp", "java", "go", "rust", "sql", "razor"]

    func show(languageId: String?) {
        _ = window
        if let languageId, let index = Self.languages.firstIndex(of: languageId) { language.selectItem(at: index) }
        reload()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.title = "Code Snippets Manager"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 420)
        for id in Self.languages { language.addItem(withTitle: Languages.language(id: id)?.name ?? id) }
        language.target = self
        language.action = #selector(reload)

        for (id, title, width) in [("shortcut", "Shortcut", 90.0), ("title", "Snippet", 170.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.style = .plain
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder

        let add = NSButton(title: "Add", target: self, action: #selector(addSnippet))
        removeButton.title = "Delete"
        removeButton.target = self
        removeButton.action = #selector(removeSnippet)
        removeButton.bezelStyle = .rounded
        let restore = NSButton(title: "Restore Built-in Snippets", target: self, action: #selector(restore))
        let reveal = NSButton(title: "Show File", target: self, action: #selector(revealFile))
        reveal.toolTip = SnippetStore.url.path
        let left = NSStackView(views: [language, tableScroll, NSStackView(views: [add, removeButton, NSView(), reveal]), restore])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 8
        tableScroll.widthAnchor.constraint(equalToConstant: 280).isActive = true
        tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        for field in [titleField, shortcutField, summaryField] { field.delegate = self }
        shortcutField.placeholderString = "Type this, then press Tab"
        summaryField.placeholderString = "Optional"
        body.isRichText = false
        body.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        body.isAutomaticQuoteSubstitutionEnabled = false
        body.isAutomaticDashSubstitutionEnabled = false
        body.isAutomaticSpellingCorrectionEnabled = false
        body.allowsUndo = true
        body.delegate = self
        body.textContainerInset = NSSize(width: 4, height: 4)
        let bodyScroll = NSScrollView()
        bodyScroll.documentView = body
        bodyScroll.hasVerticalScroller = true
        bodyScroll.borderType = .bezelBorder
        body.autoresizingMask = [.width]
        body.isVerticallyResizable = true
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Title:"), titleField],
            [NSTextField(labelWithString: "Shortcut:"), shortcutField],
            [NSTextField(labelWithString: "Description:"), summaryField],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        let codeLabel = NSTextField(labelWithString: "Code (put $0 where the cursor goes):")
        let right = NSStackView(views: [grid, codeLabel, bodyScroll, note])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 8
        let stack = NSStackView(views: [left, right])
        stack.alignment = .top
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            right.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: -16),
            left.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: -16),
            grid.widthAnchor.constraint(equalTo: right.widthAnchor),
            bodyScroll.widthAnchor.constraint(equalTo: right.widthAnchor),
            note.widthAnchor.constraint(equalTo: right.widthAnchor),
            titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
        window.contentView = content
        window.center()
        return window
    }

    private var languageId: String { Self.languages[max(language.indexOfSelectedItem, 0)] }

    @objc private func reload() {
        snippets = SnippetStore.library.snippets(forLanguage: languageId)
        table.reloadData()
        select(editing.flatMap { current in snippets.firstIndex { $0.id == current.id } } ?? (snippets.isEmpty ? nil : 0))
    }

    private func select(_ index: Int?) {
        guard let index, snippets.indices.contains(index) else {
            editing = nil
            [titleField, shortcutField, summaryField].forEach { $0.stringValue = ""; $0.isEnabled = false }
            body.string = ""
            body.isEditable = false
            note.stringValue = "No snippets for this language yet. Click Add to make one."
            removeButton.isEnabled = false
            return
        }
        table.selectRowIndexes([index], byExtendingSelection: false)
        let snippet = snippets[index]
        editing = snippet
        [titleField, shortcutField, summaryField].forEach { $0.isEnabled = true }
        titleField.stringValue = snippet.title
        shortcutField.stringValue = snippet.shortcut
        summaryField.stringValue = snippet.summary
        body.isEditable = true
        if body.string != snippet.body { body.string = snippet.body }
        removeButton.isEnabled = true
        note.stringValue = (snippet.isBuiltIn ? "A built-in snippet. Your changes are saved as your own copy." : "Your snippet.")
            + " Type “\(snippet.shortcut)” and press Tab in a \(Languages.language(id: languageId)?.name ?? languageId) file, or pick it from IntelliSense."
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0, snippets[table.selectedRow].id != editing?.id { select(table.selectedRow) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { snippets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let snippet = snippets[row]
        let isShortcut = tableColumn?.identifier.rawValue == "shortcut"
        let field = NSTextField(labelWithString: isShortcut ? snippet.shortcut : snippet.title)
        field.font = isShortcut ? .monospacedSystemFont(ofSize: 11.5, weight: .medium) : .systemFont(ofSize: 12)
        field.textColor = isShortcut || !snippet.isBuiltIn ? .labelColor : .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        // A cell view lets the text turn white on the selected row.
        let cell = NSTableCellView()
        cell.textField = field
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    /// Saves the edited fields after every change.
    private func commit() {
        guard var snippet = editing else { return }
        snippet.title = titleField.stringValue
        snippet.shortcut = shortcutField.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        snippet.summary = summaryField.stringValue
        snippet.body = body.string
        guard !snippet.shortcut.isEmpty else { return }
        SnippetStore.library.save(snippet)
        SnippetStore.save()
        editing = SnippetStore.library.all.first { $0.id == snippet.id }
        let row = table.selectedRow
        snippets = SnippetStore.library.snippets(forLanguage: languageId)
        table.reloadData()
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) { table.selectRowIndexes([index], byExtendingSelection: false) } else if row >= 0 { table.selectRowIndexes([row], byExtendingSelection: false) }
    }

    func controlTextDidChange(_ obj: Notification) { commit() }
    func textDidChange(_ notification: Notification) { commit() }

    @objc private func addSnippet() {
        var shortcut = "mysnippet"
        var number = 1
        while SnippetStore.library.snippet(shortcut: shortcut, languageId: languageId) != nil { number += 1; shortcut = "mysnippet\(number)" }
        let snippet = CodeSnippet(title: "My Snippet", shortcut: shortcut, languageId: languageId, body: "$0")
        SnippetStore.library.save(snippet)
        SnippetStore.save()
        editing = snippet
        reload()
        window.makeFirstResponder(titleField)
    }

    @objc private func removeSnippet() {
        guard let snippet = editing else { return }
        SnippetStore.library.delete(id: snippet.id)
        SnippetStore.save()
        editing = nil
        reload()
    }

    @objc private func restore() {
        guard Prompt.confirm("Restore the built-in snippets?", message: "Built-in snippets you changed or deleted come back as they were. Your own snippets are kept.", button: "Restore") else { return }
        SnippetStore.library.restoreBuiltIns()
        SnippetStore.save()
        editing = nil
        reload()
    }

    @objc private func revealFile() {
        SnippetStore.save()
        NSWorkspace.shared.activateFileViewerSelecting([SnippetStore.url])
    }
}
