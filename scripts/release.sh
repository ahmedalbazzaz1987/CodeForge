#!/bin/bash
# Publishes the version in VERSION as a GitHub release that the in-app updater can install.
#   1. Bump VERSION and add a "## <version>" section to CHANGELOG.md.
#   2. Commit and push.
#   3. Run scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
ZIP="dist/CodeForge-$VERSION.zip"

if [[ -n "$(git status --porcelain)" ]]; then echo "Commit your changes first."; exit 1; fi
if git rev-parse "$TAG" >/dev/null 2>&1; then echo "$TAG already exists. Bump VERSION first."; exit 1; fi

swift test
scripts/build-app.sh "$@"

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent dist/CodeForge.app "$ZIP"
(cd dist && shasum -a 256 "CodeForge-$VERSION.zip" > "CodeForge-$VERSION.zip.sha256")

# Release notes: this version's CHANGELOG section.
NOTES="$(awk -v v="## $VERSION" '$0 == v {found=1; next} /^## / && found {exit} found' CHANGELOG.md)"
[[ -z "$NOTES" ]] && NOTES="CodeForge $VERSION"

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" "$ZIP.sha256" --title "CodeForge $VERSION" --notes "$NOTES"
echo "==> Released $TAG"
