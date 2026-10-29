import AppKit
import CodeForgeKit

/// One open file: its text view, language and saved state.
final class EditorDocument: NSObject, NSTextViewDelegate {
    var url: URL? { didSet { onStateChange?() } }
    var language: Language {
        didSet {
            tokenizer = Tokenizer(language: language)
            textView.configure(for: language)
            rehighlight()
            onStateChange?()
        }
    }
    private(set) var isDirty = false {
        didSet { if oldValue != isDirty { onStateChange?() } }
    }
    let textView: CodeTextView
    let scrollView = NSScrollView()
    let ruler: LineNumberRuler
    private let untitledName: String
    private var tokenizer: Tokenizer
    private var highlightGeneration = 0

    /// The language server connection, when IntelliSense is available for this file.
    var session: LanguageSession? {
        willSet { session?.close() }
    }
    private var diagnosticRanges: [(range: NSRange, message: String)] = []
    var onStateChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?

    var displayName: String { url?.lastPathComponent ?? untitledName }

    enum ReadError: LocalizedError {
        case binary, tooLarge
        var errorDescription: String? {
            switch self {
            case .binary: "This looks like a binary file, so CodeForge won't open it as text."
            case .tooLarge: "The file is larger than 25 MB."
            }
        }
    }

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if data.count > 25_000_000 { throw ReadError.tooLarge }
        if data.prefix(8000).contains(0) { throw ReadError.binary }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    init(url: URL?, text: String, fontSize: CGFloat, untitledName: String = "Untitled") {
        self.url = url
        self.untitledName = untitledName
        let firstLine = text.prefix(200).split(separator: "\n", maxSplits: 1).first.map(String.init)
        language = url.map { Languages.forFile(named: $0.lastPathComponent, firstLine: firstLine) } ?? Languages.plainText
        tokenizer = Tokenizer(language: language)
        textView = CodeTextView(usingTextLayoutManager: false)   // TextKit 1: needed for the ruler and fast highlighting
        ruler = LineNumberRuler(textView: textView, scrollView: scrollView)
        super.init()

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false   // the text view paints its own background

        textView.frame = scrollView.bounds
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true   // no line wrapping
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.text
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.configure(for: language)
        scrollView.documentView = textView

        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        textView.string = text
        setFontSize(fontSize)
        textView.delegate = self
        textView.undoManager?.removeAllActions()
        ruler.textDidChange()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func setFontSize(_ size: CGFloat) {
        let font = Theme.editorFont(size: size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: font]).width
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.text, .paragraphStyle: paragraph]
        textView.font = font
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = attributes
        if let storage = textView.textStorage {
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
        ruler.font = .monospacedDigitSystemFont(ofSize: max(size - 1, 8), weight: .regular)
        rehighlight()
    }

    func write() throws {
        guard let url else { return }
        try textView.string.write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
        session?.saved()
    }

    /// 1-based line and column of the insertion point.
    var cursorPosition: (line: Int, column: Int) {
        let location = textView.selectedRange().location
        let line = ruler.line(at: location)
        return (line + 1, location - ruler.lineStart(line) + 1)
    }

    /// Moves the cursor to a 1-based line and column and scrolls it into view.
    func reveal(line: Int, column: Int?) {
        let ns = textView.string as NSString
        let start = ruler.lineStart(line - 1)
        let lineRange = ns.lineRange(for: NSRange(location: min(start, ns.length), length: 0))
        let location = min(start + max((column ?? 1) - 1, 0), NSMaxRange(lineRange))
        textView.setSelectedRange(NSRange(location: min(location, ns.length), length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        textView.window?.makeFirstResponder(textView)
        if lineRange.length > 0 { textView.showFindIndicator(for: lineRange) }
    }

    /// Underlines lines with errors (red) and warnings (yellow) until the next edit.
    func setDiagnostics(_ diagnostics: [Diagnostic]) {
        guard let layoutManager = textView.layoutManager else { return }
        let ns = textView.string as NSString
        let all = NSRange(location: 0, length: ns.length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: all)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: all)
        diagnosticRanges = []
        let lines = TextLines(textView.string)
        for diagnostic in diagnostics {
            var range: NSRange
            if let column = diagnostic.column, let endLine = diagnostic.endLine, let endColumn = diagnostic.endColumn {
                // An exact range from a language server; widen empty ranges to one character.
                let start = lines.offset(line: diagnostic.line - 1, character: column - 1)
                let end = lines.offset(line: endLine - 1, character: endColumn - 1)
                range = NSRange(location: start, length: max(end - start, start < ns.length ? 1 : 0))
            } else {
                range = ns.lineRange(for: NSRange(location: min(ruler.lineStart(diagnostic.line - 1), ns.length), length: 0))
                // Skip leading indentation and the line break.
                while range.length > 0, [0x20, 0x09].contains(ns.character(at: range.location)) { range.location += 1; range.length -= 1 }
                while range.length > 0, [0x0A, 0x0D].contains(ns.character(at: NSMaxRange(range) - 1)) { range.length -= 1 }
            }
            guard range.length > 0, NSMaxRange(range) <= ns.length else { continue }
            diagnosticRanges.append((range, (diagnostic.severity == .error ? "Error: " : "Warning: ") + diagnostic.message))
            layoutManager.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: diagnostic.severity == .error ? Theme.errorRed : Theme.warningYellow,
            ], forCharacterRange: range)
        }
        hasDiagnostics = !diagnostics.isEmpty
    }

    /// Highlights the line where the debugger is paused (1-based), or clears it.
    func setExecutionLine(_ line: Int?) {
        guard let layoutManager = textView.layoutManager else { return }
        let ns = textView.string as NSString
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: ns.length))
        ruler.executionLine = line
        guard let line else { return }
        let range = ns.lineRange(for: NSRange(location: min(ruler.lineStart(line - 1), ns.length), length: 0))
        layoutManager.addTemporaryAttribute(.backgroundColor, value: Theme.executionLine, forCharacterRange: range)
        reveal(line: line, column: nil)
    }

    /// The error or warning message under a character, for hover info.
    func diagnosticMessage(at index: Int) -> String? {
        let messages = diagnosticRanges.filter { NSLocationInRange(index, $0.range) }.map(\.message)
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    /// Applies language-server text edits as one undoable change.
    func apply(_ edits: [(range: [String: Any], text: String)]) {
        let lines = TextLines(textView.string)
        let resolved = edits.compactMap { IntelliSense.resolve($0, lines) }.sorted { $0.0 > $1.0 }
        guard !resolved.isEmpty else { return }
        textView.undoManager?.beginUndoGrouping()
        for (start, end, text) in resolved {
            let range = NSRange(location: start, length: end - start)
            if textView.shouldChangeText(in: range, replacementString: text) {
                textView.textStorage?.replaceCharacters(in: range, with: text)
                textView.didChangeText()
            }
        }
        textView.undoManager?.endUndoGrouping()
    }

    private var hasDiagnostics = false

    // MARK: Highlighting

    /// Small files are highlighted synchronously on every edit; large ones on a background queue after a pause.
    func rehighlight() {
        highlightGeneration += 1
        let generation = highlightGeneration
        let text = textView.string
        let length = (text as NSString).length
        guard length < 3_000_000 else { return apply([], length: length) }
        if length < 150_000 {
            return apply(tokenizer.tokens(in: text), length: length)
        }
        let tokenizer = self.tokenizer
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard self?.highlightGeneration == generation else { return }
            let tokens = tokenizer.tokens(in: text)
            DispatchQueue.main.async {
                guard let self, self.highlightGeneration == generation else { return }
                self.apply(tokens, length: length)
            }
        }
    }

    private func apply(_ tokens: [Token], length: Int) {
        guard let layoutManager = textView.layoutManager, (textView.string as NSString).length == length else { return }
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        for token in tokens {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: Theme.color(for: token.kind), forCharacterRange: token.range)
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        isDirty = true
        if !textView.lenses.isEmpty { textView.lenses = [:] }   // positions are stale until the next save
        if hasDiagnostics { setDiagnostics([]) }
        session?.textChanged()
        rehighlight()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        onSelectionChange?()
    }
}
