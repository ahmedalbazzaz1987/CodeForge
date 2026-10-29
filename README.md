# CodeForge

A small, fast, native IDE for macOS, inspired by Visual Studio: a Start page with project templates, a Solution
Explorer-style file tree, editor tabs, an **Output / Error List / Terminal** panel, and a green **Start** button that
runs your code. The whole app is about **1 MB**, has no third-party dependencies, and updates itself from GitHub
Releases.

![CodeForge in dark mode, showing an error from a Python program in the Error List](docs/screenshot.png)

- **Native and light.** Written in Swift with AppKit. It starts instantly and runs on Apple Silicon and Intel Macs
  with macOS 14 or later.
- **Visual Studio-style layout.** Light and dark themes, explorer on the right, docked bottom panel and a colored
  status bar (blue when ready, orange while running).
- **Start fast.** File ▸ New Project… creates a ready-to-run project for Python, C, C++, Swift, Node.js, TypeScript,
  web pages, Go, Rust or Java. You can also clone a Git repository straight from the Start page.
- **Many languages.** Syntax highlighting for Swift, Python, JavaScript, TypeScript, C, C++, Objective-C, Java, Kotlin,
  C#, Go, Rust, Ruby, PHP, Shell, Lua, SQL, HTML/XML, CSS, JSON, YAML, TOML, Markdown, Makefile and Dockerfile.
- **Run, then fix.** Press ⌘R to run. Output streams into the Output tab, and you can type input for programs that ask
  for it. Compiler and runtime errors appear in the **Error List**. Double-click one to jump to the line, which is
  underlined in the editor.
- **Built-in terminal.** Run `git`, `npm`, `pip` and other commands in the project folder.
- **Editor comforts.** Line numbers, current-line highlight, auto-indent, toggle comment, indent/outdent, find and
  replace, go to line and Quick Open (⌘P).
- **Self-updating.** CodeForge checks GitHub Releases once a day and can install a new version and relaunch.

## Install

1. Download `CodeForge-<version>.zip` from the [latest release](https://github.com/ahmedalbazzaz1987/CodeForge/releases/latest).
2. Unzip it and move **CodeForge.app** to your **Applications** folder.
3. The app isn't notarized by Apple yet, so macOS will block it the first time. Open **System Settings ▸ Privacy &
   Security**, scroll down, and click **Open Anyway** next to the CodeForge message. You only need to do this once;
   updates installed from inside the app don't ask again.

### Build from source

You need Xcode (or the Swift 6 toolchain).

```bash
git clone https://github.com/ahmedalbazzaz1987/CodeForge.git
cd CodeForge
scripts/build-app.sh
open dist/CodeForge.app
```

`swift test` runs the unit tests. To work on the code in Xcode, open `Package.swift`.

## Using CodeForge

| Action | Shortcut |
| --- | --- |
| New project | ⇧⌘N |
| Open a file or folder | ⌘O |
| Quick Open (find a file by name) | ⌘P |
| New file / Save / Save All | ⌘N / ⌘S / ⌥⌘S |
| Close tab / next and previous tab | ⌘W / ⇧⌘] and ⇧⌘[ |
| Run / Stop | ⌘R / ⌘. |
| Set the project's run command | ⇧⌘R |
| Show or hide the explorer / bottom panel | ⌘B / ⇧⌘Y |
| Output / Error List / Terminal | ⇧⌘U / ⇧⌘M / ⌃` |
| Find / Find and Replace | ⌘F / ⌥⌘F |
| Go to line | ⌘L |
| Toggle comment / indent / outdent | ⌘/ / ⌘] / ⌘[ |
| Bigger / smaller text | ⌘+ / ⌘- |

Right-click in the explorer to create, rename, reveal or trash files, or to open a Terminal in that folder. The
language menu in the status bar changes how the current file is highlighted and run.

### How files run

| Language | Command |
| --- | --- |
| Python | `python3 -u file.py` |
| JavaScript / TypeScript | `node file.js` / `npx tsx file.ts` |
| C / C++ / Objective-C | compiled with `clang` / `clang++`, then run |
| Swift | `swift file.swift` |
| Java / Kotlin / C# | `java File.java` / `kotlinc` + `java -jar` / `dotnet run file.cs` |
| Go / Rust | `go run file.go` / `rustc` then run |
| Ruby, PHP, Lua, Shell | `ruby`, `php`, `lua`, `zsh` |
| SQL | `sqlite3` (in memory) |
| HTML, Markdown | opened in your default app |

Commands run in a login shell, so tools installed with Homebrew, nvm or pyenv are found. If a tool is missing, the
console tells you how to install it. Compiled programs are built in `~/Library/Caches/<bundle id>/build`.

## Releasing an update

Version numbers live in `VERSION`, and release notes in `CHANGELOG.md`.

1. Bump `VERSION` (for example `0.1.0` → `0.2.0`) and add a `## 0.2.0` section to `CHANGELOG.md`.
2. Commit and push.
3. Run `scripts/release.sh`. It runs the tests, builds the app, zips it, writes a SHA-256 checksum, tags the commit
   and creates the GitHub release with both files.

Installed copies of CodeForge see the new release within a day, or right away with **CodeForge ▸ Check for
Updates…**. The updater only installs a download whose checksum matches, whose bundle identifier matches, and whose
code signature verifies.

To sign with an Apple Developer ID instead of the default ad-hoc signature, pass
`--sign "Developer ID Application: Your Name (TEAMID)"` to either script.

## Project layout

```
Sources/CodeForgeKit/   Languages, tokenizer, error parsing, project templates, run commands, versions (no UI; unit-tested)
Sources/CodeForge/      The AppKit app: window, editor, explorer, tabs, bottom panel, Start page, Quick Open, updater
Tests/                  Unit tests for CodeForgeKit
scripts/                build-app.sh, release.sh, make-icon.swift
```

Adding a language means adding one `Language(...)` entry in `Sources/CodeForgeKit/Languages.swift`, with its file
extensions, keywords, comment and string syntax, and run command.

## License

MIT. See [LICENSE](LICENSE).
