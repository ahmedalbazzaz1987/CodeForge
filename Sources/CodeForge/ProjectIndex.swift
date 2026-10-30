import AppKit
import CodeForgeKit

/// The declarations in the open project, for Class View, the Object Browser and IntelliSense without a language server.
final class ProjectIndex {
    static let shared = ProjectIndex()
    private(set) var symbols: [CodeSymbol] = []
    private(set) var isIndexing = false
    /// Called on the main queue whenever the symbols change.
    var onChange: (() -> Void)?
    private var folder: URL?
    private var generation = 0

    func setFolder(_ url: URL?) {
        guard url?.standardizedFileURL != folder?.standardizedFileURL else { return }
        folder = url?.standardizedFileURL
        rebuild()
    }

    func rebuild() {
        generation += 1
        let generation = generation
        guard let folder else {
            symbols = []
            onChange?()
            return
        }
        isIndexing = true
        onChange?()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = SymbolParser.index(folder: folder)
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.symbols = found
                self.isIndexing = false
                self.onChange?()
            }
        }
    }

    /// Re-reads one file after it's saved.
    func update(_ url: URL, text: String) {
        let url = url.standardizedFileURL
        guard let folder, url.path.hasPrefix(folder.path + "/") else { return }
        let language = Languages.forFile(named: url.lastPathComponent)
        symbols.removeAll { $0.url?.standardizedFileURL == url }
        if SymbolParser.supports(languageId: language.id) { symbols += SymbolParser.symbols(in: text, languageId: language.id, url: url) }
        onChange?()
    }

    /// The project's symbols, with one document's (possibly unsaved) text parsed fresh.
    func symbols(including document: EditorDocument) -> [CodeSymbol] {
        let url = document.url?.standardizedFileURL
        let text = document.textView.string
        guard SymbolParser.supports(languageId: document.language.id), (text as NSString).length < 400_000 else { return symbols }
        return symbols.filter { $0.url?.standardizedFileURL != url || url == nil } + SymbolParser.symbols(in: text, languageId: document.language.id, url: url)
    }
}

/// The code snippets library (built-in plus the user's own), saved in Application Support.
enum SnippetStore {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CodeForge").appendingPathComponent("Snippets.json")
    static var library = SnippetLibrary(contentsOf: url)
    static var onChange: (() -> Void)?

    static func save() {
        try? library.write(to: url)
        onChange?()
    }
}
