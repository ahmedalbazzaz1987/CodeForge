# Changelog

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
