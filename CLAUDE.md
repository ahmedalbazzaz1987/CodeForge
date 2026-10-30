# CodeForge — notes for Claude

CodeForge is a small, self-updating IDE modeled on Visual Studio Professional. The owner keeps asking for updates that
bring it closer to VS Pro; the full history is in `CHANGELOG.md` and the features in `README.md`.

## Layout

- `Sources/CodeForgeKit/` — the engine, Foundation and SQLite only (no UI). Languages and the tokenizer, error parsing,
  project and item templates, build detection, LSP framing, Git parsing, symbol parsing (`Symbols.swift`), IntelliSense
  without a language server (`BasicIntelliSense.swift`, `DotNetCatalog.swift`), Extract Method (`Refactoring.swift`),
  Find in Files, snippets, color themes, databases. Unit-tested in `Tests/CodeForgeKitTests` (`swift test`).
- `Sources/CodeForge/` — the macOS app (AppKit, TextKit 1). `WorkspaceWindowController.swift` holds the window and
  wires everything together; `AppDelegate.swift` builds the menus in Visual Studio's order.
- `DevSnapshot.swift` (debug builds only) renders the window to a PNG for checking layouts and features without a
  screen: `CF_SNAPSHOT`, `CF_ACTION(S)`, `CF_SELECT`, `CF_TYPE`, `CF_ANSWER`, `CF_COMPLETE`, `CF_FIND`, `CF_TABLE`… (see the file).

## Conventions

- Swift 6 toolchain, Swift 5 language mode, no third-party dependencies (keep the app small: about 3.5 MB).
- Code reads like the surrounding code: short doc comments that say why, plain names.
- Logic goes in CodeForgeKit with a test whenever it doesn't need UI.

## Releasing

Bump `VERSION`, add a `## <version>` section to `CHANGELOG.md`, commit and push, then run `scripts/release.sh` (tests,
universal build, zip + SHA-256, tag, GitHub release). Installed copies update themselves from GitHub Releases. The
macOS release is built on a Mac.

## Windows version (planned)

The owner wants a Windows version, worked on from a Windows PC. Starting points:

- Reuse `CodeForgeKit` as is: it builds with Swift on Windows (Foundation + SQLite3). Check `swift build --target
  CodeForgeKit` and `swift test` there first; path handling (`/` vs `\`), shell commands (`/bin/zsh`, `open`) and
  tool paths (`/opt/homebrew/...`) in callers will need Windows equivalents.
- The UI must be rewritten: AppKit doesn't exist on Windows. One proven route is a Swift engine behind a small C API
  with a .NET (Avalonia or WinUI) Windows app on top, built in Windows CI with Swift 6.4 or later. On Windows, Visual Studio's own features (WinForms/WPF designers, .NET debugging with vsdbg) are
  available, unlike on the Mac.
- Keep the macOS app working; put Windows code in its own folder and target.
