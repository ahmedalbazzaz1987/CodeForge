# Changelog

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
