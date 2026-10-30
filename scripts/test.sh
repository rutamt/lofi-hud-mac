#!/usr/bin/env bash
# Compiles the pure-logic sources together with Tests/SelfTest.swift and runs it.
# (Command Line Tools ship without XCTest / Swift Testing macro plugins, so this is dependency-free.)
#   scripts/test.sh          logic checks
#   scripts/test.sh --audio  also run the real-audio engine smoke test (plays quiet tones briefly)
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp Tests/SelfTest.swift "$WORK/main.swift"
SRC=Sources/LoFiHUD
swiftc -O -target "$(uname -m)-apple-macos14.0" -o "$WORK/selftest" \
    "$SRC/Core/"*.swift \
    "$SRC/Input/KeyCodes.swift" "$SRC/Input/Hotkeys.swift" \
    "$SRC/Audio/PlayQueue.swift" "$SRC/Audio/Library.swift" \
    "$SRC/System/Updater.swift" \
    "$WORK/main.swift"
"$WORK/selftest"

if [[ "${1:-}" == "--audio" ]]; then
    mkdir -p "$WORK/audio"
    cp Tests/AudioSmokeTest.swift "$WORK/audio/main.swift"
    swiftc -O -target "$(uname -m)-apple-macos14.0" -o "$WORK/audiotest" \
        "$SRC/Core/"*.swift "$SRC/Audio/"*.swift "$SRC/System/Updater.swift" \
        "$WORK/audio/main.swift"
    "$WORK/audiotest"
fi
