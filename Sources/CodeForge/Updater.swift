import AppKit
import CodeForgeKit
import CryptoKit

/// Updates CodeForge from the project's GitHub Releases.
///
/// A release is installable when it has a `CodeForge-<version>.zip` asset and a matching `.zip.sha256` asset
/// (`scripts/release.sh` publishes both). The download must match the checksum, contain an app with the same bundle
/// identifier and pass `codesign --verify` before it replaces the running copy.
final class Updater {
    static let shared = Updater()
    /// "owner/repo", from Info.plist. Updates are off when it is missing.
    let repository = Bundle.main.object(forInfoDictionaryKey: "CodeForgeRepository") as? String
    private var isBusy = false
    private let lastCheckKey = "lastUpdateCheck"

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Checks at most once a day, and stays quiet unless an update exists.
    func checkInBackgroundIfDue() {
        guard repository != nil, Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: lastCheckKey) > 86_400 else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard let repository else {
            if userInitiated { Prompt.show("Updates aren't set up for this build", message: "It was built without a GitHub repository.", style: .informational) }
            return
        }
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                let release = try await latestRelease(repository)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
                if let release, let latest = Version(release.tag_name), let installed = Version(currentVersion), latest > installed {
                    await offer(release, version: latest)
                } else if userInitiated {
                    Prompt.show("You're up to date", message: "CodeForge \(currentVersion) is the newest version.", style: .informational)
                }
            } catch {
                if userInitiated { Prompt.show("Couldn't check for updates", message: error.localizedDescription) }
            }
        }
    }

    private func latestRelease(_ repository: String) async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }   // no releases yet
        guard status == 200 else { throw UpdateError("GitHub answered with status \(status).") }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    @MainActor
    private func offer(_ release: Release, version: Version) async {
        let alert = NSAlert()
        alert.messageText = "CodeForge \(version) is available"
        var notes = HoverText.plain(release.body ?? "")
        if notes.count > 900 { notes = String(notes.prefix(900)) + "…" }
        alert.informativeText = "You have version \(currentVersion)." + (notes.isEmpty ? "" : "\n\n" + notes)
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: await install(release)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.html_url)
        default: break
        }
    }

    @MainActor
    private func install(_ release: Release) async {
        guard let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let checksum = release.assets.first(where: { $0.name == zip.name + ".sha256" }) else {
            Prompt.show("This release can't be installed automatically", message: "Download it from the release page instead.")
            NSWorkspace.shared.open(release.html_url)
            return
        }
        let progress = ProgressPanel("Downloading \(zip.name)…")
        defer { progress.close() }
        do {
            let installed = Bundle.main.bundleURL
            if installed.path.contains("/AppTranslocation/") {
                throw UpdateError("Move CodeForge to your Applications folder, open it from there, and try again.")
            }
            guard FileManager.default.isWritableFile(atPath: installed.deletingLastPathComponent().path) else {
                throw UpdateError("CodeForge can't replace itself in “\(installed.deletingLastPathComponent().path)”.")
            }
            let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true)
            defer { try? FileManager.default.removeItem(at: work) }

            let (downloaded, _) = try await URLSession.shared.download(from: zip.browser_download_url)
            let archive = work.appendingPathComponent(zip.name)
            try FileManager.default.moveItem(at: downloaded, to: archive)
            let (sumData, _) = try await URLSession.shared.data(from: checksum.browser_download_url)
            let expected = String(decoding: sumData, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() }
            let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
            guard expected == actual else { throw UpdateError("The download didn't match its checksum, so it wasn't installed.") }

            progress.setMessage("Installing…")
            let unpacked = work.appendingPathComponent("unpacked")
            try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
            guard let app = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
                  Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError("The download doesn't contain CodeForge.")
            }
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            _ = try FileManager.default.replaceItemAt(installed, withItemAt: app)
            relaunch(installed)
        } catch {
            Prompt.show("The update couldn't be installed", message: error.localizedDescription)
        }
    }

    /// Opens the new copy once this process has exited.
    private func relaunch(_ app: URL) {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                            "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        try? waiter.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) failed with exit code \(process.terminationStatus).")
        }
    }
}

/// A small floating window with a spinner.
private final class ProgressPanel {
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 70), styleMask: [.titled], backing: .buffered, defer: false)
    private let label = NSTextField(labelWithString: "")

    init(_ message: String) {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        label.stringValue = message
        label.lineBreakMode = .byTruncatingMiddle
        let row = NSStackView(views: [spinner, label])
        row.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        panel.contentView = row
        panel.title = "Updating CodeForge"
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func setMessage(_ message: String) { label.stringValue = message }
    func close() { panel.close() }
}
