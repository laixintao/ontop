#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
./scripts/build.sh Debug
TEST_APP="$PROJECT_ROOT/build/Tests/OnTopTests.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources" build/qa
rm -f build/qa/*.png
cp OnTop/Info.plist "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.ontop.OnTopTests' "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable OnTopSmokeTests' "$TEST_APP/Contents/Info.plist"
cp -R OnTop/Resources/. "$TEST_APP/Contents/Resources/"

xcrun swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" \
    -sdk "$(xcrun --show-sdk-path)" \
    -module-cache-path build/ModuleCache \
    OnTop/CaptureController.swift OnTop/PinManager.swift OnTop/PreviewPanelController.swift OnTop/FrameRenderer.swift Tests/SmokeTests.swift \
    -o "$TEST_APP/Contents/MacOS/OnTopSmokeTests"

codesign --force --sign - "$TEST_APP"
"$TEST_APP/Contents/MacOS/OnTopSmokeTests" -AppleLanguages '(en)'
"$TEST_APP/Contents/MacOS/OnTopSmokeTests" -AppleLanguages '(zh-Hans)'
