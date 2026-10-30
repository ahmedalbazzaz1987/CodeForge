#if DEBUG
import AppKit
import CodeForgeKit

/// Debug builds only: renders the window to a PNG and quits, for checking layouts without a screen.
///   CF_SNAPSHOT=/path/out.png  where to write the image (required)
///   CF_DARK=1                  dark appearance
///   CF_RUN=1                   press Run first and wait for it
///   CF_ACTION=selector:        send one more action to the window controller first (e.g. showTerminal:)
///   CF_TERMINAL="ls"           type a command into the Terminal tab first
///   CF_LSP_PROBE=word          print completion, hover and definition results for the first "word" in the open file
enum DevSnapshot {
    static func runIfRequested(_ controller: WorkspaceWindowController) {
        let env = ProcessInfo.processInfo.environment
        if let word = env["CF_LSP_PROBE"] { probe(controller, word: word) }
        guard let path = env["CF_SNAPSHOT"] else { return }
        if env["CF_DARK"] != nil { NSApp.appearance = NSAppearance(named: .darkAqua) }
        var delay = Double(env["CF_DELAY"] ?? "") ?? 1.5
        if env["CF_RUN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { controller.runActiveFile(nil) }
            delay = 5
        }
        if let line = env["CF_BREAK"].flatMap(Int.init) {
            // Set a breakpoint on a line of the open file.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let textView = find(controller.window!.contentView!, CodeTextView.self),
                      let document = controller.documentForProbe(textView) else { return }
                document.reveal(line: line, column: nil)
                controller.toggleBreakpointAtCursor(nil)
            }
        }
        if let name = env["CF_TOOLBOX"] {
            // Insert a Toolbox item (by name) at the end of the first <body> line, like a double-click.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let textView = find(controller.window!.contentView!, CodeTextView.self),
                      let document = controller.documentForProbe(textView),
                      let item = ToolboxCatalog.groups(forLanguage: document.language.id).flatMap(\.items).first(where: { $0.name == name }) else { return }
                let ns = textView.string as NSString
                let body = ns.range(of: "<body>")
                textView.setSelectedRange(NSRange(location: NSMaxRange(ns.lineRange(for: body)) , length: 0))
                textView.insertSnippet(item)
            }
        }
        if let action = env["CF_ACTION"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { _ = controller.perform(NSSelectorFromString(action), with: nil) }
        }
        if let text = env["CF_COMPLETE"] {
            // Put the cursor after `text` and open the completion list.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let textView = find(controller.window!.contentView!, CodeTextView.self) else { return }
                let range = (textView.string as NSString).range(of: text)
                textView.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
                textView.showCompletions(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                guard let popup = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }), let view = popup.contentView else {
                    return print("SNAPSHOT: no completion list")
                }
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".popup.png"))
                print("SNAPSHOT: popup at", popup.frame, "window", controller.window!.frame)
            }
            delay = max(delay, 5)
        }
        if let command = env["CF_TERMINAL"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard let field = find(controller.window!.contentView!, TerminalView.self)?.inputField else { return }
                field.stringValue = command
                field.sendAction(field.action, to: field.target)
            }
            delay = 4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let textView = find(controller.window!.contentView!, CodeTextView.self) { print("LENSES:", textView.lenses) }
            // Any other visible window (a sheet, Options) is saved next to the main image.
            for (index, extra) in NSApp.windows.enumerated() where extra !== controller.window && extra.isVisible {
                guard let view = extra.contentView?.superview ?? extra.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".window\(index).png"))
            }
            let view = controller.window!.contentView!.superview!
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    private static func probe(_ controller: WorkspaceWindowController, word: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard let textView = find(controller.window!.contentView!, CodeTextView.self),
                  let session = controller.documentForProbe(textView)?.session else { print("PROBE: no session"); exit(1) }
            let ns = textView.string as NSString
            let found = ns.range(of: word)
            print("PROBE: server \(session.server.spec.name), word at \(found.location)")
            session.hover(at: found.location + 1) { print("PROBE hover:", $0 ?? "nil") }
            session.definition(at: found.location + 1) { print("PROBE definition:", $0.map { "\($0.url.lastPathComponent):\($0.line):\($0.column)" }) }
            session.references(at: found.location + 1) { print("PROBE references:", $0.count) }
            // Complete after "word." on the last line.
            let dotted = ns.range(of: word + ".")
            session.completion(at: NSMaxRange(dotted)) { items in
                print("PROBE completion count:", items.count, "by sortText:", items.sorted { $0.sortText < $1.sortText }.prefix(6).map { "\($0.label)@\($0.replaceStart ?? -1)" })
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                print("PROBE diagnostics:", controller.diagnosticsForProbe())
                exit(0)
            }
        }
    }

    private static func find<T: NSView>(_ view: NSView, _ type: T.Type) -> T? {
        (view as? T) ?? view.subviews.lazy.compactMap { find($0, type) }.first
    }
}
#endif
