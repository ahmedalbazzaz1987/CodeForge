import AppKit
import CodeForgeKit
import WebKit

/// Visual Studio-style Toolbox: controls and snippets for the current file. Double-click or drag into the editor.
final class ToolboxView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    var onInsert: ((ToolboxItem) -> Void)?
    private var groups: [ToolboxGroup] = []
    private var shown: [ToolboxGroup] = []
    private let outline = NSOutlineView()
    private let search = NSSearchField()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var languageName = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: "TOOLBOX")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        search.placeholderString = "Search Toolbox"
        search.controlSize = .small
        search.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(insertClicked)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.font = .systemFont(ofSize: 12)

        for view in [title, search, scroll, empty] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            search.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        show(language: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.sidebar.setFill()
        bounds.fill()
    }

    func show(language: Language?) {
        guard language?.name ?? "" != languageName || groups.isEmpty else { return }
        languageName = language?.name ?? ""
        groups = language.map { ToolboxCatalog.groups(forLanguage: $0.id) } ?? []
        empty.stringValue = language == nil
            ? "Open a file to see its controls and snippets."
            : "There are no usable controls in this group for \(language!.name) files. Open an HTML, Razor, C#, VB.NET, Swift, Python or JavaScript file."
        filter()
    }

    private func filter() {
        let query = search.stringValue.lowercased()
        shown = groups.compactMap { group in
            let items = query.isEmpty ? group.items : group.items.filter { $0.name.lowercased().contains(query) }
            return items.isEmpty ? nil : ToolboxGroup(name: group.name, items: items)
        }
        empty.isHidden = !groups.isEmpty
        outline.reloadData()
        for index in shown.indices { outline.expandItem(GroupBox(index)) }
    }

    func controlTextDidChange(_ notification: Notification) { filter() }

    /// Outline items: groups are boxed indexes, items are (group, item) pairs.
    private final class GroupBox: NSObject {
        let index: Int
        init(_ index: Int) { self.index = index }
        override func isEqual(_ object: Any?) -> Bool { (object as? GroupBox)?.index == index }
        override var hash: Int { index }
    }

    private final class ItemBox: NSObject {
        let item: ToolboxItem
        init(_ item: ToolboxItem) { self.item = item }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let group = item as? GroupBox else { return shown.count }
        return shown[group.index].items.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let group = item as? GroupBox else { return GroupBox(index) }
        return ItemBox(shown[group.index].items[index])
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is GroupBox }
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { item is GroupBox }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { item is ItemBox }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let group = item as? GroupBox {
            let label = NSTextField(labelWithString: shown[group.index].name)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        }
        guard let box = item as? ItemBox else { return nil }
        let icon = NSImageView(image: NSImage(systemSymbolName: box.item.symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "square", accessibilityDescription: nil)!)
        icon.contentTintColor = Theme.accent
        let label = NSTextField(labelWithString: box.item.name)
        label.font = .systemFont(ofSize: 12)
        let row = NSStackView(views: [icon, label])
        row.spacing = 6
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        row.toolTip = box.item.snippet.replacingOccurrences(of: "$0", with: "")
        return row
    }

    /// Dragging an item into the editor drops its text there.
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? ItemBox).map { $0.item.expanded(indent: "").text as NSString }
    }

    @objc private func insertClicked() {
        guard let box = outline.item(atRow: outline.clickedRow) as? ItemBox else { return }
        onInsert?(box.item)
    }
}

/// The Properties window: attributes of the HTML element at the cursor (editable), or details of the file.
final class PropertiesView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    /// (index, new name, new value); index == rows.count adds an attribute; a nil name removes it.
    var onChangeAttribute: ((Int, String?, String?) -> Void)?
    private var rows: [(name: String, value: String)] = []
    private var editable = false
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let add = FileTreeView.iconButton("plus", "Add Attribute", #selector(addAttribute), nil)
    private let remove = FileTreeView.iconButton("minus", "Remove Attribute", #selector(removeAttribute), nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        add.target = self
        remove.target = self
        let heading = NSTextField(labelWithString: "PROPERTIES")
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        for (id, name, width) in [("name", "Property", 110.0), ("value", "Value", 160.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = name
            column.width = width
            table.addTableColumn(column)
        }
        table.style = .plain
        table.rowHeight = 20
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = [.solidVerticalGridLineMask]
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let header = NSStackView(views: [heading, NSView(), add, remove])
        header.spacing = 8
        let titles = NSStackView(views: [title, subtitle])
        titles.spacing = 6
        for view in [header, titles, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titles.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            titles.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: titles.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        showNothing()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.sidebar.setFill()
        bounds.fill()
        Theme.separator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    func showNothing() {
        show(title: "", subtitle: "", rows: [], editable: false)
    }

    func show(tag: HTMLTag) {
        show(title: "<\(tag.name)>", subtitle: "HTML element", rows: tag.attributes.map { ($0.name, $0.value ?? "") }, editable: true)
    }

    func show(file document: EditorDocument) {
        var rows: [(String, String)] = [("Name", document.displayName), ("Language", document.language.name)]
        if let url = document.url {
            rows.append(("Full Path", url.path))
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            if let size = values?.fileSize { rows.append(("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))) }
            if let date = values?.contentModificationDate {
                rows.append(("Modified", DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)))
            }
        }
        rows.append(("Lines", "\(document.ruler.lineCount)"))
        rows.append(("Encoding", "UTF-8"))
        rows.append(("Indentation", document.language.indentWithTabs ? "Tabs" : "4 spaces"))
        show(title: document.displayName, subtitle: "File Properties", rows: rows, editable: false)
    }

    private func show(title: String, subtitle: String, rows: [(name: String, value: String)], editable: Bool) {
        // Don't rebuild while the user is typing a value.
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor, editor.delegate as? NSTextField != nil,
           (editor.delegate as? NSView)?.isDescendant(of: table) == true { return }
        self.title.stringValue = title
        self.subtitle.stringValue = subtitle
        self.rows = rows
        self.editable = editable
        add.isHidden = !editable
        remove.isHidden = !editable
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isValue = tableColumn?.identifier.rawValue == "value"
        let field = NSTextField(string: isValue ? rows[row].value : rows[row].name)
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        field.isEditable = editable
        field.isSelectable = true
        field.toolTip = field.stringValue
        field.tag = row * 2 + (isValue ? 1 : 0)
        field.delegate = self
        return field
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard editable, let field = notification.object as? NSTextField else { return }
        let row = field.tag / 2, isValue = field.tag % 2 == 1
        guard rows.indices.contains(row) else { return }
        let name = isValue ? rows[row].name : field.stringValue.trimmingCharacters(in: .whitespaces)
        let value = isValue ? field.stringValue : rows[row].value
        guard name != rows[row].name || value != rows[row].value else { return }
        onChangeAttribute?(row, name.isEmpty ? nil : name, value)
    }

    @objc private func addAttribute() {
        guard editable, let name = Prompt.ask("Add Attribute", message: "Name of the attribute, for example class, id or style.", confirm: "Add")?
            .trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
        onChangeAttribute?(rows.count, name, "")
    }

    @objc private func removeAttribute() {
        guard editable, rows.indices.contains(table.selectedRow) else { return NSSound.beep() }
        onChangeAttribute?(table.selectedRow, nil, nil)
    }
}

/// Design / Split / Source views for HTML pages, like Visual Studio's web designer.
final class DesignHost: NSView, WKScriptMessageHandler, WKNavigationDelegate {
    enum Mode: Int { case design, split, source }

    /// The element clicked in the design surface: tag name and its index among elements with that tag.
    var onSelectElement: ((String, Int) -> Void)?
    private(set) var mode: Mode = .split
    private let document: EditorDocument
    private let webView: WKWebView
    private let split = NSSplitView()
    private let bar = NSStackView()
    private var buttons: [NSButton] = []
    private var pendingReload: DispatchWorkItem?
    private var scrollY: Double = 0
    /// The Split divider is placed once the view has a real size.
    private var needsSplitPosition = false

    init(document: EditorDocument) {
        self.document = document
        let configuration = WKWebViewConfiguration()
        let script = """
            document.addEventListener('click', function (event) {
              event.preventDefault(); event.stopPropagation();
              if (event.detail === 0) { return; }   // keyboard-made clicks (Return, Space) don't select
              var element = event.target, tag = element.tagName.toLowerCase();
              if (tag === 'html' || tag === 'head') { return; }   // stray clicks on the page root keep the current selection
              var index = Array.prototype.indexOf.call(document.getElementsByTagName(tag), element);
              document.querySelectorAll('[data-codeforge-selected]').forEach(function (e) { e.removeAttribute('data-codeforge-selected'); e.style.outline = ''; });
              element.setAttribute('data-codeforge-selected', '1');
              element.style.outline = '2px solid #007ACC';
              window.webkit.messageHandlers.codeforge.postMessage({ tag: tag, index: index });
            }, true);
            """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        configuration.userContentController.add(WeakMessageHandler(self), name: "codeforge")
        webView.navigationDelegate = self

        split.isVertical = false
        split.dividerStyle = .thin
        for (index, title) in ["Design", "Split", "Source"].enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(modeClicked(_:)))
            button.tag = index
            button.isBordered = false
            button.font = .systemFont(ofSize: 11)
            buttons.append(button)
        }
        bar.setViews(buttons + [NSView()], in: .leading)
        bar.spacing = 14
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        for view in [split, bar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: topAnchor),
            split.leadingAnchor.constraint(equalTo: leadingAnchor),
            split.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: split.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 24),
        ])
        setMode((UserDefaults.standard.object(forKey: "designMode") as? Int).flatMap(Mode.init) ?? .split)
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
    }

    override func layout() {
        super.layout()
        guard needsSplitPosition, mode == .split, split.bounds.height > 100 else { return }
        needsSplitPosition = false
        split.setPosition(split.bounds.height * 0.55, ofDividerAt: 0)
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "designMode")
        split.arrangedSubviews.forEach { split.removeArrangedSubview($0); $0.removeFromSuperview() }
        switch mode {
        case .design: split.addArrangedSubview(webView)
        case .split:
            split.addArrangedSubview(webView)
            split.addArrangedSubview(document.scrollView)
        case .source: split.addArrangedSubview(document.scrollView)
        }
        if mode == .split {
            needsSplitPosition = true
            needsLayout = true
        }
        for button in buttons {
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: button.tag == mode.rawValue ? .semibold : .regular),
                .foregroundColor: button.tag == mode.rawValue ? Theme.accent : NSColor.secondaryLabelColor,
            ])
        }
        if mode != .source { reload() }
    }

    @objc private func modeClicked(_ sender: NSButton) {
        setMode(Mode(rawValue: sender.tag) ?? .split)
        if mode == .source { window?.makeFirstResponder(document.textView) }
    }

    /// Re-renders the page shortly after the source changes.
    func textChanged() {
        guard mode != .source else { return }
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func reload() {
        let base = document.url?.deletingLastPathComponent()
        webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
            guard let self else { return }
            scrollY = value as? Double ?? scrollY
            webView.loadHTMLString(document.textView.string, baseURL: base)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let tag = body["tag"] as? String, let index = body["index"] as? Int else { return }
        onSelectElement?(tag, index)
    }
}

/// WKUserContentController keeps its handlers alive; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
