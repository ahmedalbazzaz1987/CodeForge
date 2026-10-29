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
    }

    /// 1-based line and column of the insertion point.
    var cursorPosition: (line: Int, column: Int) {
        let location = textView.selectedRange().location
        let line = ruler.line(at: location)
        return (line + 1, location - ruler.lineStart(line) + 1)
    }

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
        rehighlight()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        onSelectionChange?()
    }
}
