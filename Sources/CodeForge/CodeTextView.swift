import AppKit
import CodeForgeKit

/// The code editor: a plain-text NSTextView with current-line highlighting, auto-indent and line commands.
final class CodeTextView: NSTextView {
    var indentUnit = "    "
    var lineComment: String?
    var blockComment: (open: String, close: String)?
    var indentAfterColon = false
    weak var assistant: CodeTextViewAssistant?
    /// CodeLens text by 1-based line, drawn faintly after the end of the line.
    var lenses: [Int: String] = [:] { didSet { needsDisplay = true } }
    private var hoverTimer: Timer?

    func configure(for language: Language) {
        indentUnit = language.indentWithTabs ? "\t" : "    "
        lineComment = language.lineComments.first
        blockComment = language.blockComment
        indentAfterColon = language.indentAfterColon
    }

    // MARK: Current line

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawLenses(in: rect)
        guard let layoutManager, selectedRange().length == 0 else { return }
        let location = selectedRange().location
        let length = (string as NSString).length
        var lineRect: NSRect
        if length == 0 || (location >= length && layoutManager.extraLineFragmentTextContainer != nil) {
            lineRect = layoutManager.extraLineFragmentRect
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(location, length - 1))
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        lineRect.origin.x = 0
        lineRect.origin.y += textContainerOrigin.y
        lineRect.size.width = bounds.width
        Theme.currentLine.setFill()
        lineRect.intersection(rect).fill()
    }

    private func drawLenses(in rect: NSRect) {
        guard !lenses.isEmpty, let layoutManager, let textContainer else { return }
        let ns = string as NSString
        let lines = TextLines(string)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max((font?.pointSize ?? 13) - 2, 9)),
            .foregroundColor: Theme.lens,
        ]
        for (line, text) in lenses where line - 1 < lines.lineStarts.count {
            let start = lines.lineStarts[line - 1]
            guard start < ns.length else { continue }
            var lineRange = ns.lineRange(for: NSRange(location: start, length: 0))
            // Measure the text only: the line break's glyph reaches the edge of the (unbounded) container.
            while lineRange.length > 0, [0x0A, 0x0D].contains(ns.character(at: NSMaxRange(lineRange) - 1)) { lineRange.length -= 1 }
            guard lineRange.length > 0 else { continue }
            let glyphs = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var used = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            used.origin.x += textContainerOrigin.x
            used.origin.y += textContainerOrigin.y
            let point = NSPoint(x: used.maxX + 28, y: used.minY + 1)
            guard NSRect(x: point.x, y: used.minY, width: 600, height: used.height).intersects(rect) else { continue }
            (text as NSString).draw(at: point, withAttributes: attributes)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }

    // MARK: Typing

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let baseIndent = String(before.prefix { $0 == " " || $0 == "\t" })
        let last = before.trimmingCharacters(in: .whitespaces).last
        let pairs: [Character: unichar] = ["{": 0x7D, "[": 0x5D, "(": 0x29]

        var indent = baseIndent
        if let last, pairs[last] != nil || (indentAfterColon && last == ":") { indent += indentUnit }

        // `{|}` + Return puts the closing bracket on its own line.
        let after = NSMaxRange(selection)
        if let last, let close = pairs[last], after < ns.length, ns.character(at: after) == close {
            insertText("\n" + indent + "\n" + baseIndent, replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location + 1 + (indent as NSString).length, length: 0))
            return
        }
        insertText("\n" + indent, replacementRange: selection)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        insertTextWithoutAssistant(string, replacementRange: replacementRange)
        if let text = (string as? String) ?? (string as? NSAttributedString)?.string {
            assistant?.textView(self, didInsert: text)
        }
    }

    private func insertTextWithoutAssistant(_ string: Any, replacementRange: NSRange) {
        // Typing a closing brace on a blank line removes one level of indentation.
        if let text = string as? String, text == "}" {
            let ns = self.string as NSString
            let selection = selectedRange()
            let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
            let before = ns.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
            if selection.length == 0, !before.isEmpty, before.allSatisfy({ $0 == " " || $0 == "\t" }) {
                super.insertText(outdented(before) + "}", replacementRange: NSRange(location: lineStart, length: before.utf16.count))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        assistant?.textViewDidDeleteBackward(self)
    }

    override func doCommand(by selector: Selector) {
        if assistant?.textView(self, handle: selector) == true { return }
        super.doCommand(by: selector)
    }

    /// Escape and Edit ▸ Show Completions (⌃Space) open the IntelliSense list.
    override func complete(_ sender: Any?) {
        if let assistant { assistant.textViewRequestedCompletion(self) } else { super.complete(sender) }
    }

    @objc func showCompletions(_ sender: Any?) {
        assistant?.textViewRequestedCompletion(self)
    }

    // MARK: Hover and ⌘-click

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self && $0.options.contains(.mouseMoved) }) {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hoverTimer?.invalidate()
        assistant?.textViewEndedHover(self)
        let point = convert(event.locationInWindow, from: nil)
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self, let index = characterIndex(at: point) else { return }
            assistant?.textView(self, hoverAt: index)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverTimer?.invalidate()
    }

    override func mouseDown(with event: NSEvent) {
        hoverTimer?.invalidate()
        assistant?.textViewEndedHover(self)
        if event.modifierFlags.contains(.command), let index = characterIndex(at: convert(event.locationInWindow, from: nil)) {
            setSelectedRange(NSRange(location: index, length: 0))
            assistant?.textView(self, goToDefinitionAt: index)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        hoverTimer?.invalidate()
        assistant?.textViewEndedHover(self)
        super.keyDown(with: event)
    }

    /// The character under a point, or nil when the point is past the end of a line.
    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: inContainer, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -1, dy: -1).contains(inContainer) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        let character = (string as NSString).character(at: index)
        return character == 10 || character == 32 ? nil : index
    }

    override func insertTab(_ sender: Any?) {
        let selection = selectedRange()
        if (string as NSString).substring(with: selection).contains("\n") {
            indentSelection(sender)
        } else {
            insertText(indentUnit, replacementRange: selection)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        outdentSelection(sender)
    }

    // MARK: Line commands (Edit menu)

    /// Inserts a Toolbox item at the cursor, indented to match the line, with the cursor where the item says.
    func insertSnippet(_ item: ToolboxItem) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let indent = ns.substring(with: NSRange(location: lineStart, length: selection.location - lineStart)).prefix { $0 == " " || $0 == "\t" }
        var (text, cursor) = item.expanded(indent: String(indent))
        // At the start of a line that already has code, give the new item its own line.
        let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: selection.location, length: 0)))
        let after = ns.substring(with: NSRange(location: NSMaxRange(selection), length: max(lineEnd - NSMaxRange(selection), 0)))
        if indent.count == selection.location - lineStart, !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += "\n" + indent
        }
        insertText(text, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + cursor, length: 0))
        window?.makeFirstResponder(self)
    }

    @objc func indentSelection(_ sender: Any?) {
        transformLines { lines in lines.map { $0.isEmpty ? $0 : indentUnit + $0 } }
    }

    @objc func outdentSelection(_ sender: Any?) {
        transformLines { lines in lines.map(outdented) }
    }

    @objc func toggleComment(_ sender: Any?) {
        guard let marker = lineComment else {
            guard let block = blockComment else { return NSSound.beep() }
            let selection = selectedRange()
            let text = (string as NSString).substring(with: selection)
            let replacement: String
            if text.hasPrefix(block.open), text.hasSuffix(block.close), text.count >= block.open.count + block.close.count {
                replacement = String(text.dropFirst(block.open.count).dropLast(block.close.count))
            } else {
                replacement = block.open + text + block.close
            }
            replace(selection, with: replacement, select: NSRange(location: selection.location, length: replacement.utf16.count))
            return
        }
        transformLines { lines in
            let isBlank = { (line: String) in line.allSatisfy { $0 == " " || $0 == "\t" } }
            let content = lines.filter { !isBlank($0) }
            let commented = !content.isEmpty && content.allSatisfy { $0.drop { $0 == " " || $0 == "\t" }.hasPrefix(marker) }
            if commented {
                return lines.map { line in
                    guard let range = line.range(of: marker) else { return line }
                    var result = line
                    result.removeSubrange(range)
                    if result[range.lowerBound...].hasPrefix(" ") { result.remove(at: range.lowerBound) }
                    return result
                }
            }
            let indent = content.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
            return lines.map { line in
                guard !isBlank(line) else { return line }
                let at = line.index(line.startIndex, offsetBy: indent)
                return String(line[..<at]) + marker + " " + String(line[at...])
            }
        }
    }

    @objc func goToLine(_ sender: Any?) {
        guard let input = Prompt.ask("Go to Line", message: "Enter a line number, or line:column.") else { return }
        let numbers = input.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let line = numbers.first, line > 0 else { return }
        let ns = string as NSString
        var location = 0
        var current = 1
        while current < line, location < ns.length {
            location = NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0)))
            current += 1
        }
        let lineRange = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        if numbers.count > 1 {
            location = min(location + max(numbers[1] - 1, 0), NSMaxRange(lineRange))
        }
        setSelectedRange(NSRange(location: min(location, ns.length), length: 0))
        scrollRangeToVisible(selectedRange())
        if lineRange.length > 0 { showFindIndicator(for: lineRange) }
    }

    // MARK: Helpers

    private func outdented(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        let spaces = line.prefix { $0 == " " }.count
        return String(line.dropFirst(min(spaces, 4)))
    }

    /// Replaces the lines touched by the selection, as one undoable edit.
    private func transformLines(_ transform: ([String]) -> [String]) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineRange = ns.lineRange(for: selection)
        let original = ns.substring(with: lineRange)
        let endsWithNewline = original.hasSuffix("\n")
        var lines = original.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        let updated = transform(lines).joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        let updatedLength = updated.utf16.count
        let newSelection: NSRange
        if selection.length == 0 {
            let caret = selection.location + updatedLength - original.utf16.count
            newSelection = NSRange(location: max(lineRange.location, caret), length: 0)
        } else {
            newSelection = NSRange(location: lineRange.location, length: updatedLength - (endsWithNewline ? 1 : 0))
        }
        replace(lineRange, with: updated, select: newSelection)
    }

    private func replace(_ range: NSRange, with text: String, select: NSRange) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(select)
    }
}
