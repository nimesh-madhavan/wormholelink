#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARTIFACT_PATH="${1:-${ARTIFACT_PATH:-$ROOT_DIR/dist/WormholeLink-macOS.zip}}"
STAPLE_PATH="${STAPLE_PATH:-$ARTIFACT_PATH}"

if ! xcrun notarytool --help >/dev/null 2>&1; then
  if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

if ! xcrun notarytool --help >/dev/null 2>&1; then
  echo "error: notarytool is unavailable. Install full Xcode and configure Xcode command line tools." >&2
  exit 1
fi

if [ ! -f "$ARTIFACT_PATH" ]; then
  echo "error: expected packaged artifact at $ARTIFACT_PATH" >&2
  exit 1
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$ARTIFACT_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
  : "${APPLE_ID:?Set APPLE_ID or NOTARY_PROFILE}"
  : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or NOTARY_PROFILE}"
  : "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD or NOTARY_PROFILE}"
  xcrun notarytool submit "$ARTIFACT_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
fi

case "$STAPLE_PATH" in
  *.dmg|*.app|*.pkg)
    xcrun stapler staple "$STAPLE_PATH"
    ;;
esac