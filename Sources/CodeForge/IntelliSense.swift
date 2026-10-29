import AppKit
import CodeForgeKit

/// One open file's connection to its language server: keeps the server's copy in sync and asks it questions.
final class LanguageSession {
    struct Location {
        let url: URL
        let line: Int        // 1-based
        let column: Int      // 1-based
    }

    struct CompletionItem {
        let label: String
        let detail: String
        let kind: Int
        let text: String
        let filterText: String
        let sortText: String
        /// The range the server wants replaced (UTF-16 offsets), if it gave one.
        let replaceStart: Int?
    }

    let server: LanguageServer
    let url: URL
    private weak var document: EditorDocument?
    private var version = 1
    private var pendingChange: DispatchWorkItem?
    private var uri: String { url.absoluteString }

    init(document: EditorDocument, server: LanguageServer, url: URL) {
        self.document = document
        self.server = server
        self.url = url
        let languageId = LanguageServerSpecs.languageId(forLanguage: document.language.id, fileExtension: url.pathExtension)
        server.notify("textDocument/didOpen", ["textDocument": [
            "uri": uri, "languageId": languageId, "version": version, "text": document.textView.string,
        ]])
        server.whenReady { [weak server] in server?.pullDiagnostics(for: url) }
    }

    var triggerCharacters: Set<String> { server.triggerCharacters }

    func textChanged() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendChange() }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Sends any waiting edit now, so a request sees the latest text.
    func flush() {
        guard let work = pendingChange, !work.isCancelled else { return }
        work.cancel()
        sendChange()
    }

    private func sendChange() {
        pendingChange = nil
        guard let text = document?.textView.string else { return }
        version += 1
        server.notify("textDocument/didChange", [
            "textDocument": ["uri": uri, "version": version],
            "contentChanges": [["text": text]],
        ])
        server.pullDiagnostics(for: url)
    }

    func saved() {
        flush()
        server.notify("textDocument/didSave", ["textDocument": ["uri": uri]])
    }

    func close() {
        pendingChange?.cancel()
        server.notify("textDocument/didClose", ["textDocument": ["uri": uri]])
    }

    // MARK: Requests

    private func params(at offset: Int) -> [String: Any] {
        flush()
        let lines = TextLines(document?.textView.string ?? "")
        let position = lines.position(of: offset)
        return ["textDocument": ["uri": uri], "position": ["line": position.line, "character": position.character]]
    }

    func completion(at offset: Int, handler: @escaping ([CompletionItem]) -> Void) {
        let lines = TextLines(document?.textView.string ?? "")
        server.request("textDocument/completion", params(at: offset)) { result in
            let raw = (result as? [String: Any])?["items"] as? [[String: Any]] ?? result as? [[String: Any]] ?? []
            handler(raw.prefix(2000).compactMap { item in
                guard let label = item["label"] as? String else { return nil }
                var text = item["insertText"] as? String ?? label
                var replaceStart: Int?
                if let edit = item["textEdit"] as? [String: Any] {
                    text = edit["newText"] as? String ?? text
                    let range = (edit["range"] ?? edit["replace"] ?? edit["insert"]) as? [String: Any]
                    if let start = range?["start"] as? [String: Any], let line = start["line"] as? Int, let character = start["character"] as? Int {
                        replaceStart = lines.offset(line: line, character: character)
                    }
                }
                if item["insertTextFormat"] as? Int == 2 { text = Self.stripSnippet(text) }
                return CompletionItem(label: label.trimmingCharacters(in: .whitespaces), detail: item["detail"] as? String ?? "",
                                      kind: item["kind"] as? Int ?? 0, text: text,
                                      filterText: item["filterText"] as? String ?? label, sortText: item["sortText"] as? String ?? label,
                                      replaceStart: replaceStart)
            })
        }
    }

    func hover(at offset: Int, handler: @escaping (String?) -> Void) {
        server.request("textDocument/hover", params(at: offset)) { result in
            let contents = (result as? [String: Any])?["contents"]
            let text: String?
            if let markup = contents as? [String: Any] {
                text = markup["value"] as? String
            } else if let string = contents as? String {
                text = string
            } else if let list = contents as? [Any] {
                text = list.compactMap { ($0 as? String) ?? ($0 as? [String: Any])?["value"] as? String }.joined(separator: "\n\n")
            } else {
                text = nil
            }
            handler(text.map(HoverText.plain).flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    func definition(at offset: Int, handler: @escaping ([Location]) -> Void) {
        server.request("textDocument/definition", params(at: offset)) { handler(Self.locations($0)) }
    }

    struct Symbol {
        let name: String
        let line: Int          // 1-based line of the name
        let character: Int     // 0-based UTF-16 column of the name
        let endLine: Int       // 1-based last line of the body
    }

    /// Functions, methods, classes and other types in this file (nested ones included).
    func symbols(handler: @escaping ([Symbol]) -> Void) {
        flush()
        let interesting: Set<Int> = [5, 6, 9, 10, 11, 12, 23]   // class, method, constructor, enum, interface, function, struct
        let lines = (document?.textView.string ?? "").components(separatedBy: "\n")
        server.request("textDocument/documentSymbol", ["textDocument": ["uri": uri]]) { result in
            var symbols: [Symbol] = []
            /// Older servers give only the whole declaration's range; point at the name inside it instead.
            func nameColumn(_ name: String, line: Int, from column: Int) -> Int {
                guard lines.indices.contains(line), !name.isEmpty else { return column }
                let text = lines[line] as NSString
                let found = text.range(of: name, options: [], range: NSRange(location: min(column, text.length), length: text.length - min(column, text.length)))
                return found.location == NSNotFound ? column : found.location
            }
            func position(_ range: Any?) -> (Int, Int)? {
                guard let start = (range as? [String: Any])?["start"] as? [String: Any],
                      let line = start["line"] as? Int, let character = start["character"] as? Int else { return nil }
                return (line, character)
            }
            func endLine(_ range: Any?) -> Int? { ((range as? [String: Any])?["end"] as? [String: Any])?["line"] as? Int }
            func walk(_ items: [[String: Any]]) {
                for item in items {
                    let range = item["range"] ?? (item["location"] as? [String: Any])?["range"]
                    if interesting.contains(item["kind"] as? Int ?? 0), let (line, character) = position(item["selectionRange"] ?? range) {
                        let name = item["name"] as? String ?? ""
                        let column = item["selectionRange"] == nil ? nameColumn(name, line: line, from: character) : character
                        symbols.append(Symbol(name: name, line: line + 1, character: column, endLine: (endLine(range) ?? line) + 1))
                    }
                    walk(item["children"] as? [[String: Any]] ?? [])
                }
            }
            walk(result as? [[String: Any]] ?? [])
            handler(symbols)
        }
    }

    /// How many places use the symbol at a position (its declaration not included).
    func referenceCount(line: Int, character: Int, handler: @escaping (Int) -> Void) {
        server.request("textDocument/references", [
            "textDocument": ["uri": uri], "position": ["line": line - 1, "character": character],
            "context": ["includeDeclaration": false],
        ]) { result in
            // The same place can come back under two spellings of its path (e.g. /tmp and /private/tmp).
            let places = Set(((result as? [[String: Any]]) ?? []).compactMap { location -> String? in
                guard let uri = location["uri"] as? String, let url = URL(string: uri),
                      let start = (location["range"] as? [String: Any])?["start"] as? [String: Any] else { return nil }
                return "\(url.resolvingSymlinksInPath().path):\(start["line"] ?? 0):\(start["character"] ?? 0)"
            })
            handler(places.count)
        }
    }

    func references(at offset: Int, handler: @escaping ([Location]) -> Void) {
        var parameters = params(at: offset)
        parameters["context"] = ["includeDeclaration": true]
        server.request("textDocument/references", parameters) { handler(Self.locations($0)) }
    }

    /// Asks for a rename and returns the edits per file: (start offset… is computed by the caller from line/character).
    func rename(at offset: Int, to newName: String, handler: @escaping ([URL: [(range: [String: Any], text: String)]]) -> Void) {
        var parameters = params(at: offset)
        parameters["newName"] = newName
        server.request("textDocument/rename", parameters) { result in
            var edits: [URL: [(range: [String: Any], text: String)]] = [:]
            let workspaceEdit = result as? [String: Any]
            func add(_ uri: String, _ list: [[String: Any]]) {
                guard let url = URL(string: uri) else { return }
                for edit in list {
                    if let range = edit["range"] as? [String: Any], let text = edit["newText"] as? String {
                        edits[url, default: []].append((range, text))
                    }
                }
            }
            for (uri, list) in workspaceEdit?["changes"] as? [String: [[String: Any]]] ?? [:] { add(uri, list) }
            for change in workspaceEdit?["documentChanges"] as? [[String: Any]] ?? [] {
                if let uri = (change["textDocument"] as? [String: Any])?["uri"] as? String, let list = change["edits"] as? [[String: Any]] {
                    add(uri, list)
                }
            }
            handler(edits)
        }
    }

    private static func locations(_ result: Any?) -> [Location] {
        let list = result as? [[String: Any]] ?? (result as? [String: Any]).map { [$0] } ?? []
        return list.compactMap { item in
            guard let uri = (item["uri"] ?? item["targetUri"]) as? String, let url = URL(string: uri),
                  let range = (item["range"] ?? item["targetSelectionRange"]) as? [String: Any],
                  let start = range["start"] as? [String: Any],
                  let line = start["line"] as? Int, let character = start["character"] as? Int else { return nil }
            return Location(url: url, line: line + 1, column: character + 1)
        }
    }

    /// "print(${1:value})$0" → "print(value)"
    static func stripSnippet(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: #"\$\{\d+:([^}]*)\}|\$\{\d+\}|\$\d+"#) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "$1")
        }
        return result
    }
}

/// Events from the editor that IntelliSense reacts to.
protocol CodeTextViewAssistant: AnyObject {
    func textView(_ textView: CodeTextView, didInsert text: String)
    func textViewDidDeleteBackward(_ textView: CodeTextView)
    /// Return true to swallow an editing command (arrow keys, Return, Tab, Escape) while the completion list is open.
    func textView(_ textView: CodeTextView, handle command: Selector) -> Bool
    func textViewRequestedCompletion(_ textView: CodeTextView)
    func textView(_ textView: CodeTextView, hoverAt index: Int)
    func textViewEndedHover(_ textView: CodeTextView)
    func textView(_ textView: CodeTextView, goToDefinitionAt index: Int)
}

/// Completion list, hover info, definitions, references and rename for one window.
final class IntelliSense: CodeTextViewAssistant {
    var document: (CodeTextView) -> EditorDocument? = { _ in nil }
    var onOpenLocation: ((URL, Int, Int?) -> Void)?
    var onReferences: ((String, [LanguageSession.Location]) -> Void)?
    var onStatus: ((String) -> Void)?
    private let completion = CompletionPopup()
    private var hoverPopover: NSPopover?
    private var hoverIndex = -1
    private var requestGeneration = 0

    private static let identifierCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))

    // MARK: Completion

    func textView(_ textView: CodeTextView, didInsert text: String) {
        closeHover()
        guard let session = document(textView)?.session, !completion.isAccepting else { return }
        let isIdentifier = text.count == 1 && text.unicodeScalars.allSatisfy { Self.identifierCharacters.contains($0) }
        if completion.isVisible {
            if isIdentifier { return completion.refilter() }
            completion.hide()
        }
        if let last = text.last, session.triggerCharacters.contains(String(last)) {
            requestCompletion(textView, session: session)
        } else if isIdentifier, wordStart(in: textView) == textView.selectedRange().location - 1 {
            requestCompletion(textView, session: session)   // first letter of a new word
        }
    }

    func textViewDidDeleteBackward(_ textView: CodeTextView) {
        if completion.isVisible { completion.refilter() }
    }

    func textView(_ textView: CodeTextView, handle command: Selector) -> Bool {
        completion.isVisible && completion.handle(command)
    }

    func textViewRequestedCompletion(_ textView: CodeTextView) {
        guard let session = document(textView)?.session else { return NSSound.beep() }
        requestCompletion(textView, session: session)
    }

    private func requestCompletion(_ textView: CodeTextView, session: LanguageSession) {
        requestGeneration += 1
        let generation = requestGeneration
        let cursor = textView.selectedRange().location
        session.completion(at: cursor) { [weak self, weak textView] items in
            guard let self, let textView, generation == requestGeneration, !items.isEmpty else { return }
            let start = items.compactMap(\.replaceStart).min() ?? wordStart(in: textView)
            completion.show(items, in: textView, wordStart: min(start, textView.selectedRange().location))
        }
    }

    private func wordStart(in textView: NSTextView) -> Int {
        let ns = textView.string as NSString
        var index = textView.selectedRange().location
        while index > 0, let scalar = UnicodeScalar(ns.character(at: index - 1)), Self.identifierCharacters.contains(scalar) {
            index -= 1
        }
        return index
    }

    // MARK: Hover

    func textView(_ textView: CodeTextView, hoverAt index: Int) {
        guard index != hoverIndex, let document = document(textView) else { return }
        closeHover()
        hoverIndex = index
        let problem = document.diagnosticMessage(at: index)
        let show: (String?) -> Void = { [weak self, weak textView] info in
            guard let self, let textView, hoverIndex == index else { return }
            let text = [problem, info].compactMap { $0 }.joined(separator: "\n\n")
            if !text.isEmpty { showHover(text, at: index, in: textView) }
        }
        if let session = document.session {
            session.hover(at: index, handler: show)
        } else {
            show(nil)
        }
    }

    func textViewEndedHover(_ textView: CodeTextView) {
        closeHover()
    }

    private func showHover(_ text: String, at index: Int, in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer, textView.window != nil else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        let label = NSTextField(wrappingLabelWithString: String(text.prefix(1500)))
        label.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        label.preferredMaxLayoutWidth = 520
        label.isSelectable = true
        let controller = NSViewController()
        let size = label.fittingSize
        label.frame = NSRect(x: 10, y: 8, width: min(size.width, 520), height: size.height)
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 20, height: label.frame.height + 16))
        controller.view.addSubview(label)
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .semitransient
        popover.animates = false
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
        hoverPopover = popover
    }

    func closeHover() {
        hoverIndex = -1
        hoverPopover?.close()
        hoverPopover = nil
    }

    // MARK: Navigation

    func textView(_ textView: CodeTextView, goToDefinitionAt index: Int) {
        guard let session = document(textView)?.session else {
            onStatus?("Go to Definition needs IntelliSense for this language")
            return NSSound.beep()
        }
        session.definition(at: index) { [weak self] locations in
            guard let location = locations.first else {
                self?.onStatus?("No definition found")
                return NSSound.beep()
            }
            self?.onOpenLocation?(location.url, location.line, location.column)
        }
    }

    func findReferences(in textView: CodeTextView) {
        guard let session = document(textView)?.session else { return NSSound.beep() }
        let ns = textView.string as NSString
        let index = textView.selectedRange().location
        let word = wordRange(in: ns, at: index).map { ns.substring(with: $0) } ?? "symbol"
        session.references(at: index) { [weak self] in self?.onReferences?(word, $0) }
    }

    /// Asks for a new name and renames the symbol everywhere the language server knows about.
    func rename(in textView: CodeTextView, documents: [EditorDocument]) {
        guard let session = document(textView)?.session else { return NSSound.beep() }
        let ns = textView.string as NSString
        let index = textView.selectedRange().location
        guard let range = wordRange(in: ns, at: index) else { return NSSound.beep() }
        let old = ns.substring(with: range)
        guard let new = Prompt.ask("Rename “\(old)”", message: "Enter the new name. Every reference is updated.",
                                   defaultValue: old, confirm: "Rename")?.trimmingCharacters(in: .whitespaces),
              !new.isEmpty, new != old else { return }
        session.rename(at: range.location, to: new) { [weak self] edits in
            guard !edits.isEmpty else {
                self?.onStatus?("Nothing to rename here")
                return NSSound.beep()
            }
            var count = 0
            for (url, list) in edits {
                count += list.count
                if let open = documents.first(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
                    open.apply(list)
                } else if var text = try? String(contentsOf: url, encoding: .utf8) {
                    text = Self.apply(list, to: text)
                    try? text.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            self?.onStatus?("Renamed \(count) occurrence\(count == 1 ? "" : "s") in \(edits.count) file\(edits.count == 1 ? "" : "s")")
        }
    }

    static func apply(_ edits: [(range: [String: Any], text: String)], to text: String) -> String {
        let lines = TextLines(text)
        let ns = NSMutableString(string: text)
        for (start, end, newText) in edits.compactMap({ resolve($0, lines) }).sorted(by: { $0.0 > $1.0 }) {
            ns.replaceCharacters(in: NSRange(location: start, length: end - start), with: newText)
        }
        return ns as String
    }

    static func resolve(_ edit: (range: [String: Any], text: String), _ lines: TextLines) -> (Int, Int, String)? {
        guard let start = edit.range["start"] as? [String: Any], let end = edit.range["end"] as? [String: Any],
              let sl = start["line"] as? Int, let sc = start["character"] as? Int,
              let el = end["line"] as? Int, let ec = end["character"] as? Int else { return nil }
        return (lines.offset(line: sl, character: sc), lines.offset(line: el, character: ec), edit.text)
    }

    private func wordRange(in ns: NSString, at index: Int) -> NSRange? {
        var start = index, end = index
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length, let scalar = UnicodeScalar(ns.character(at: i)) else { return false }
            return Self.identifierCharacters.contains(scalar)
        }
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}

/// The IntelliSense list that appears under the cursor.
final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let table = NSTableView()
    private var items: [LanguageSession.CompletionItem] = []
    private var shown: [LanguageSession.CompletionItem] = []
    private weak var textView: NSTextView?
    private var wordStart = 0
    private(set) var isAccepting = false

    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")))
        table.headerView = nil
        table.rowHeight = 20
        table.intercellSpacing = .zero
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(accept)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = Theme.sidebar
        box.borderColor = Theme.separator
        box.borderWidth = 1
        box.cornerRadius = 4
        box.contentViewMargins = NSSize(width: 1, height: 1)
        box.contentView = scroll
        panel.contentView = box
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
    }

    func show(_ items: [LanguageSession.CompletionItem], in textView: NSTextView, wordStart: Int) {
        self.items = items
        self.textView = textView
        self.wordStart = wordStart
        refilter()
    }

    func refilter() {
        guard let textView else { return hide() }
        let cursor = textView.selectedRange().location
        guard cursor >= wordStart else { return hide() }
        let prefix = (textView.string as NSString).substring(with: NSRange(location: wordStart, length: cursor - wordStart))
        if prefix.isEmpty {
            shown = items.sorted { $0.sortText < $1.sortText }
        } else {
            shown = items.compactMap { item in FuzzyMatch.score(prefix, item.filterText).map { (item, $0) } }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.sortText < $1.0.sortText }
                .map(\.0)
        }
        if shown.count > 300 { shown = Array(shown.prefix(300)) }
        // Nothing left, or the only match is exactly what's typed.
        guard !shown.isEmpty, !(shown.count == 1 && shown[0].text == prefix) else { return hide() }
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)
        position()
    }

    private func position() {
        guard let textView, let window = textView.window else { return }
        let caret = textView.firstRect(forCharacterRange: NSRange(location: wordStart, length: 0), actualRange: nil)
        let height = CGFloat(min(shown.count, 10)) * table.rowHeight + 4
        var frame = NSRect(x: caret.minX - 26, y: caret.minY - height - 2, width: 440, height: height)
        if let screen = window.screen?.visibleFrame, frame.minY < screen.minY {
            frame.origin.y = caret.maxY + 2   // no room below: open above the line
        }
        panel.setFrame(frame, display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func handle(_ command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)): move(9)
        case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)): move(-9)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): accept()
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)): hide()
        case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)):
            hide()
            return false
        default: return false
        }
        return true
    }

    private func move(_ delta: Int) {
        let row = min(max(table.selectedRow + delta, 0), shown.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func accept() {
        guard let textView, shown.indices.contains(table.selectedRow) else { return hide() }
        let item = shown[table.selectedRow]
        let cursor = textView.selectedRange().location
        let start = min(wordStart, cursor)
        hide()
        isAccepting = true
        textView.insertText(item.text, replacementRange: NSRange(location: start, length: cursor - start))
        isAccepting = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = shown[row]
        let (letter, color) = Self.badge(for: item.kind)
        let badge = NSTextField(labelWithString: letter)
        badge.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        badge.textColor = color
        badge.alignment = .center
        let label = NSTextField(labelWithString: item.label)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: item.detail)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.alignment = .right
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [badge, label, NSView(), detail])
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 8)
        badge.widthAnchor.constraint(equalToConstant: 14).isActive = true
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return row
    }

    /// LSP CompletionItemKind → a letter and color, like Visual Studio's icons.
    private static func badge(for kind: Int) -> (String, NSColor) {
        switch kind {
        case 2, 3, 4: ("ƒ", .systemPurple)              // method, function, constructor
        case 5, 10: ("◆", .systemBlue)                   // field, property
        case 6, 12, 21: ("v", .systemBlue)               // variable, value, constant
        case 7, 22: ("C", .systemOrange)                 // class, struct
        case 8: ("I", .systemTeal)                       // interface
        case 9: ("{}", .systemGray)                      // module
        case 13, 20: ("E", .systemYellow)                // enum, enum member
        case 14: ("k", .systemPink)                      // keyword
        case 15: ("⋯", .systemGray)                      // snippet
        case 25: ("T", .systemTeal)                      // type parameter
        default: ("•", .secondaryLabelColor)
        }
    }
}
