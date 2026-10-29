#!/usr/bin/env bash
# Packages build/LoFi HUD.app into a drag-to-Applications DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-2.0.0}"
APP="build/LoFi HUD.app"
DMG="build/LoFiHUD_v${VERSION}.dmg"
[[ -d "$APP" ]] || VERSION="$VERSION" scripts/build.sh

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "LoFi HUD" -srcfolder "$STAGE" -ov -format ULFO "$DMG" >/dev/null
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
