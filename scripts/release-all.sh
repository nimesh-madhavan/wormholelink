#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

"$ROOT_DIR/scripts/package-release.sh"
"$ROOT_DIR/scripts/package-dmg.sh"

if [ "${NOTARIZE_DMG:-0}" = "1" ]; then
  "$ROOT_DIR/scripts/notarize-release.sh" "$ROOT_DIR/dist/WormholeLink-macOS.dmg"
fi

echo "Release artifacts ready in $ROOT_DIR/dist"