# Changelog

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
