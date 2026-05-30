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
```

## Current Limitations

- This is a development build, not a packaged `.app` or DMG release
- Notification Center support is only enabled when running from a proper bundled macOS app
- The app does not yet include an Xcode project, signing setup, or release packaging flow

## Next Steps

Useful future improvements include:

- packaging the app as a real macOS `.app`
- adding automated tests for tunnel argument generation and configuration import/export
- improving runtime diagnostics around SSH authentication and connection verification