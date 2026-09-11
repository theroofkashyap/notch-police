#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
DEPLOYMENT_TARGET="14.0"
# Builds for whatever machine is doing the building. Set ARCHS="arm64 x86_64"
# to produce a universal binary for distribution.
ARCHS="${ARCHS:-$(uname -m)}"
CONFIG="${1:-debug}"
OUT="$ROOT/.build/$CONFIG"
mkdir -p "$OUT"

CORE_SRCS=(Sources/NotchPoliceCore/*.swift)
APP_SRCS=(Sources/NotchPolice/*.swift)

core_slices=()
app_slices=()

for arch in $ARCHS; do
  slice="$OUT/$arch"
  mkdir -p "$slice"

  common=(swiftc -sdk "$SDK" -target "${arch}-apple-macosx${DEPLOYMENT_TARGET}" -parse-as-library)
  if [[ "$CONFIG" == "release" ]]; then
    common+=(-O -whole-module-optimization)
  else
    common+=(-Onone -g)
  fi

  echo "→ compiling NotchPoliceCore ($CONFIG, $arch)"
  "${common[@]}" \
    -module-name NotchPoliceCore \
    -emit-module \
    -emit-module-path "$slice/NotchPoliceCore.swiftmodule" \
    -emit-library \
    -o "$slice/libNotchPoliceCore.dylib" \
    -Xlinker -install_name -Xlinker @rpath/libNotchPoliceCore.dylib \
    -lsqlite3 \
    -framework Foundation \
    -framework Security \
    "${CORE_SRCS[@]}"

  echo "→ compiling NotchPolice ($CONFIG, $arch)"
  "${common[@]}" \
    -module-name NotchPolice \
    -I "$slice" \
    -L "$slice" \
    -lNotchPoliceCore \
    -Xlinker -rpath -Xlinker @executable_path \
    -framework Foundation \
    -framework AppKit \
    -framework SwiftUI \
    -framework UserNotifications \
    -framework ServiceManagement \
    -o "$slice/NotchPolice" \
    "${APP_SRCS[@]}"

  core_slices+=("$slice/libNotchPoliceCore.dylib")
  app_slices+=("$slice/NotchPolice")
done

lipo -create "${core_slices[@]}" -output "$OUT/libNotchPoliceCore.dylib"
lipo -create "${app_slices[@]}" -output "$OUT/NotchPolice"

echo "→ $OUT/NotchPolice ($(lipo -archs "$OUT/NotchPolice"))"
