#!/bin/bash
# Builds QuietDesk.app with only the Xcode Command Line Tools (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" 2>&1 | grep -v -E '^\[|warning:' || true
BIN=".build/$CONFIG/QuietDesk"
test -x "$BIN" || { echo "build failed"; exit 1; }
APP="build/QuietDesk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QuietDesk"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Ad-hoc signature: required to run on Apple silicon; not a Developer ID signature.
codesign --force --sign - --identifier dev.quietdesk.QuietDesk "$APP" >/dev/null
echo "Built $APP"
