#!/usr/bin/env bash
# Builds a release DMG and (optionally) publishes it as a GitHub release.
#   scripts/release.sh 2.1.0              # test, build, package → build/LoFiHUD_v2.1.0.dmg
#   scripts/release.sh 2.1.0 --publish    # …then tag v2.1.0 and upload with the GitHub CLI (gh)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [--publish]}"
PUBLISH="${2:-}"
DMG="build/LoFiHUD_v${VERSION}.dmg"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ Working tree has uncommitted changes. Commit them first so the release matches the tag." >&2
    exit 1
fi

echo "▸ Testing…"
scripts/test.sh

rm -rf "build/LoFi HUD.app"
VERSION="$VERSION" scripts/build.sh
VERSION="$VERSION" scripts/make_dmg.sh
shasum -a 256 "$DMG" | tee "$DMG.sha256"

if [[ "$PUBLISH" == "--publish" ]]; then
    command -v gh >/dev/null || { echo "✗ GitHub CLI not found: brew install gh && gh auth login" >&2; exit 1; }
    git tag -a "v$VERSION" -m "LoFi HUD $VERSION"
    git push origin HEAD "v$VERSION"
    gh release create "v$VERSION" "$DMG" "$DMG.sha256" --title "LoFi HUD $VERSION" --generate-notes
    echo "✓ Published v$VERSION"
else
    echo "✓ $DMG ready. Re-run with --publish to tag and upload it."
fi
