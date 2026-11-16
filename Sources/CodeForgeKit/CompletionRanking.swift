import Foundation

/// How well what's typed matches a name in the completion list. Better kinds of match always come first: the exact name,
/// then names that start with it (same case first), then capital letters or word starts (`sb` → StringBuilder,
/// `wl` → WriteLine, `get_val` → get_value), then names that contain it, then names that merely have its letters in order.
public enum CompletionMatch {
    public static func score(_ query: String, _ candidate: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let tier: Int
        if candidate == query {
            tier = 6
        } else if candidate.lowercased() == query.lowercased() {
            tier = 5
        } else if candidate.hasPrefix(query) {
            tier = 4
        } else if candidate.lowercased().hasPrefix(query.lowercased()) {
            tier = 3
        } else if matchesWordStarts(query, candidate) {
            tier = 2
        } else if candidate.lowercased().contains(query.lowercased()) {
            tier = 1
        } else if FuzzyMatch.score(query, candidate) != nil {
            tier = 0
        } else {
            return nil
        }
        // Within a kind of match, shorter names first (Write before WriteLine).
        return tier * 1_000_000 - min((candidate as NSString).length, 999)
    }

    /// The words of a name: `StringBuilder` → String, Builder; `get_value` → get, value; `HTTPServer` → HTTP, Server.
    static func words(_ name: String) -> [String] {
        let characters = Array(name)
        var words: [String] = []
        var current = ""
        for (i, c) in characters.enumerated() {
            let previous: Character? = i > 0 ? characters[i - 1] : nil
            let next: Character? = i + 1 < characters.count ? characters[i + 1] : nil
            let boundary = c.isUppercase && (previous.map { $0.isLowercase || $0.isNumber } ?? false
                || (previous?.isUppercase == true && next?.isLowercase == true))
            if "_-.$ ".contains(c) {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            if boundary, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(c)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// Whether the query is made of the starts of the name's words, in order, beginning with the first: `sb`, `strb`, `SBuild`.
    static func matchesWordStarts(_ query: String, _ candidate: String) -> Bool {
        let parts = words(candidate).map { Array($0.lowercased()) }
        let q = Array(query.lowercased().filter { $0 != "_" })
        guard let first = parts.first, let head = q.first, first.first == head else { return false }
        func match(_ qi: Int, _ wi: Int) -> Bool {
            if qi == q.count { return true }
            guard wi < parts.count else { return false }
            let word = parts[wi]
            var k = 0
            while k < word.count, qi + k < q.count, word[k] == q[qi + k] { k += 1 }
            // Take as much of this word as matches, or less, then go on with a later word.
            for taken in stride(from: k, through: 1, by: -1) {
                for next in (wi + 1)...parts.count where match(qi + taken, next) { return true }
            }
            return false
        }
        return match(0, 0)
    }
}

/// The names picked from the completion list lately, per language, so the list offers them first next time (Visual Studio
/// does the same). Kept for the session.
public final class CompletionHistory {
    private let limit = 200
    private var recent: [String: [String]] = [:]

    public init() {}

    public func used(_ label: String, languageId: String) {
        guard !label.isEmpty else { return }
        var list = recent[languageId] ?? []
        list.removeAll { $0 == label }
        list.insert(label, at: 0)
        if list.count > limit { list.removeLast() }
        recent[languageId] = list
    }

    /// How recently a name was picked: 0 if not lately, up to 200 for the last one.
    public func recency(of label: String, languageId: String) -> Int {
        guard let index = recent[languageId]?.firstIndex(of: label) else { return 0 }
        return limit - index
    }
}
