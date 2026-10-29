#!/usr/bin/env bash
# Compiles the pure-logic sources together with Tests/SelfTest.swift and runs it.
# (Command Line Tools ship without XCTest / Swift Testing macro plugins, so this is dependency-free.)
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp Tests/SelfTest.swift "$WORK/main.swift"
SRC=Sources/LoFiHUD
swiftc -O -o "$WORK/selftest" \
    "$SRC/Core/"*.swift \
    "$SRC/Input/KeyCodes.swift" \
    "$SRC/Audio/Player.swift" \
    "$WORK/main.swift"
"$WORK/selftest"
