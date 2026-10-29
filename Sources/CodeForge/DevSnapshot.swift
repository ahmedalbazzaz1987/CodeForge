#if DEBUG
import AppKit

/// Debug builds only: renders the window to a PNG and quits, for checking layouts without a screen.
///   CF_SNAPSHOT=/path/out.png  where to write the image (required)
///   CF_DARK=1                  dark appearance
///   CF_RUN=1                   press Run first and wait for it
///   CF_ACTION=selector:        send one more action to the window controller first (e.g. showTerminal:)
///   CF_TERMINAL="ls"           type a command into the Terminal tab first
enum DevSnapshot {
    static func runIfRequested(_ controller: WorkspaceWindowController) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["CF_SNAPSHOT"] else { return }
        if env["CF_DARK"] != nil { NSApp.appearance = NSAppearance(named: .darkAqua) }
        var delay = 1.5
        if env["CF_RUN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { controller.runActiveFile(nil) }
            delay = 5
        }
        if let action = env["CF_ACTION"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { _ = controller.perform(NSSelectorFromString(action), with: nil) }
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
            let view = controller.window!.contentView!.superview!
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    private static func find<T: NSView>(_ view: NSView, _ type: T.Type) -> T? {
        (view as? T) ?? view.subviews.lazy.compactMap { find($0, type) }.first
    }
}
#endif
