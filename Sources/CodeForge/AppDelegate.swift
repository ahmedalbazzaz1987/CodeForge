import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windowController: WorkspaceWindowController!

    func applicationWillFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)   // writing to a program that already exited must not crash the editor
        NSApp.mainMenu = MainMenu.build()
        windowController = WorkspaceWindowController()
        windowController.restoreSession()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController.showWindow(nil)
        NSApp.activate()
        Updater.shared.checkInBackgroundIfDue()
        #if DEBUG
        DevSnapshot.runIfRequested(windowController)
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { windowController.open($0) }
        windowController.showWindow(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard windowController.window?.isVisible == true else { return .terminateNow }
        return windowController.confirmCloseAll() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController.saveSession()
        windowController.stopAll()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Fills File ▸ Open Recent.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = menu.addItem(withTitle: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = url
            item.toolTip = url.path
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
        }
        if menu.items.isEmpty { menu.addItem(withTitle: "No Recent Items", action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { windowController.open(url) }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Updater.shared.check(userInitiated: true)
    }

    @objc func openProjectPage(_ sender: Any?) {
        if let repository = Updater.shared.repository, let url = URL(string: "https://github.com/\(repository)") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        main.addSubmenu("CodeForge") { menu in
            menu.add("About CodeForge", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            menu.add("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:)))
            menu.addItem(.separator())
            let services = NSMenu()
            menu.add("Services", nil).submenu = services
            NSApp.servicesMenu = services
            menu.addItem(.separator())
            menu.add("Hide CodeForge", #selector(NSApplication.hide(_:)), "h")
            menu.add("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            menu.add("Show All", #selector(NSApplication.unhideAllApplications(_:)))
            menu.addItem(.separator())
            menu.add("Quit CodeForge", #selector(NSApplication.terminate(_:)), "q")
        }

        main.addSubmenu("File") { menu in
            menu.add("New Project…", #selector(WorkspaceWindowController.newProject(_:)), "n", [.command, .shift])
            menu.add("New File", #selector(WorkspaceWindowController.newDocument(_:)), "n")
            menu.add("Open…", #selector(WorkspaceWindowController.openDocument(_:)), "o")
            menu.add("Clone Repository…", #selector(WorkspaceWindowController.cloneRepository(_:)))
            let recent = NSMenu(title: "Open Recent")
            recent.delegate = NSApp.delegate as? NSMenuDelegate
            menu.add("Open Recent", nil).submenu = recent
            menu.add("Quick Open…", #selector(WorkspaceWindowController.quickOpen(_:)), "p")
            menu.addItem(.separator())
            menu.add("Save", #selector(WorkspaceWindowController.saveDocument(_:)), "s")
            menu.add("Save As…", #selector(WorkspaceWindowController.saveDocumentAs(_:)), "s", [.command, .shift])
            menu.add("Save All", #selector(WorkspaceWindowController.saveAllDocuments(_:)), "s", [.command, .option])
            menu.addItem(.separator())
            menu.add("Close Tab", #selector(WorkspaceWindowController.closeTab(_:)), "w")
            menu.add("Close Folder", #selector(WorkspaceWindowController.closeFolder(_:)))
        }

        main.addSubmenu("Edit") { menu in
            menu.add("Undo", Selector(("undo:")), "z")
            menu.add("Redo", Selector(("redo:")), "z", [.command, .shift])
            menu.addItem(.separator())
            menu.add("Cut", #selector(NSText.cut(_:)), "x")
            menu.add("Copy", #selector(NSText.copy(_:)), "c")
            menu.add("Paste", #selector(NSText.paste(_:)), "v")
            menu.add("Select All", #selector(NSText.selectAll(_:)), "a")
            menu.addItem(.separator())
            let find = NSMenu(title: "Find")
            let finder = #selector(NSTextView.performTextFinderAction(_:))
            find.add("Find…", finder, "f").tag = NSTextFinder.Action.showFindInterface.rawValue
            find.add("Find and Replace…", finder, "f", [.command, .option]).tag = NSTextFinder.Action.showReplaceInterface.rawValue
            find.add("Find Next", finder, "g").tag = NSTextFinder.Action.nextMatch.rawValue
            find.add("Find Previous", finder, "g", [.command, .shift]).tag = NSTextFinder.Action.previousMatch.rawValue
            find.add("Use Selection for Find", finder, "e").tag = NSTextFinder.Action.setSearchString.rawValue
            menu.add("Find", nil).submenu = find
            menu.addItem(.separator())
            menu.add("Go to Line…", #selector(CodeTextView.goToLine(_:)), "l")
            menu.add("Toggle Comment", #selector(CodeTextView.toggleComment(_:)), "/")
            menu.add("Indent", #selector(CodeTextView.indentSelection(_:)), "]")
            menu.add("Outdent", #selector(CodeTextView.outdentSelection(_:)), "[")
        }

        main.addSubmenu("View") { menu in
            menu.add("Hide Explorer", #selector(WorkspaceWindowController.toggleExplorer(_:)), "b")
            menu.add("Move Explorer to Left", #selector(WorkspaceWindowController.toggleExplorerSide(_:)))
            menu.add("Hide Panel", #selector(WorkspaceWindowController.toggleConsole(_:)), "y", [.command, .shift])
            menu.add("Output", #selector(WorkspaceWindowController.showOutput(_:)), "u", [.command, .shift])
            menu.add("Error List", #selector(WorkspaceWindowController.showErrorList(_:)), "m", [.command, .shift])
            menu.add("Terminal", #selector(WorkspaceWindowController.showTerminal(_:)), "`", .control)
            menu.addItem(.separator())
            menu.add("Bigger", #selector(WorkspaceWindowController.increaseFontSize(_:)), "+")
            menu.add("Smaller", #selector(WorkspaceWindowController.decreaseFontSize(_:)), "-")
            menu.add("Actual Size", #selector(WorkspaceWindowController.resetFontSize(_:)), "0")
            menu.addItem(.separator())
            menu.add("Show Next Tab", #selector(WorkspaceWindowController.selectNextTab(_:)), "}")
            menu.add("Show Previous Tab", #selector(WorkspaceWindowController.selectPreviousTab(_:)), "{")
            menu.addItem(.separator())
            menu.add("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        }

        main.addSubmenu("Run") { menu in
            menu.add("Run", #selector(WorkspaceWindowController.runActiveFile(_:)), "r")
            menu.add("Stop", #selector(WorkspaceWindowController.stopRunning(_:)), ".")
            menu.addItem(.separator())
            menu.add("Set Run Command…", #selector(WorkspaceWindowController.editRunCommand(_:)), "r", [.command, .shift])
            menu.add("Send Input…", #selector(WorkspaceWindowController.focusConsoleInput(_:)), "i", [.command, .shift])
            menu.add("Clear Console", #selector(WorkspaceWindowController.clearConsole(_:)), "k")
        }

        main.addSubmenu("Window") { menu in
            menu.add("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            menu.add("Zoom", #selector(NSWindow.performZoom(_:)))
            NSApp.windowsMenu = menu
        }

        main.addSubmenu("Help") { menu in
            menu.add("CodeForge on GitHub", #selector(AppDelegate.openProjectPage(_:)))
            NSApp.helpMenu = menu
        }
        return main
    }
}

private extension NSMenu {
    func addSubmenu(_ title: String, _ build: (NSMenu) -> Void) {
        let menu = NSMenu(title: title)
        build(menu)
        addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
    }

    @discardableResult
    func add(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
