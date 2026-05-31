#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/WormholeLink.xcarchive}"
APP_PATH="$ARCHIVE_PATH/Products/Applications/WormholeLink.app"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
DMG_PATH="${DMG_PATH:-$DIST_DIR/WormholeLink-macOS.dmg}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-WormholeLink}"
STAGING_DIR="$DIST_DIR/dmg-root"
BACKGROUND_PATH="${BACKGROUND_PATH:-$ROOT_DIR/Config/DMGBackground.png}"
RW_DMG_PATH="$DIST_DIR/WormholeLink-layout.dmg"
MOUNT_POINT=""

cleanup() {
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_DIR"
  rm -f "$RW_DMG_PATH"
}

trap cleanup EXIT INT TERM

if ! hdiutil help >/dev/null 2>&1; then
  echo "error: hdiutil is unavailable on this machine." >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

"$ROOT_DIR/scripts/archive-release.sh"
"$ROOT_DIR/scripts/generate-dmg-background.sh"

if [ ! -d "$APP_PATH" ]; then
  echo "error: expected app bundle at $APP_PATH" >&2
  exit 1
fi

if [ ! -f "$BACKGROUND_PATH" ]; then
  echo "error: expected DMG background at $BACKGROUND_PATH" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
rm -f "$DMG_PATH"
rm -f "$RW_DMG_PATH"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$STAGING_DIR/.background"
cp "$BACKGROUND_PATH" "$STAGING_DIR/.background/background.png"

echo "Creating layout DMG at $RW_DMG_PATH"
hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  "$RW_DMG_PATH" >/dev/null

ATTACH_OUTPUT=$(hdiutil attach "$RW_DMG_PATH" -readwrite -noverify -noautoopen)
MOUNT_POINT=$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// { path = $0; sub(/^.*\/Volumes\//, "/Volumes/", path); print path; exit }')
MOUNT_NAME=$(basename "$MOUNT_POINT")

if [ -z "$MOUNT_POINT" ]; then
  echo "error: failed to mount temporary DMG" >&2
  exit 1
fi

if [ "${SKIP_DMG_LAYOUT:-0}" != "1" ]; then
  BACKGROUND_ALIAS_PATH="$MOUNT_POINT/.background/background.png"
  osascript <<EOF
set bgFile to POSIX file "$BACKGROUND_ALIAS_PATH"
tell application "Finder"
  tell disk "$MOUNT_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 840, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set text size of viewOptions to 12
    set background picture of viewOptions to bgFile
    set position of item "WormholeLink.app" to {176, 192}
    set position of item "Applications" to {534, 192}
    close
    open
    update without registering applications
  end tell
end tell
EOF
fi

sync
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""

echo "Compressing DMG to $DMG_PATH"
hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

if [ "${NOTARIZE_DMG:-0}" = "1" ]; then
  "$ROOT_DIR/scripts/notarize-release.sh" "$DMG_PATH"
fi

echo "Created $DMG_PATH"