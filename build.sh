#!/bin/sh
# Builds the repro app and the probe for the iOS simulator with the Xcode command line tools
# (no Xcode project), then installs the app on the given simulator.
# usage: ./build.sh <simulator-udid>
set -eu
UDID="$1"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
APP="$OUT/EdgePanRepro.app"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="$(uname -m)-apple-ios17.0-simulator"

rm -rf "$OUT"
mkdir -p "$APP"
xcrun --sdk iphonesimulator swiftc -sdk "$SDK" -target "$TARGET" -O \
  "$ROOT/App/main.swift" -o "$APP/EdgePanRepro"
cp "$ROOT/App/Info.plist" "$APP/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1

xcrun --sdk iphonesimulator clang -fobjc-arc -isysroot "$SDK" -target "$TARGET" \
  "$ROOT/probe/probe.m" -framework Foundation -framework IOKit -o "$OUT/probe"
codesign --force --sign - "$OUT/probe" >/dev/null 2>&1

xcrun --sdk iphonesimulator clang -fobjc-arc -isysroot "$SDK" -target "$TARGET" \
  "$ROOT/probe/touchscreens.m" -framework Foundation -framework IOKit -o "$OUT/touchscreens"
codesign --force --sign - "$OUT/touchscreens" >/dev/null 2>&1

xcrun simctl install "$UDID" "$APP"
