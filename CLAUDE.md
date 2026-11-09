# Kryndev (formerly CodeForge) — notes for Claude

The product is called **Kryndev** (renamed from CodeForge in 0.13.0). Only user-visible text says Kryndev: the
repository, Swift targets, bundle ID (`io.github.ahmedalbazzaz1987.codeforge`), executable, Info.plist keys and settings
paths keep "CodeForge" so installed copies keep updating and keep their settings. Don't rename those.

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

## Windows version

The Windows version lives in its own repository, ahmedalbazzaz1987/CodeForge-Windows (C#, WPF, .NET 10), with its own
CLAUDE.md. New features usually go to both. .NET debugging uses netcoredbg on both: Microsoft's vsdbg is licensed only
for Microsoft's own tools, on Windows too.
