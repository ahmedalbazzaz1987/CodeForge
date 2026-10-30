import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windowController: WorkspaceWindowController!

    func applicationWillFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)   // writing to a program that already exited must not crash the editor
        NSApp.mainMenu = MainMenu.build()
        windowController = WorkspaceWindowController()
        OptionsWindow.applyAppearance()
        if UserDefaults.standard.object(forKey: "restoreSession") as? Bool ?? true { windowController.restoreSession() }
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
    static func functionKey(_ key: Int) -> String { String(Character(UnicodeScalar(UInt16(key))!)) }

    static func build() -> NSMenu {
        let main = NSMenu()

        main.addSubmenu("CodeForge") { menu in
            menu.add("About CodeForge", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            menu.add("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:)))
            menu.addItem(.separator())
            menu.add("Settings…", #selector(WorkspaceWindowController.showOptions(_:)), ",")
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
            find.addItem(.separator())
            find.add("Find in Files…", #selector(WorkspaceWindowController.findInFiles(_:)), "f", [.command, .shift])
            find.add("Replace in Files…", #selector(WorkspaceWindowController.replaceInFiles(_:)), "h", [.command, .shift])
            menu.add("Find and Replace", nil).submenu = find
            menu.addItem(.separator())
            menu.add("Go to Line…", #selector(CodeTextView.goToLine(_:)), "l")
            menu.addItem(.separator())
            menu.add("Show Completions", #selector(CodeTextView.showCompletions(_:)), " ", .control)
            menu.add("Go to Definition", #selector(WorkspaceWindowController.goToDefinition(_:)), MainMenu.functionKey(NSF12FunctionKey), [])
            menu.add("Find All References", #selector(WorkspaceWindowController.findAllReferences(_:)), MainMenu.functionKey(NSF12FunctionKey), .shift)
            let refactor = NSMenu(title: "Refactor")
            refactor.add("Quick Actions and Refactorings…", #selector(WorkspaceWindowController.showQuickActions(_:)), "\r", .option)
            refactor.addItem(.separator())
            refactor.add("Rename…", #selector(WorkspaceWindowController.renameSymbol(_:)), MainMenu.functionKey(NSF2FunctionKey), [])
            refactor.add("Extract Method…", #selector(WorkspaceWindowController.extractMethod(_:)), "m", [.command, .option])
            menu.add("Refactor", nil).submenu = refactor
            menu.add("Insert Snippet…", #selector(WorkspaceWindowController.showSnippetsManager(_:)))
            menu.addItem(.separator())
            menu.add("Toggle Comment", #selector(CodeTextView.toggleComment(_:)), "/")
            menu.add("Indent", #selector(CodeTextView.indentSelection(_:)), "]")
            menu.add("Outdent", #selector(CodeTextView.outdentSelection(_:)), "[")
        }

        main.addSubmenu("View") { menu in
            menu.add("Hide Explorer", #selector(WorkspaceWindowController.toggleExplorer(_:)), "b")
            menu.add("Move Explorer to Left", #selector(WorkspaceWindowController.toggleExplorerSide(_:)))
            menu.add("Hide Toolbox", #selector(WorkspaceWindowController.toggleToolbox(_:)), "x", [.command, .option])
            menu.add("Server Explorer", #selector(WorkspaceWindowController.showServerExplorer(_:)), "s", [.command, .control])
            menu.add("Class View", #selector(WorkspaceWindowController.showClassView(_:)), "c", [.command, .shift])
            menu.add("Object Browser", #selector(WorkspaceWindowController.showObjectBrowser(_:)), "j", [.command, .option])
            menu.add("Hide Properties Window", #selector(WorkspaceWindowController.toggleProperties(_:)), MainMenu.functionKey(NSF4FunctionKey), [])
            menu.add("Hide Panel", #selector(WorkspaceWindowController.toggleConsole(_:)), "y", [.command, .shift])
            menu.add("Output", #selector(WorkspaceWindowController.showOutput(_:)), "u", [.command, .shift])
            menu.add("Error List", #selector(WorkspaceWindowController.showErrorList(_:)), "m", [.command, .shift])
            menu.add("Find Results", #selector(WorkspaceWindowController.showFindResults(_:)))
            menu.add("Query Results", #selector(WorkspaceWindowController.showQueryResults(_:)))
            menu.add("Terminal", #selector(WorkspaceWindowController.showTerminal(_:)), "`", .control)
            menu.add("Show CodeLens", #selector(WorkspaceWindowController.toggleCodeLens(_:)))
            let toolbars = NSMenu(title: "Toolbars")
            toolbars.add("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option])
            toolbars.add("Customize…", #selector(WorkspaceWindowController.customizeToolbar(_:)))
            menu.add("Toolbars", nil).submenu = toolbars
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

        main.addSubmenu("Git") { menu in
            menu.add("Git Changes", #selector(WorkspaceWindowController.showGitChanges(_:)), "g", [.command, .option])
            menu.add("View History", #selector(WorkspaceWindowController.showGitHistory(_:)))
            menu.addItem(.separator())
            menu.add("Clone Repository…", #selector(WorkspaceWindowController.cloneRepository(_:)))
        }

        main.addSubmenu("Project") { menu in
            menu.add("Add New Item…", #selector(WorkspaceWindowController.addNewItem(_:)), "a", [.command, .shift])
            menu.add("Add Existing Item…", #selector(WorkspaceWindowController.addExistingItem(_:)), "a", [.command, .option, .shift])
            menu.addItem(.separator())
            menu.add("Manage NuGet Packages…", #selector(WorkspaceWindowController.manageNuGetPackages(_:)))
            menu.add("Project Properties", #selector(WorkspaceWindowController.openProjectFile(_:)))
        }

        main.addSubmenu("Build") { menu in
            menu.add("Build", #selector(WorkspaceWindowController.buildProject(_:)), "b", [.command, .shift])
            menu.add("Clean", #selector(WorkspaceWindowController.cleanProject(_:)), "k", [.command, .shift])
            menu.addItem(.separator())
            menu.add("Set Build Command…", #selector(WorkspaceWindowController.editBuildCommand(_:)))
        }

        main.addSubmenu("Debug") { menu in
            let f = MainMenu.functionKey
            menu.add("Start Debugging", #selector(WorkspaceWindowController.startDebugging(_:)), f(NSF5FunctionKey), [])
            menu.add("Start Without Debugging", #selector(WorkspaceWindowController.runActiveFile(_:)), "r")
            menu.add("Stop Debugging", #selector(WorkspaceWindowController.stopDebugging(_:)), f(NSF5FunctionKey), .shift)
            menu.add("Stop Running", #selector(WorkspaceWindowController.stopRunning(_:)), ".")
            menu.addItem(.separator())
            menu.add("Step Over", #selector(WorkspaceWindowController.debugStepOver(_:)), f(NSF10FunctionKey), [])
            menu.add("Step Into", #selector(WorkspaceWindowController.debugStepInto(_:)), f(NSF11FunctionKey), [])
            menu.add("Step Out", #selector(WorkspaceWindowController.debugStepOut(_:)), f(NSF11FunctionKey), .shift)
            menu.add("Pause", #selector(WorkspaceWindowController.debugPause(_:)))
            menu.addItem(.separator())
            menu.add("Toggle Breakpoint", #selector(WorkspaceWindowController.toggleBreakpointAtCursor(_:)), f(NSF9FunctionKey), [])
            menu.add("Delete All Breakpoints", #selector(WorkspaceWindowController.deleteAllBreakpoints(_:)), f(NSF9FunctionKey), [.command, .shift])
            menu.addItem(.separator())
            menu.add("Set Run Command…", #selector(WorkspaceWindowController.editRunCommand(_:)), "r", [.command, .shift])
            menu.add("Set Program to Debug…", #selector(WorkspaceWindowController.setDebugProgram(_:)))
            menu.add("Send Input…", #selector(WorkspaceWindowController.focusConsoleInput(_:)), "i", [.command, .shift])
            menu.add("Clear Console", #selector(WorkspaceWindowController.clearConsole(_:)), "k")
        }

        main.addSubmenu("Test") { menu in
            menu.add("Run All Tests", #selector(WorkspaceWindowController.runAllTests(_:)), "u")
        }

        main.addSubmenu("Tools") { menu in
            menu.add("Connect to Database…", #selector(WorkspaceWindowController.connectToDatabase(_:)))
            menu.add("Execute Query", #selector(WorkspaceWindowController.executeQuery(_:)), "e", [.command, .shift])
            menu.addItem(.separator())
            menu.add("Code Snippets Manager…", #selector(WorkspaceWindowController.showSnippetsManager(_:)), "b", [.command, .control])
            menu.add("Terminal", #selector(WorkspaceWindowController.showTerminal(_:)))
            menu.add("Manage NuGet Packages…", #selector(WorkspaceWindowController.manageNuGetPackages(_:)))
            menu.addItem(.separator())
            menu.add("Customize Toolbar…", #selector(WorkspaceWindowController.customizeToolbar(_:)))
            menu.add("Options…", #selector(WorkspaceWindowController.showOptions(_:)))
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
