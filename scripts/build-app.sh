#!/bin/bash
# Builds a release "CodeForge.app" in dist/.
# Usage: scripts/build-app.sh [--sign "Developer ID Application: Name (TEAMID)"] [--repo owner/name]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITY="-"   # ad-hoc signature by default
REPO="ahmedalbazzaz1987/CodeForge"   # GitHub repository the updater checks; pass --repo "" to turn updates off
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) IDENTITY="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 1 ;;
  esac
done
REPO_KEY=""
[[ -n "$REPO" ]] && REPO_KEY="<key>CodeForgeRepository</key><string>${REPO}</string>"

APP="dist/CodeForge.app"
echo "==> Compiling release build (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product CodeForge -Xswiftc -Osize
BIN="$(swift build -c release --arch arm64 --arch x86_64 -Xswiftc -Osize --show-bin-path)/CodeForge"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CodeForge"
strip -x "$APP/Contents/MacOS/CodeForge"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CodeForge</string>
  <key>CFBundleDisplayName</key><string>CodeForge</string>
  <key>CFBundleIdentifier</key><string>io.github.ahmedalbazzaz1987.codeforge</string>
  <key>CFBundleExecutable</key><string>CodeForge</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Ahmed Albazzaz. MIT License.</string>
  ${REPO_KEY}
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Source Code</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.source-code</string>
        <string>public.script</string>
        <string>public.plain-text</string>
        <string>public.json</string>
        <string>public.xml</string>
        <string>public.html</string>
        <string>public.yaml</string>
        <string>net.daringfireball.markdown</string>
        <string>public.folder</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> Signing (identity: $IDENTITY)"
TIMESTAMP="--timestamp=none"; [[ "$IDENTITY" != "-" ]] && TIMESTAMP="--timestamp"
codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

SIZE=$(du -sh "$APP" | cut -f1)
echo "==> Built $APP ($SIZE, version $VERSION build $BUILD)"
