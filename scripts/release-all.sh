#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

"$ROOT_DIR/scripts/package-release.sh"
"$ROOT_DIR/scripts/package-dmg.sh"

echo "Release artifacts ready in $ROOT_DIR/dist"