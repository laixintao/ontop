#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -eq 0 ]] || { echo "Usage: scripts/package.sh" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/OnTop/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid app version: $VERSION" >&2; exit 1; }
NAME="OnTop-$VERSION-universal"

"$PROJECT_ROOT/scripts/build.sh" Release universal
mkdir -p "$PROJECT_ROOT/dist"
STAGING_DIR="$(mktemp -d "$PROJECT_ROOT/dist/.package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$PROJECT_ROOT/build/Release-universal/OnTop.app" "$STAGING_DIR/OnTop.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/OnTop.app" "$STAGING_DIR/$NAME.zip"

mkdir "$STAGING_DIR/image"
ditto "$STAGING_DIR/OnTop.app" "$STAGING_DIR/image/OnTop.app"
ln -s /Applications "$STAGING_DIR/image/Applications"
hdiutil create -quiet -volname OnTop -srcfolder "$STAGING_DIR/image" \
    -format UDZO -fs HFS+ "$STAGING_DIR/$NAME.dmg"
hdiutil verify -quiet "$STAGING_DIR/$NAME.dmg"
(
    cd "$STAGING_DIR"
    shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS
)

# A failed build/package leaves the last successful distribution intact.
# Only remove files owned by this script, never the whole dist directory.
rm -rf "$PROJECT_ROOT/dist/OnTop.app"
rm -f "$PROJECT_ROOT"/dist/OnTop-*-universal.dmg "$PROJECT_ROOT"/dist/OnTop-*-universal.zip
for artifact in OnTop.app "$NAME.dmg" "$NAME.zip" SHA256SUMS; do
    mv "$STAGING_DIR/$artifact" "$PROJECT_ROOT/dist/$artifact"
done
echo "Packaged: $PROJECT_ROOT/dist/$NAME.dmg"
echo "Packaged: $PROJECT_ROOT/dist/$NAME.zip"
