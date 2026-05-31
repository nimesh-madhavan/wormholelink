#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PNG_PATH="${PNG_PATH:-$ROOT_DIR/Config/DMGBackground.png}"
RUNNER_PATH="${RUNNER_PATH:-$ROOT_DIR/build/generate-dmg-background}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc is required to render the DMG background." >&2
  exit 1
fi

mkdir -p "$(dirname "$PNG_PATH")"
mkdir -p "$(dirname "$RUNNER_PATH")"

swiftc \
  -parse-as-library \
  "$ROOT_DIR/scripts/generate-dmg-background.swift" \
  -o "$RUNNER_PATH"

"$RUNNER_PATH" "$PNG_PATH"
echo "Generated $PNG_PATH"