#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
[[ $# -eq 0 ]] || { echo "Usage: scripts/tag-release.sh" >&2; exit 1; }
VERSION="$(python3 -c 'import plistlib; print(plistlib.load(open("OnTop/Info.plist", "rb"))["CFBundleShortVersionString"])')"
TAG="v$VERSION"
python3 scripts/check-project.py --release-tag "$TAG"
[[ -z "$(git status --porcelain)" ]] || { echo "Commit all changes before tagging a release." >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main." >&2; exit 1; }
REMOTE_HEAD="$(git ls-remote origin refs/heads/main | cut -f1)"
[[ "$(git rev-parse HEAD)" == "$REMOTE_HEAD" ]] || { echo "Push main before tagging a release." >&2; exit 1; }
if git show-ref --verify --quiet "refs/tags/$TAG"; then
    echo "$TAG already exists locally. If its push failed, retry: git push origin $TAG" >&2
    exit 1
fi
if [[ -n "$(git ls-remote origin "refs/tags/$TAG")" ]]; then
    echo "$TAG already exists on origin. Choose a new version." >&2
    exit 1
fi
git tag -a "$TAG" -m "OnTop $VERSION"
git push origin "refs/tags/$TAG"
echo "Release workflow started for $TAG."
