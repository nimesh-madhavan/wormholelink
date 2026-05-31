#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/WormholeLink.xcarchive}"
APP_PATH="$ARCHIVE_PATH/Products/Applications/WormholeLink.app"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
ZIP_PATH="${ZIP_PATH:-$DIST_DIR/WormholeLink-macOS.zip}"

if ! xcodebuild -version >/dev/null 2>&1; then
  if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

"$ROOT_DIR/scripts/archive-release.sh"

if [ ! -d "$APP_PATH" ]; then
  echo "error: expected app bundle at $APP_PATH" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"

echo "Packaging $APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Created $ZIP_PATH"