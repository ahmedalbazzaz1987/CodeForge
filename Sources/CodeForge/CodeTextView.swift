import AppKit
import CodeForgeKit

/// The code editor: a plain-text NSTextView with current-line highlighting, auto-indent and line commands.
final class CodeTextView: NSTextView {
    var indentUnit = "    "
    var lineComment: String?
    var blockComment: (open: String, close: String)?
    var indentAfterColon = false

    func configure(for language: Language) {
        indentUnit = language.indentWithTabs ? "\t" : "    "
        lineComment = language.lineComments.first
        blockComment = language.blockComment
        indentAfterColon = language.indentAfterColon
    }

    // MARK: Current line

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
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
