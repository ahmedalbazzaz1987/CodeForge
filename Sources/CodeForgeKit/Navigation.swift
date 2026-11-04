import Foundation

/// A comment that says there's work left: Visual Studio's Task List tokens plus a few common ones.
public struct TaskComment: Sendable, Equatable {
    public let url: URL
    public let line: Int          // 1-based
    public let column: Int        // 1-based, UTF-16: where the token starts
    public let token: String      // TODO, FIXME…
    public let text: String       // the rest of the comment
}

/// View ▸ Task List: finds TODO, HACK and similar comments. Only real comments count, not the same words in code or strings.
public enum TaskScanner {
    public static let tokens = ["TODO", "FIXME", "HACK", "UNDONE", "BUG", "XXX"]
    private static let expression = try! NSRegularExpression(pattern: #"\b(TODO|FIXME|HACK|UNDONE|BUG|XXX)\b:?[ \t]*([^\r\n]*)"#)

    public static func tasks(in text: String, url: URL, language: Language) -> [TaskComment] {
        let ns = text as NSString
        let lines = TextLines(text)
        var result: [TaskComment] = []
        for token in Tokenizer(language: language).tokens(in: text) where token.kind == .comment {
            for match in expression.matches(in: text, range: token.range) {
                let position = lines.position(of: match.range.location)
                let note = ns.substring(with: match.range(at: 2)).replacingOccurrences(of: #"\s*(\*/|-->|\*@)\s*$"#, with: "", options: .regularExpression)
                result.append(TaskComment(url: url, line: position.line + 1, column: position.character + 1,
                                          token: ns.substring(with: match.range(at: 1)), text: note))
            }
        }
        return result
    }

    /// Every task in a folder's source files, in file and line order.
    public static func tasks(in folder: URL, limit: Int = 2000) -> [TaskComment] {
        var result: [TaskComment] = []
        for url in FileSearch.files(in: folder) {
            let language = Languages.forFile(named: url.lastPathComponent)
            guard language.id != Languages.plainText.id, let text = FileSearch.text(of: url) else { continue }
            result += tasks(in: text, url: url, language: language)
            if result.count >= limit { break }
        }
        return result
    }
}

/// Keeps bookmarked lines on the same code while text above them is edited.
public enum BookmarkLines {
    /// The lines after an edit that starts on `line` (1-based) and removes and adds line breaks.
    /// A bookmark inside removed lines moves to the line where the edit happened.
    public static func shift(_ lines: Set<Int>, editLine: Int, removed: Int, added: Int) -> Set<Int> {
        guard removed != added else { return lines }
        return Set(lines.map { bookmark in
            if bookmark <= editLine { return bookmark }
            if bookmark <= editLine + removed { return editLine + added }
            return bookmark - removed + added
        })
    }

    /// The next bookmark after a position (or before it, going backward), wrapping across files in order.
    public static func next(after place: (path: String, line: Int), in bookmarks: [String: Set<Int>], backward: Bool) -> (path: String, line: Int)? {
        let all = bookmarks.flatMap { path, lines in lines.map { (path: path, line: $0) } }
            .sorted { ($0.path, $0.line) < ($1.path, $1.line) }
        guard !all.isEmpty else { return nil }
        if backward { return all.last { ($0.path, $0.line) < (place.path, place.line) } ?? all.last }
        return all.first { ($0.path, $0.line) > (place.path, place.line) } ?? all.first
    }
}

/// View ▸ Navigate Backward and Forward: where you've been, like a browser's history.
public struct NavigationHistory<Place: Equatable> {
    public private(set) var back: [Place] = []
    public private(set) var forward: [Place] = []
    private let limit: Int

    public init(limit: Int = 100) { self.limit = limit }

    /// Call before jumping somewhere new. A new jump clears the forward list, as in a browser.
    public mutating func record(_ place: Place) {
        if back.last != place { back.append(place) }
        if back.count > limit { back.removeFirst(back.count - limit) }
        forward.removeAll()
    }

    public mutating func goBack(from current: Place) -> Place? {
        while let place = back.popLast() {
            if place == current { continue }
            forward.append(current)
            return place
        }
        return nil
    }

    public mutating func goForward(from current: Place) -> Place? {
        guard let place = forward.popLast() else { return nil }
        back.append(current)
        return place
    }
}
