#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
[[ $# -eq 0 ]] || { echo "Usage: scripts/ci.sh" >&2; exit 1; }
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint OnTop/Info.plist OnTop.xcodeproj/project.pbxproj OnTop/Resources/*.lproj/Localizable.strings

# Reject a mismatched release tag before spending time building artifacts.
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' OnTop/Info.plist)"
    [[ "${GITHUB_REF_NAME:-}" == "v$version" ]] || {
        echo "Release tag must match Info.plist version: v$version" >&2
        exit 1
    }
fi

./scripts/test.sh
./scripts/package.sh
./scripts/test-package.sh
echo "PASS: CI"
