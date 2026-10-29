// swift-tools-version: 6.0
// CodeForge — a small, native code editor for macOS.
// Build the app with `scripts/build-app.sh`, or open this file in Xcode to work on it.
import PackageDescription

let package = Package(
    name: "CodeForge",
    platforms: [.macOS(.v14)],
    targets: [
        // Platform-independent logic: languages, tokenizer, command templates, versions, fuzzy matching.
        .target(
            name: "CodeForgeKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The AppKit application. No third-party dependencies, to keep the app small.
        .executableTarget(
            name: "CodeForge",
            dependencies: ["CodeForgeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CodeForgeKitTests",
            dependencies: ["CodeForgeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
