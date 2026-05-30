# WormholeLink

WormholeLink is a native macOS menu bar app for creating and managing SSH tunnels without using the terminal directly. It supports local forwards, remote forwards, and SOCKS proxy tunnels through a SwiftUI preferences window and a menu bar status item.

This repository currently contains a Swift Package based development build of the app.

## Features

- Manage SSH tunnel configurations from a macOS preferences window
- Start and stop tunnels from the menu bar
- Support for:
  - Local forward tunnels
  - Remote forward tunnels
  - SOCKS proxy tunnels
- Password and identity-file authentication
- Password and passphrase storage through macOS Keychain
- Import and export tunnel configurations as JSON
- Export all connections into a single JSON backup file
- Persistent debug logging for troubleshooting tunnel startup and lifecycle issues

## Requirements

- macOS 13 Ventura or newer
- Apple Swift 6 toolchain or newer
- Access to the system SSH binary at `/usr/bin/ssh`

## Project Layout

- `Package.swift`: Swift Package definition
- `Sources/WormholeLink/`: application source code
- `spec.md`: original product specification used to implement the app

## Build

From the repository root:

```bash
swift build
```

This builds the debug executable in `.build/arm64-apple-macosx/debug/` on Apple Silicon Macs.

## Xcode Project

This repository also includes an Xcode project for app-style development and release packaging:

```text
WormholeLink.xcodeproj
```

Open it with full Xcode:

```bash
open WormholeLink.xcodeproj
```

Notes:

- Full Xcode is required. Command Line Tools alone are not enough for `xcodebuild archive`.
- The Xcode project is configured as a macOS app target that uses the existing source files under `Sources/WormholeLink`.
- The bundled app uses `Config/Info.plist` for app metadata.

## Run

To launch the app in development mode:

```bash
swift run
```

This starts WormholeLink as a menu bar app. Open the status item from the macOS menu bar to access connections and preferences.

## Debug

### Option 1: Use the built-in debug log

WormholeLink writes a persistent log file to:

```text
~/Library/Application Support/WormholeLink/Logs/debug.log
```

You can open the log from either:

- the application menu: `Open Debug Log`
- the menu bar dropdown: `Open Debug Log`

The log includes tunnel state transitions, SSH launch arguments, startup verification messages, import/export activity, and other app lifecycle events.

### Option 2: Run from the terminal

Running with `swift run` is useful when iterating quickly on UI and tunnel behavior:

```bash
swift run
```

Then reproduce the issue and inspect the debug log.

### Option 3: Debug in Xcode or LLDB

You can also open the folder in Xcode or attach LLDB to the running process if you want to step through the Swift code.

With the included Xcode project, you can:

- run the app directly from Xcode
- set breakpoints in the Swift sources
- archive a Release build for distribution

## Configuration Import and Export

WormholeLink supports JSON-based tunnel configuration exchange.

- `Export`: exports the currently selected tunnel as a JSON file
- `Export All...`: exports all saved tunnels into one JSON file
- `Import...`: imports either a single tunnel JSON file or a JSON array exported by `Export All...`

Imported connections are merged with existing connections. New UUIDs are assigned automatically and names are adjusted when needed to avoid collisions.

## Notes for Development

- The project currently uses Swift Package Manager instead of an Xcode `.app` target.
- When launched via `swift run`, some macOS app-bundle-specific features are limited.
  - Notification Center integration is intentionally skipped in non-bundled runs.
- Tunnel startup and failure analysis are easiest to diagnose using the persistent debug log.
- The app uses the system SSH client and does not bundle its own SSH implementation.

## Common Development Commands

```bash
swift build
swift run
open WormholeLink.xcodeproj
./scripts/package-dmg.sh
./scripts/release-all.sh
```

## Release Packaging

Release packaging is set up through shell scripts in `scripts/`.

### Archive a Release Build

```bash
./scripts/archive-release.sh
```

Optional environment variables:

- `DEVELOPMENT_TEAM`: override the signing team for `xcodebuild archive`
- `SKIP_CODESIGN=1`: create an unsigned archive for local testing
- `ARCHIVE_PATH=/custom/path/WormholeLink.xcarchive`: choose a custom archive path

The archive script builds a universal binary targeting both `arm64` (Apple Silicon) and `x86_64` (Intel) so the resulting app runs natively on all supported Macs.

### Create a ZIP for Direct Distribution

```bash
./scripts/package-release.sh
```

This will:

- archive the app in Release mode
- package `WormholeLink.app` into `dist/WormholeLink-macOS.zip`

### Create a DMG for Drag-and-Drop Installation

```bash
./scripts/package-dmg.sh
```

This will:

- archive the app in Release mode
- create `dist/WormholeLink-macOS.dmg`
- include a styled Finder window with background artwork and positioned icons
- use the application icon as the mounted DMG volume icon
- include an `Applications` shortcut for drag-and-drop installation

Optional environment variables:

- `DMG_PATH=/custom/path/WormholeLink.dmg`: choose a custom DMG output path
- `DMG_VOLUME_NAME=WormholeLink`: set the mounted volume name
- `SKIP_DMG_LAYOUT=1`: skip Finder window styling when running in an environment without Finder automation
- `NOTARIZE_DMG=1`: build the DMG and immediately notarize and staple it

### Notarize and Staple a Release Artifact

```bash
./scripts/notarize-release.sh
```

or for a DMG:

```bash
./scripts/notarize-release.sh dist/WormholeLink-macOS.dmg
```

Use either:

- `NOTARY_PROFILE=<keychain-profile>`

or:

- `APPLE_ID=<apple-id>`
- `APPLE_TEAM_ID=<team-id>`
- `APPLE_APP_PASSWORD=<app-specific-password>`

By default the notarization script targets `dist/WormholeLink-macOS.zip`.

When the input artifact is a `.dmg`, `.app`, or `.pkg`, the script also runs `xcrun stapler staple` after notarization succeeds.

### Build ZIP and DMG Together

```bash
./scripts/release-all.sh
```

This builds both release artifacts into `dist/`.

Optional environment variables:

- `NOTARIZE_DMG=1`: also notarize and staple the DMG once both artifacts are built

## Current Limitations

- The included release flow produces an archived app bundle, ZIP, and styled DMG, but it does not yet automate Developer ID signing for the DMG container itself
- Notification Center support is only enabled when running from a proper bundled macOS app
- The DMG layout uses Finder scripting, so fully headless CI environments may need `SKIP_DMG_LAYOUT=1`

## Next Steps

Useful future improvements include:

- packaging the app as a real macOS `.app`
- adding automated tests for tunnel argument generation and configuration import/export
- improving runtime diagnostics around SSH authentication and connection verification