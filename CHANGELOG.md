# Changelog

## 0.11.1

Fixes from a full test of the Mac version.

**Running programs**
- Programs now run on a real terminal (a pseudo-terminal). Output that was lost when a program crashed now appears, and
  stdout and stderr come in the order they were written. A crash says so: "The program crashed: Segmentation fault".
- Output colors go by the content: errors red, warnings yellow, and no more red "Build complete!".
- Progress that rewrites its line (like git's percentages) keeps only the last version, and SwiftPM's step counter is hidden.
- The Stop button says "Stopped" instead of reporting a failure.
- The Input row under Output is taller, and clicking anywhere in it works. Start puts the cursor there, and it returns to
  the code when the program ends.
- If a language's tools aren't installed (Java, Go, Rust…), New Project and Start say what to install, instead of failing
  with an unclear message. Java is checked properly, because macOS always has a /usr/bin/java that does nothing by itself.

**Error List and IntelliSense**
- An error reported by both the build and the language server is listed once.
- C and C++ files no longer show false errors from a missing language standard: clangd is told C17 or C++20 unless the
  project has its own settings, and new C and C++ projects include `compile_flags.txt`.
- TypeScript runs now list type errors in the Error List, and the program still runs.

**Projects and windows**
- Opening another project closes the old project's tabs, errors, output, Find Results and Task List, like closing a solution
  in Visual Studio. It asks about unsaved files first. Closing a tab removes its errors from the list.
- Properties shows the new size and date after a save.
- In a small window the editor keeps its room: the side panes and the bottom panel give way, and panel tabs that don't
  fit move to a » menu. The Debug panel's columns fit the panel, so Value stays visible.
- The output no longer wraps too early when the panel was hidden at first.
- New Project closes its sheet before the project opens, and Xcode's tools are looked up in the background at launch, so
  the first C, C++ or Swift project shouldn't freeze the window.

**Toolbox and snippets**
- Snippets for C, C++, Java, Go and Rust, and a TypeScript group of its own.

## 0.11.0

A modern look, and more of Visual Studio's everyday tools. By Ahmed Al-Bazzaz.

- **New color themes** in Tools ▸ Options: **Modern Light** and **Modern Dark** (the new defaults, with calm neutrals, an
  indigo accent and softer syntax colors), **Gray** (a second dark option in neutral graphite with a teal accent) and
  **Midnight** (deep navy). Visual Studio's own colors are still there as **Visual Studio Light** and **Visual Studio Dark**.
- **Task List** (⌥⌘T): every TODO, FIXME, HACK, UNDONE, BUG and XXX comment in the project. Only real comments count,
  not the same words in code or strings. Double-click to go there.
- **Bookmarks** (Edit ▸ Bookmarks): Toggle (⌃⌘K), Next (⌃⌘N), Previous (⌃⌘P) and Clear All. A bar in the margin marks each
  one; they stay on their code as you edit, and are remembered between launches.
- **Breakpoints follow their code** too when lines are added or removed above them.
- **Navigate Backward and Forward** (⌃- and ⌃⇧-, with toolbar buttons), like a browser's history, after Go to Definition,
  search results, bookmarks and switching tabs.
- The app, its About panel, the Start Page and the license now credit **Ahmed Al-Bazzaz**.

## 0.10.0

Closer to Visual Studio Professional: refactoring, Find in Files, Class View, Object Browser, Server Explorer, code
snippets, color themes, VB.NET IntelliSense, more .NET templates and .NET debugging.

- **.NET debugging** (F5) for C#, VB.NET, F# and ASP.NET Core: breakpoints, stepping, Locals, Call Stack and Evaluate.
  It uses netcoredbg, Samsung's open-source .NET debugger, which CodeForge offers to download the first time.
- **VB.NET IntelliSense** without a language server: member lists after `.` for your own classes and common .NET classes
  (`Console.`, `List(Of T).`, `String`, `DateTime`, `File`, LINQ…), keywords, locals, hover info, Go to Definition (F12),
  Find All References (⇧F12) and Rename (F2). Other languages without a server get keyword, symbol and word completion.
- **Find in Files / Replace in Files** (⇧⌘F / ⇧⌘H): the whole project, the current folder or the open documents; match
  case, whole word, regular expressions and file types. Results go to a new **Find Results** tab with the matches
  highlighted; Replace All in open files can be undone.
- **Refactoring.** Edit ▸ Refactor ▸ **Quick Actions and Refactorings** (⌥↩) shows the language server's fixes and
  refactorings; **Extract Method** (⌥⌘M) uses the server's when it has one, and CodeForge's own for VB.NET, C#, Python,
  JavaScript, TypeScript and Swift (parameters and the return value are worked out for you).
- **Class View** (⇧⌘C), a new tab next to Solution Explorer and Git: namespaces, classes, modules and their members, with
  search. **Object Browser** (⌥⌘J): your project's types and about 45 common .NET classes with their members.
- **Server Explorer** (⌃⌘S), a tab next to the Toolbox: connect to SQLite files, PostgreSQL, MySQL/MariaDB or SQL Server;
  browse tables, views and columns; double-click a table to see its data. **Tools ▸ Execute Query** (⇧⌘E) runs a SQL tab
  and shows the rows in a new **Query Results** tab.
- **Code snippets**: type a shortcut (`prop`, `ctor`, `foreach`, `cw`, `Sub`, `For`, `Try`…) and press Tab. **Tools ▸ Code
  Snippets Manager** (⌃⌘B) adds, changes and deletes snippets for each language; they also appear in IntelliSense and in a
  Code Snippets group in the Toolbox.
- **Color themes** in Tools ▸ Options: Light, Dark, Blue, High Contrast, Monokai, Dracula, Solarized Dark and Solarized Light.
- **Customizable toolbar** (View ▸ Toolbars ▸ Customize…, or right-click the toolbar) with new buttons: Build, Run All
  Tests, Find in Files, Quick Actions, Comment/Uncomment, Add New Item, Git Changes, Toolbox, Server Explorer, Class View
  and Object Browser.
- **New Project templates**: ASP.NET Core Empty, gRPC Service, Worker Service, Blazor WebAssembly, Razor Class Library,
  .NET MAUI (runs on this Mac with Mac Catalyst), Avalonia desktop apps with XAML (like WPF, and they run on a Mac),
  xUnit (C# and VB.NET), MSTest and NUnit test projects, and an F# console app.

## 0.9.0

Visual Studio-style menus and tools.

- Menus in Visual Studio's order: File, Edit, View, Git, **Project**, Build, Debug, **Test**, **Tools**, Window, Help.
- **Project ▸ Add New Item…** (⇧⌘A): C# and VB.NET classes, interfaces and modules, Razor pages and components, HTML, CSS, JavaScript, TypeScript, JSON, Swift, Python, C/C++ and text files. It starts on a template that matches the file you're editing. **Add Existing Item…** copies files into the project.
- **Project ▸ Manage NuGet Packages…** adds a package (with an optional version) to a .NET project and lists its packages; **Project Properties** opens the project file.
- **Debug / Release** configuration box in the toolbar, used by Build and Start (`dotnet -c Release`, `swift -c release`, `cargo --release`, CMake and Xcode builds).
- **Test ▸ Run All Tests** (⌘U) runs `dotnet test`, `swift test`, `cargo test`, `go test`, `npm test`, pytest/unittest or `make test`.
- **Tools ▸ Options…** (also CodeForge ▸ Settings, ⌘,): color theme (system, light, dark), Solution Explorer side, font size, CodeLens, automatic update checks and reopening the last session.

## 0.8.2

- Design view: stray clicks that land on the page root (`<html>`) no longer replace the selected element in the Properties window.

## 0.8.1

- Properties window: changes always apply to the element it shows, even if the cursor moved in the meantime.
- The design view no longer selects elements on keyboard presses (Return or Space), only on mouse clicks.

## 0.8.0

The Toolbox, a web designer and the Properties window, arranged like Visual Studio.

- **Toolbox** (left, ⌥⌘X): controls and snippets for the current file. HTML controls (Button, Text Box, Check Box, Drop-Down List, Table, Form…), Bootstrap components, ASP.NET Tag Helpers for Razor pages, C# and VB.NET code snippets, SwiftUI controls, and Python, JavaScript and CSS snippets. Double-click an item to insert it at the cursor, or drag it into the editor. Search to filter.
- **Design / Split / Source** views for HTML pages (tabs under the editor). The design surface shows the page live as you type; click an element there to select its tag in the source.
- **Properties window** (under Solution Explorer, F4): the attributes of the HTML or Razor element at the cursor, editable in place, with + and − to add or remove attributes. For other files it shows the file's details.

## 0.7.0

.NET: VB.NET, C# and ASP.NET Core.

- **New Project** has .NET templates: ASP.NET Core Web App (Razor Pages), ASP.NET Core MVC, ASP.NET Core Web API, Blazor Web App, Console App and Class Library in **VB.NET** and **C#**. They're created with `dotnet new` (needs the .NET SDK: `brew install dotnet`).
- Syntax highlighting for **VB.NET**, **Razor** (`.cshtml`, `.razor`) and **F#**; project files (`.csproj`, `.vbproj`, `.slnx`, `.xaml`) are highlighted as XML.
- **Start** runs the whole project, like Visual Studio's startup project: `dotnet run` for .NET, and also `swift run`, `cargo run`, `go run .` and `npm start` for those project types. The Start button shows the project's name.
- ASP.NET sites open in your browser as soon as the server is ready.
- **Build** detects solutions and projects (`.sln`, `.slnx`, `.csproj`, `.vbproj`, `.fsproj`) and puts MSBuild errors (C#, VB.NET) in the Error List.
- **C# IntelliSense** with csharp-ls, installed with one click from the status bar.

## 0.6.1

- Python debugging no longer prints debugpy's internal "ptvsd" / "debugpy" messages in the Output.
- Pressing the line-number margin with VoiceOver or other accessibility tools toggles a breakpoint, instead of opening a tab-stop dialog.

## 0.6.0

- **Python debugging**: breakpoints, Step Over / Into / Out, Locals (expand objects, lists and dicts), Call Stack and Evaluate, using debugpy. The first time you debug Python, CodeForge offers to install debugpy (about 18 MB) into its own folder.
- Update notes in the "new version available" window no longer show Markdown symbols.

## 0.5.1

- Debug tab: an **Evaluate** button next to the expression field, and results show just the value (`= 30`).
- Undoing all edits back to the saved text now clears the unsaved mark on the tab.

## 0.5.0

Git and CodeLens.

- **Git Changes** next to the Explorer: see changed files (staged and unstaged), stage or unstage each one, write a message and commit, switch or create branches, and Fetch, Pull and Push. Double-click a file to see its changes as a highlighted diff; right-click to undo changes.
- **View History** shows the branch's commit log in a tab. Folders that aren't repositories offer **Create Git Repository**.
- The status bar shows the current branch, commits ahead/behind, and the number of changed files. Click it to open Git Changes.
- **CodeLens** after each function, method and type: how many references it has and who last changed it (from git blame), for example "2 references | Ahmed, 3 days ago". Turn it off in View ▸ Show CodeLens.
- Diff files (`.diff`, `.patch`) are highlighted.

## 0.4.0

Build and debug.

- **Build** (⇧⌘B) detects the project type: Swift packages, Cargo, Go modules, CMake, Xcode projects, Make, npm and TypeScript. Single C, C++, Objective-C, Swift, Rust and Go files are compiled with debug information. **Clean** and a per-project **Set Build Command…** are in the Build menu.
- **Debugger** using LLDB (Xcode's `lldb-dap`) for C, C++, Objective-C, Swift, Rust and Go programs: Start Debugging (F5), breakpoints (click the line-number margin or press F9), Continue, Step Over (F10), Step Into (F11), Step Out (⇧F11), Pause and Stop (⇧F5).
- **Debug tab** with Locals (expand structs and arrays), Call Stack (click a frame to go there) and an expression evaluator. The paused line is highlighted with a yellow arrow.
- Debug toolbar above the editor while debugging; the status bar turns orange.
- Breakpoints are remembered between launches.
- Tool output no longer shows terminal color codes, and an error reported by both the build and IntelliSense is listed once.

## 0.3.0

IntelliSense, powered by standard language servers.

- **Completions** as you type (and with ⌃Space or Esc), with kind icons and type details.
- **Quick info** when you rest the mouse on a symbol, including the error or warning under it.
- **Go to Definition** (F12 or ⌘-click), **Find All References** (⇧F12, results in the new References tab) and **Rename** (F2) across files.
- **Live errors and warnings** while you type: exact squiggles in the editor and entries in the Error List, before you run anything.
- Works out of the box for Swift (SourceKit-LSP) and C, C++ and Objective-C (clangd), using Xcode's tools.
- Python (Pyright) and JavaScript/TypeScript (TypeScript 7) are one click away: the status bar offers to install them into CodeForge's own folder. Go (gopls) and Rust (rust-analyzer) are used when installed.

## 0.2.0

A Visual Studio-style look and layout.

- New Visual Studio-style light and dark color themes for the editor and window.
- Explorer docked on the right like Solution Explorer (View ▸ Move Explorer to Left to change it).
- Bottom panel with three tabs: **Output**, **Error List** and **Terminal**.
- Error List: errors and warnings from compilers and runtimes (clang, Swift, Go, Rust, TypeScript, Python, Node.js, Java, Ruby) appear in a list. Double-click one to jump to the line, which is underlined in the editor.
- Terminal: run shell commands in the project folder, with history (↑/↓) and Ctrl-C.
- Start page with recent projects and Get started actions.
- File ▸ New Project… with templates for Python, C, C++, Swift, Node.js, TypeScript, web pages, Go, Rust, Java and an empty project.
- File ▸ Clone Repository… clones a Git repository and opens it.
- Toolbar with New Project, Open, Save All, a green Start button that shows what will run, and Stop.
- Status bar colored like Visual Studio: blue when ready, orange while running, purple with no folder open.

## 0.1.0

First release.

- Native macOS editor (about 1 MB) with a file explorer, tabs, line numbers and current-line highlight.
- Syntax highlighting for 25 languages and file types, in light and dark mode.
- Run the current file with ⌘R, or set a run command for the whole project; output and input in the console.
- Auto-indent, toggle comment, indent/outdent, find and replace, go to line, Quick Open (⌘P).
- Reopens your last folder and files on launch.
- Updates itself from GitHub Releases (checks once a day, or with Check for Updates…).
