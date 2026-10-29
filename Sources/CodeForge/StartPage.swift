import AppKit
import CodeForgeKit

/// Shown when no file is open: recent projects on the left, "Get started" actions on the right.
final class StartPage: NSView {
    var onOpenRecent: ((URL) -> Void)?
    var onNewProject: (() -> Void)?
    var onOpen: (() -> Void)?
    var onClone: (() -> Void)?
    var onNewFile: (() -> Void)?
    private let recentList = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: "CodeForge")
        title.font = .systemFont(ofSize: 30, weight: .light)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let subtitle = NSTextField(labelWithString: version.map { "Version \($0)" } ?? "Development build")
        subtitle.textColor = .secondaryLabelColor

        let recentTitle = Self.heading("Open recent")
        recentList.orientation = .vertical
        recentList.alignment = .leading
        recentList.spacing = 2
        let recentScroll = NSScrollView()
        recentScroll.drawsBackground = false
        recentScroll.hasVerticalScroller = true
        recentScroll.autohidesScrollers = true
        let flipped = FlippedView()
        flipped.addSubview(recentList)
        recentList.translatesAutoresizingMaskIntoConstraints = false
        recentScroll.documentView = flipped
        flipped.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recentList.topAnchor.constraint(equalTo: flipped.topAnchor),
            recentList.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            recentList.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            recentList.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
            flipped.widthAnchor.constraint(equalTo: recentScroll.contentView.widthAnchor),
            flipped.topAnchor.constraint(equalTo: recentScroll.contentView.topAnchor),
        ])
        let left = NSStackView(views: [recentTitle, recentScroll])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 12

        let actions = NSStackView(views: [
            Self.heading("Get started"),
            ActionTile(symbol: "plus.rectangle.on.folder", title: "Create a new project",
                       detail: "Choose a template with starter files to get going") { [weak self] in self?.onNewProject?() },
            ActionTile(symbol: "folder", title: "Open a folder or file",
                       detail: "Open a project folder or any code file") { [weak self] in self?.onOpen?() },
            ActionTile(symbol: "arrow.down.circle", title: "Clone a repository",
                       detail: "Get code from GitHub or another Git server") { [weak self] in self?.onClone?() },
            ActionTile(symbol: "doc.badge.plus", title: "New file",
                       detail: "Start typing in an empty editor tab") { [weak self] in self?.onNewFile?() },
        ])
        actions.orientation = .vertical
        actions.alignment = .leading
        actions.spacing = 8
        actions.setCustomSpacing(12, after: actions.arrangedSubviews[0])

        let columns = NSStackView(views: [left, actions])
        columns.alignment = .top
        columns.distribution = .fill
        columns.spacing = 48
        let page = NSStackView(views: [title, subtitle, columns])
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 4
        page.setCustomSpacing(32, after: subtitle)
        page.translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            page.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            page.centerXAnchor.constraint(equalTo: centerXAnchor),
            left.widthAnchor.constraint(equalToConstant: 340),
            actions.widthAnchor.constraint(equalToConstant: 340),
            recentScroll.widthAnchor.constraint(equalTo: left.widthAnchor),
            recentScroll.heightAnchor.constraint(equalTo: actions.heightAnchor, constant: -30),
        ])
        // The page may be cut off in a short window rather than forcing the editor area taller.
        let bottom = page.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24)
        bottom.priority = .defaultLow
        bottom.isActive = true
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
    }

    func reload() {
        recentList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let recents = NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if recents.isEmpty {
            let none = NSTextField(wrappingLabelWithString: "Projects and files you open appear here.")
            none.textColor = .secondaryLabelColor
            recentList.addArrangedSubview(none)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for url in recents.prefix(14) {
            let path = url.deletingLastPathComponent().path.replacingOccurrences(of: home, with: "~")
            let row = RecentRow(url: url, path: path) { [weak self] in self?.onOpenRecent?(url) }
            recentList.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: recentList.widthAnchor).isActive = true
        }
    }

    private static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .regular)
        return label
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A clickable row or tile that highlights on hover.
private class HoverControl: NSView {
    private let action: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    var drawsTile: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        if drawsTile {
            Theme.chrome.setFill()
            path.fill()
        }
        if hovering {
            Theme.accent.withAlphaComponent(0.15).setFill()
            path.fill()
            Theme.accent.setStroke()
            path.stroke()
        }
    }
}

private final class ActionTile: HoverControl {
    init(symbol: String, title: String, detail: String, action: @escaping () -> Void) {
        super.init(action: action)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 22, weight: .light)
        icon.contentTintColor = Theme.accent
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let info = NSTextField(wrappingLabelWithString: detail)
        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        let text = NSStackView(views: [name, info])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text])
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(equalToConstant: 340),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    override var drawsTile: Bool { true }
}

private final class RecentRow: HoverControl {
    init(url: URL, path: String, action: @escaping () -> Void) {
        super.init(action: action)
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
        icon.image?.size = NSSize(width: 24, height: 24)
        let name = NSTextField(labelWithString: url.lastPathComponent)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        let location = NSTextField(labelWithString: path)
        location.font = .systemFont(ofSize: 11)
        location.textColor = .secondaryLabelColor
        location.lineBreakMode = .byTruncatingMiddle
        let text = NSStackView(views: [name, location])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        let row = NSStackView(views: [icon, text])
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        toolTip = url.path
        setAccessibilityRole(.button)
        setAccessibilityLabel(url.lastPathComponent)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// File ▸ New Project: pick a template, a name and a location.
final class NewProjectSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 470), styleMask: [.titled], backing: .buffered, defer: true)
    private let table = NSTableView()
    private let nameField = NSTextField()
    private let locationField = NSTextField()
    private let onCreate: (ProjectTemplate, String, URL) -> Void
    private static var current: NewProjectSheet?

    init(onCreate: @escaping (ProjectTemplate, String, URL) -> Void) {
        self.onCreate = onCreate
        super.init()
        let title = NSTextField(labelWithString: "Create a new project")
        title.font = .systemFont(ofSize: 18, weight: .regular)

        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("template")))
        table.headerView = nil
        table.rowHeight = 50
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        nameField.placeholderString = "MyProject"
        nameField.stringValue = "MyProject"
        let defaultLocation = ["Developer", "Projects", "Documents"]
            .map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }!
        locationField.stringValue = UserDefaults.standard.string(forKey: "newProjectLocation") ?? defaultLocation.path
        let browse = NSButton(title: "Browse…", target: self, action: #selector(browse))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Project name"), nameField, NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Location"), locationField, browse],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let create = NSButton(title: "Create", target: self, action: #selector(create))
        create.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, create])

        let stack = NSStackView(views: [title, scroll, grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
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
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            nameField.widthAnchor.constraint(equalToConstant: 380),
        ])
        window.contentView = content
        table.selectRowIndexes([0], byExtendingSelection: false)
    }

    func show(in parent: NSWindow) {
        Self.current = self
        parent.beginSheet(window) { _ in Self.current = nil }
        window.makeFirstResponder(nameField)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { ProjectTemplates.all.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let template = ProjectTemplates.all[row]
        let icon = NSImageView(image: NSImage(systemSymbolName: template.symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 20, weight: .light)
        icon.contentTintColor = Theme.accent
        let name = NSTextField(labelWithString: template.name)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let summary = NSTextField(labelWithString: template.summary)
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        let tag = NSTextField(labelWithString: template.tags)
        tag.font = .systemFont(ofSize: 10, weight: .medium)
        tag.textColor = Theme.accent
        let text = NSStackView(views: [name, summary])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text, NSView(), tag])
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 12)
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return row
    }

    @objc private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.locationField.stringValue = url.path }
        }
    }

    @objc private func cancel() {
        window.sheetParent?.endSheet(window)
    }

    @objc private func create() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let location = URL(fileURLWithPath: (locationField.stringValue as NSString).expandingTildeInPath)
        guard !name.isEmpty, !name.contains("/"), table.selectedRow >= 0 else { return NSSound.beep() }
        UserDefaults.standard.set(location.path, forKey: "newProjectLocation")
        let template = ProjectTemplates.all[table.selectedRow]
        window.sheetParent?.endSheet(window)
        onCreate(template, name, location)
    }
}
