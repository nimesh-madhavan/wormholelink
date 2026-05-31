#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ICNS_PATH="${ICNS_PATH:-$ROOT_DIR/Config/AppIcon.icns}"
RUNNER_PATH="${RUNNER_PATH:-$ROOT_DIR/build/generate-app-icon}"

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift is required to render the application icon." >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "error: iconutil is required to build AppIcon.icns." >&2
  exit 1
fi

mkdir -p "$(dirname "$ICNS_PATH")"
mkdir -p "$(dirname "$RUNNER_PATH")"

swiftc \
  -parse-as-library \
  "$ROOT_DIR/Sources/WormholeLink/WormholeIcon.swift" \
  "$ROOT_DIR/scripts/generate-app-icon.swift" \
  -o "$RUNNER_PATH"

"$RUNNER_PATH" "$ICNS_PATH"

echo "Generated $ICNS_PATH"