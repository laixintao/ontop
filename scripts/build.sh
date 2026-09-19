#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Release}"
ARCHITECTURE="${2:-native}"
usage() { echo "Usage: scripts/build.sh [Debug|Release] [native|universal|arm64|x86_64]" >&2; exit 1; }
[[ $# -le 2 ]] || usage
case "$CONFIGURATION" in
    Debug) SWIFT_FLAGS=(-Onone -g -D DEBUG) ;;
    Release) SWIFT_FLAGS=(-O) ;;
    *) usage ;;
esac

BUILD_DIR="$PROJECT_ROOT/build/$CONFIGURATION"
case "$ARCHITECTURE" in
    native) ARCHITECTURES=("$(uname -m)") ;;
    universal) ARCHITECTURES=(arm64 x86_64); BUILD_DIR+="-universal" ;;
    arm64|x86_64) ARCHITECTURES=("$ARCHITECTURE"); BUILD_DIR+="-$ARCHITECTURE" ;;
    *) usage ;;
esac
mkdir -p "$BUILD_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/OnTop.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$PROJECT_ROOT/build/ModuleCache"

SDK_PATH="$(xcrun --show-sdk-path)"
BINARIES=()
for arch in "${ARCHITECTURES[@]}"; do
    binary="$STAGING_DIR/OnTop-$arch"
    xcrun swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors \
        -target "$arch-apple-macosx14.0" -sdk "$SDK_PATH" \
        -module-cache-path "$PROJECT_ROOT/build/ModuleCache" \
        -module-name OnTop "${SWIFT_FLAGS[@]}" \
        "$PROJECT_ROOT"/OnTop/*.swift -o "$binary"
    BINARIES+=("$binary")
done
if [[ ${#BINARIES[@]} -eq 1 ]]; then
    cp "${BINARIES[0]}" "$APP_DIR/Contents/MacOS/OnTop"
else
    xcrun lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/OnTop"
fi

cp "$PROJECT_ROOT/OnTop/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$PROJECT_ROOT/OnTop/Resources/." "$APP_DIR/Contents/Resources/"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict --all-architectures "$APP_DIR"
# Replace only after compilation and signing succeed, without stale resources.
rm -rf "$BUILD_DIR/OnTop.app"
mv "$APP_DIR" "$BUILD_DIR/OnTop.app"
echo "Built: $BUILD_DIR/OnTop.app"
