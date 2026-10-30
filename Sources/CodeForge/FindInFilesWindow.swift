import AppKit
import CodeForgeKit

/// Edit ▸ Find and Replace ▸ Find in Files (⇧⌘F) and Replace in Files (⇧⌘H), like Visual Studio's Find and Replace window.
final class FindInFilesWindow: NSObject, NSWindowDelegate {
    enum Scope: Int { case project, currentFolder, openDocuments }

    static let shared = FindInFilesWindow()

    /// Where to search: the project folder, the current file's folder and the open documents (url, text).
    var context: () -> (project: URL?, currentFolder: URL?, open: [(URL, String)]) = { (nil, nil, []) }
    var onResults: ((String, [SearchMatch]) -> Void)?
    /// Replaces in open documents through the editor (so it can be undone); returns the URLs it handled.
    var onReplaceInOpenDocuments: ((NSRegularExpression, String, Bool, Set<URL>) -> (handled: Set<URL>, count: Int))?
    var onStatus: ((String) -> Void)?

    private lazy var panel: NSPanel = makePanel()
    private let mode = NSSegmentedControl(labels: ["Find in Files", "Replace in Files"], trackingMode: .selectOne, target: nil, action: nil)
    private let findField = NSComboBox()
    private let replaceField = NSComboBox()
    private let replaceLabel = NSTextField(labelWithString: "Replace with:")
    private let scope = NSPopUpButton()
    private let fileTypes = NSComboBox()
    private let matchCase = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let wholeWord = NSButton(checkboxWithTitle: "Match whole word", target: nil, action: nil)
    private let regex = NSButton(checkboxWithTitle: "Use regular expressions", target: nil, action: nil)
    private let findButton = NSButton(title: "Find All", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace All", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private var replaceRow: NSGridRow?
    private let defaults = UserDefaults.standard

    func show(replacing: Bool, initialText: String?) {
        _ = panel
        mode.selectedSegment = replacing ? 1 : 0
        modeChanged()
        if let initialText, !initialText.isEmpty, !initialText.contains("\n") { findField.stringValue = initialText }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(findField)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 290), styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: true)
        panel.title = "Find and Replace"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        mode.target = self
        mode.action = #selector(modeChanged)
        for field in [findField, replaceField, fileTypes] {
            field.completes = false
            field.numberOfVisibleItems = 10
            field.widthAnchor.constraint(equalToConstant: 340).isActive = true
        }
        findField.addItems(withObjectValues: defaults.stringArray(forKey: "findHistory") ?? [])
        replaceField.addItems(withObjectValues: defaults.stringArray(forKey: "replaceHistory") ?? [])
        fileTypes.addItems(withObjectValues: ["*.*", "*.vb", "*.cs", "*.cs; *.vb", "*.cshtml; *.razor", "*.html; *.css; *.js", "*.py", "*.swift", "*.ts; *.tsx", "*.json; *.xml"])
        fileTypes.stringValue = defaults.string(forKey: "findFileTypes") ?? "*.*"
        fileTypes.placeholderString = "*.*"
        findField.placeholderString = "Text to find"
        scope.addItems(withTitles: ["Entire Solution (project folder)", "Current Folder", "All Open Documents"])
        scope.selectItem(at: defaults.integer(forKey: "findScope"))
        matchCase.state = defaults.bool(forKey: "findMatchCase") ? .on : .off
        wholeWord.state = defaults.bool(forKey: "findWholeWord") ? .on : .off
        regex.state = defaults.bool(forKey: "findRegex") ? .on : .off
        findButton.target = self
        findButton.action = #selector(findAll)
        findButton.keyEquivalent = "\r"
        replaceButton.target = self
        replaceButton.action = #selector(replaceAll)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Find what:"), findField],
            [replaceLabel, replaceField],
            [NSTextField(labelWithString: "Look in:"), scope],
            [NSTextField(labelWithString: "File types:"), fileTypes],
            [NSGridCell.emptyContentView, NSStackView(views: [matchCase, wholeWord, regex])],
        ])
        (grid.cell(atColumnIndex: 1, rowIndex: 4).contentView as? NSStackView)?.orientation = .vertical
        (grid.cell(atColumnIndex: 1, rowIndex: 4).contentView as? NSStackView)?.alignment = .leading
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 9
        replaceRow = grid.row(at: 1)
        let buttons = NSStackView(views: [progress, NSView(), replaceButton, findButton])
        let stack = NSStackView(views: [mode, grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: grid.widthAnchor),
        ])
        panel.contentView = content
        panel.center()
        return panel
    }

    @objc private func modeChanged() {
        let replacing = mode.selectedSegment == 1
        replaceRow?.isHidden = !replacing
        replaceButton.isHidden = !replacing
        panel.title = replacing ? "Replace in Files" : "Find in Files"
    }

    private var options: SearchOptions {
        SearchOptions(matchCase: matchCase.state == .on, wholeWord: wholeWord.state == .on, regularExpression: regex.state == .on,
                      fileTypes: fileTypes.stringValue.trimmingCharacters(in: .whitespaces) == "*.*" ? "" : fileTypes.stringValue)
    }

    private func remember() {
        func push(_ value: String, _ key: String, _ box: NSComboBox) {
            guard !value.isEmpty else { return }
            var list = defaults.stringArray(forKey: key) ?? []
            list.removeAll { $0 == value }
            list.insert(value, at: 0)
            list = Array(list.prefix(20))
            defaults.set(list, forKey: key)
            box.removeAllItems()
            box.addItems(withObjectValues: list)
            box.stringValue = value
        }
        push(findField.stringValue, "findHistory", findField)
        if mode.selectedSegment == 1 { push(replaceField.stringValue, "replaceHistory", replaceField) }
        defaults.set(fileTypes.stringValue, forKey: "findFileTypes")
        defaults.set(scope.indexOfSelectedItem, forKey: "findScope")
        defaults.set(matchCase.state == .on, forKey: "findMatchCase")
        defaults.set(wholeWord.state == .on, forKey: "findWholeWord")
        defaults.set(regex.state == .on, forKey: "findRegex")
    }

    /// Files to look at with their text: open documents use the editor's (maybe unsaved) text.
    private func sources() -> [(URL, String?)]? {
        let context = context()
        let open = Dictionary(context.open.map { ($0.0.standardizedFileURL, $0.1) }, uniquingKeysWith: { first, _ in first })
        switch Scope(rawValue: scope.indexOfSelectedItem) ?? .project {
        case .openDocuments:
            return context.open.map { ($0.0, $0.1) }
        case .currentFolder:
            guard let folder = context.currentFolder ?? context.project else { return nil }
            return FileSearch.files(in: folder, fileTypes: options.fileTypes).map { ($0, open[$0.standardizedFileURL]) }
        case .project:
            guard let folder = context.project ?? context.currentFolder else { return nil }
            return FileSearch.files(in: folder, fileTypes: options.fileTypes).map { ($0, open[$0.standardizedFileURL]) }
        }
    }

    @objc private func findAll() {
        let query = findField.stringValue
        guard let expression = FileSearch.expression(for: query, options: options) else {
            return NSSound.beep()   // empty, or an invalid regular expression
        }
        remember()
        guard let sources = sources() else {
            return Prompt.show("Open a folder first", message: "Find in Files searches the open project folder. Choose All Open Documents to search only the files you have open.")
        }
        progress.startAnimation(nil)
        findButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var matches: [SearchMatch] = []
            var files = Set<URL>()
            for (url, openText) in sources {
                guard let text = openText ?? FileSearch.text(of: url) else { continue }
                let found = FileSearch.matches(in: text, url: url, expression: expression)
                if !found.isEmpty { files.insert(url) }
                matches += found
                if matches.count >= 5000 { break }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.progress.stopAnimation(nil)
                self.findButton.isEnabled = true
                let summary = matches.isEmpty ? "No matches for “\(query)” in \(sources.count) file\(sources.count == 1 ? "" : "s")."
                    : "\(matches.count) match\(matches.count == 1 ? "" : "es") for “\(query)” in \(files.count) file\(files.count == 1 ? "" : "s")"
                        + (matches.count >= 5000 ? " (stopped at 5,000)" : "")
                self.onResults?(summary, matches)
                if matches.isEmpty { NSSound.beep() }
            }
        }
    }

    @objc private func replaceAll() {
        let query = findField.stringValue
        let replacement = replaceField.stringValue
        let options = options
        guard let expression = FileSearch.expression(for: query, options: options) else { return NSSound.beep() }
        remember()
        guard let sources = sources() else { return Prompt.show("Open a folder first", message: "Replace in Files works in the open project folder.") }
        // Count first, so the question says how much will change.
        var perFile: [(URL, Int)] = []
        for (url, openText) in sources {
            guard let text = openText ?? FileSearch.text(of: url) else { continue }
            let count = expression.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            if count > 0 { perFile.append((url, count)) }
        }
        let total = perFile.reduce(0) { $0 + $1.1 }
        guard total > 0 else {
            onStatus?("No matches for “\(query)”")
            return NSSound.beep()
        }
        guard Prompt.confirm("Replace \(total) occurrence\(total == 1 ? "" : "s") in \(perFile.count) file\(perFile.count == 1 ? "" : "s")?",
                             message: "“\(query)” will be replaced with “\(replacement)”. Open files can be undone with ⌘Z; other files are saved right away.",
                             button: "Replace All") else { return }
        let handled = onReplaceInOpenDocuments?(expression, replacement, options.regularExpression, Set(perFile.map { $0.0.standardizedFileURL })) ?? (handled: [], count: 0)
        var replaced = handled.count
        var failed: [String] = []
        for (url, _) in perFile where !handled.handled.contains(url.standardizedFileURL) {
            guard let text = FileSearch.text(of: url) else { continue }
            let result = FileSearch.replace(in: text, expression: expression, with: replacement, regularExpression: options.regularExpression)
            do {
                try result.text.write(to: url, atomically: true, encoding: .utf8)
                replaced += result.count
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        onStatus?("Replaced \(replaced) occurrence\(replaced == 1 ? "" : "s") in \(perFile.count) file\(perFile.count == 1 ? "" : "s")")
        if !failed.isEmpty { Prompt.show("Some files couldn't be changed", message: failed.joined(separator: ", ")) }
        findAll()
    }

    #if DEBUG
    func debugFindAll(_ text: String) {
        _ = panel
        findField.stringValue = text
        findAll()
    }
    #endif
}
