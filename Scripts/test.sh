#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
DEPLOYMENT_TARGET="14.0"
ARCH="${ARCH:-$(uname -m)}"
OUT="$ROOT/.build/tests"
mkdir -p "$OUT"

# Tests compile alongside the core sources as one module so they can reach
# internal helpers without those helpers being public in the shipped library.
echo "→ compiling tests ($ARCH)"
swiftc -sdk "$SDK" -target "${ARCH}-apple-macosx${DEPLOYMENT_TARGET}" \
  -parse-as-library -Onone -g \
  -module-name NotchPoliceTests \
  -o "$OUT/NotchPoliceTests" \
  -lsqlite3 \
  -framework Foundation \
  -framework Security \
  Sources/NotchPoliceCore/*.swift \
  Tests/*.swift

echo "→ running tests"
"$OUT/NotchPoliceTests"
