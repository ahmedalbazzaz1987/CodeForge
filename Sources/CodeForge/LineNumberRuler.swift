import AppKit

/// Line numbers in the editor's left margin, with breakpoints (click to toggle) and the debugger's current line.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    /// 1-based lines with breakpoints.
    var breakpoints: Set<Int> = [] { didSet { needsDisplay = true } }
    /// 1-based line where the debugger is paused.
    var executionLine: Int? { didSet { needsDisplay = true } }
    var onToggleBreakpoint: ((Int) -> Void)?
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular) {
        didSet { updateThickness(); needsDisplay = true }
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSTextView.didChangeSelectionNotification, object: textView)
        textDidChange()
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// 0-based line index containing a character location.
    func line(at location: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func lineStart(_ line: Int) -> Int { lineStarts[min(max(line, 0), lineStarts.count - 1)] }

    @objc func textDidChange() {
        var starts = [0]
        var index = 0
        for unit in textView?.string.utf16 ?? "".utf16 {
            index += 1
            if unit == 10 { starts.append(index) }
        }
        lineStarts = starts
        updateThickness()
        needsDisplay = true
    }

    @objc private func redraw() { needsDisplay = true }

    private func updateThickness() {
        let digits = max(3, String(lineStarts.count).count)
        let width = ceil(("8" as NSString).size(withAttributes: [.font: font]).width * CGFloat(digits) + 34)
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        textView.backgroundColor.setFill()
        bounds.intersection(rect).fill()   // the rect AppKit passes can extend past the ruler

        let ns = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let currentLine = line(at: textView.selectedRange().location)
        let editorAscender = textView.font?.ascender ?? font.ascender
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        var index = line(at: characters.location)
        while index < lineStarts.count {
            let start = lineStarts[index]
            var lineRect: NSRect
            if start >= ns.length {
                guard layoutManager.extraLineFragmentTextContainer != nil || ns.length == 0 else { break }
                lineRect = layoutManager.extraLineFragmentRect
            } else {
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
            }
            if lineRect.minY > visible.maxY { break }
            lineRect.origin.y += textView.textContainerOrigin.y
            let y = convert(lineRect, from: textView).minY + (editorAscender - font.ascender)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: index == currentLine ? Theme.gutterCurrent : Theme.gutterText,
                .paragraphStyle: paragraph,
            ]
            ("\(index + 1)" as NSString).draw(in: NSRect(x: 0, y: y, width: ruleThickness - 10, height: lineRect.height), withAttributes: attributes)
            let marker = NSRect(x: 4, y: convert(lineRect, from: textView).midY - 6, width: 12, height: 12)
            if breakpoints.contains(index + 1) {
                Theme.errorRed.setFill()
                NSBezierPath(ovalIn: marker).fill()
            }
            if executionLine == index + 1 {
                let arrow = NSBezierPath()
                arrow.move(to: NSPoint(x: marker.minX, y: marker.minY + 2))
                arrow.line(to: NSPoint(x: marker.maxX - 1, y: marker.midY))
                arrow.line(to: NSPoint(x: marker.minX, y: marker.maxY - 2))
                arrow.close()
                NSColor.systemYellow.setFill()
                arrow.fill()
                NSColor.black.withAlphaComponent(0.5).setStroke()
                arrow.stroke()
            }
            index += 1
        }
    }

    // NSRulerView's own accessibility press opens a tab-stop editor; toggle a breakpoint on the cursor's line instead.
    override func accessibilityPerformPress() -> Bool {
        guard let textView else { return false }
        onToggleBreakpoint?(line(at: textView.selectedRange().location) + 1)
        return true
    }

    override func accessibilityLabel() -> String? { "Line numbers and breakpoints" }

    override func mouseDown(with event: NSEvent) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let point = textView.convert(event.locationInWindow, from: nil)
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: point.y - textView.textContainerOrigin.y), in: container)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        onToggleBreakpoint?(line(at: min(character, (textView.string as NSString).length)) + 1)
    }
}
