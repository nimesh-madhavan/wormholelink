#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/WormholeLink.xcodeproj"
SCHEME="WormholeLink"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/WormholeLink.xcarchive}"

if ! xcodebuild -version >/dev/null 2>&1; then
  if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: full Xcode is required to archive this app." >&2
  exit 1
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")"

set -- xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [ "${SKIP_CODESIGN:-0}" = "1" ]; then
  set -- "$@" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
elif [ -n "${DEVELOPMENT_TEAM:-}" ]; then
  set -- "$@" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
fi

echo "Archiving WormholeLink to $ARCHIVE_PATH"
"$@"