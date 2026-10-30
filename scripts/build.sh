#!/usr/bin/env bash
# Builds "build/LoFi HUD.app" (release, ad-hoc signed).
#   scripts/build.sh              # native arch
#   UNIVERSAL=1 scripts/build.sh  # arm64 + x86_64 (requires full Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-2.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/LoFi HUD.app"

echo "▸ Compiling (release)…"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
else
    swift build -c release
fi
BIN="$(swift build -c release --show-bin-path)/LoFiHUD"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LoFiHUD"
strip -x "$APP/Contents/MacOS/LoFiHUD" 2>/dev/null || true
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "▸ Signing (ad-hoc)…"
codesign --force --options runtime --timestamp=none -s "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"

SIZE=$(du -sh "$APP" | cut -f1)
echo "✓ $APP ($SIZE)"
