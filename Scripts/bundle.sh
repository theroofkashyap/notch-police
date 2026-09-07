#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
BIN="$ROOT/.build/$CONFIG/NotchPolice"
APP="$ROOT/.build/NotchPolice.app"

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  echo "run: ./Scripts/build.sh $CONFIG" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchPolice"
if [[ -f "$ROOT/.build/$CONFIG/libNotchPoliceCore.dylib" ]]; then
  cp "$ROOT/.build/$CONFIG/libNotchPoliceCore.dylib" "$APP/Contents/MacOS/"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -d "$ROOT/Resources/Providers" ]]; then
  mkdir -p "$APP/Contents/Resources/Providers"
  cp "$ROOT/Resources/Providers/"*.png "$APP/Contents/Resources/Providers/" 2>/dev/null || true
fi

codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
