# WormholeLink — Product Specification

## Overview

WormholeLink is a native macOS menu bar app for creating and managing SSH tunnels. It targets developers and power users who need secure port forwarding without touching the command line. It is a spiritual successor to **Secure Pipes** — providing the same three tunnel types with a modern SwiftUI interface.

---

## Technology Stack

| Concern | Choice |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI + AppKit (NSStatusItem menu bar) |
| SSH execution | System `ssh` binary (`/usr/bin/ssh`) via `Process` |
| Credential storage | macOS Keychain (via `Security` framework) |
| Persistence | `UserDefaults` / plist for non-sensitive config |
| Minimum macOS | 13 Ventura |
| Distribution | Direct download (DMG) — not Mac App Store (requires `Process` + SSH binary access) |

---

## Core Concepts

### Tunnel Types

1. **Local Forward** — Binds a port on the local machine and forwards traffic through the SSH server to a remote host:port. Use case: access a database or private service behind a firewall.
   - SSH equivalent: `ssh -L [bind_addr:]local_port:remote_host:remote_port user@ssh_server`

2. **Remote Forward** — Instructs the SSH server to bind a port on itself and forward incoming traffic back to a local host:port. Use case: expose a local service (e.g., dev server) through a cloud host.
   - SSH equivalent: `ssh -R [bind_addr:]remote_port:local_host:local_port user@ssh_server`

3. **SOCKS Proxy** — Creates a dynamic SOCKS5 proxy on a local port through the SSH server. Use case: anonymize browsing or route all traffic through a remote network.
   - SSH equivalent: `ssh -D [bind_addr:]local_port user@ssh_server`

---

## Data Model

### `Tunnel` (stored per-connection)

```
id: UUID
name: String                    // user-facing label, must be unique
type: TunnelType                // .localForward | .remoteForward | .socksProxy
sshHost: String                 // SSH server hostname or IP
sshPort: Int                    // default 22
sshUser: String
authMethod: AuthMethod          // .password | .identityFile
identityFilePath: String?       // path to private key file
// password / passphrase stored in Keychain, keyed by id

localBindAddress: String        // default "127.0.0.1"
localPort: Int

remoteHost: String?             // Local/Remote Forward only
remotePort: Int?                // Local/Remote Forward only

compress: Bool                  // -C flag
strictHostKeyChecking: Bool     // StrictHostKeyChecking=yes/no

autoStartOnLaunch: Bool         // connect when app starts
autoReconnect: Bool             // retry loop on unexpected disconnect
showInMenuBar: Bool             // include in menu bar tunnel list

// SOCKS Proxy only
autoConfigureSystemProxy: Bool  // write to Network Preferences via SystemConfiguration
```

### `AppSettings`

```
launchAtLogin: Bool
useNotificationCenter: Bool
allowSaveAdminPasswordInKeychain: Bool
reconnectOnSleepWake: Bool
```

---

## Application Architecture

```
WormholeLinkApp (SwiftUI App)
├── StatusBarController          // NSStatusItem, builds menu
├── TunnelManager                // owns all Tunnel states, spawns/kills SSH processes
│   └── TunnelSession            // wraps a single Process, stdout/stderr pipes, retry logic
├── KeychainService              // read/write passwords and passphrases
├── SystemProxyService           // SCPreferences to set/clear SOCKS proxy (admin auth)
├── SleepWakeObserver            // IOKit or NSWorkspace notifications
└── PreferencesWindow            // SwiftUI sheet / window
    ├── TunnelListView           // sidebar list of tunnels
    ├── TunnelDetailView         // form for Connection + Options tabs
    └── GeneralSettingsView
```

---

## UI Specification

### Menu Bar Icon

The `NSStatusItem` icon has four visual states:

| State | Icon description |
|---|---|
| No connections active | Hollow cloud / grey |
| One connection active | Filled cloud / tinted |
| Multiple connections active | Filled cloud + badge |
| Connecting (any) | Animated pulsing cloud |

### Menu Bar Dropdown (when clicked)

```
● My DB Tunnel          [Connected]   ▶ Disconnect
○ Work SOCKS Proxy      [Idle]        ▶ Connect
─────────────────────────────────────
  Connect All
  Disconnect All
─────────────────────────────────────
  Preferences...
  Quit WormholeLink
```

Tunnels with `showInMenuBar = false` are hidden from this list but manageable in Preferences.

### Preferences Window

**Layout**: Two-panel — sidebar tunnel list on the left, detail form on the right. Toolbar button `+` opens an action sheet to pick tunnel type; `−` removes selected tunnel; gear icon shows context actions (Duplicate, Export).

**Connection Tab** (all types share these fields):

- Connection Name *(text field)*
- SSH Server Address *(text field)*
- SSH Port *(number field, default 22)*
- SSH Username *(text field)*
- Authentication: segmented control `Password | Identity File`
  - Password mode: secure text field (saved to Keychain)
  - Identity File mode: file picker for `~/.ssh/id_*`, optional passphrase field
- Local Bind Address *(text field, default `127.0.0.1`; enter `*` for all interfaces)*
- Local Port *(number field)*
- Remote Host *(text field — Local Forward and Remote Forward only)*
- Remote Port *(number field — Local Forward and Remote Forward only)*
- *SOCKS Proxy only*: checkbox "Automatically configure system SOCKS proxy"

**Options Tab** (all types):

- [ ] Compress data
- [ ] Strict host key checking
- [ ] Start this connection when WormholeLink launches
- [ ] Automatically retry connection on disconnect
- [ ] Include in menu bar menu

**General Tab**:

- [ ] Launch WormholeLink at login
- [ ] Show connection notifications (Notification Center)
- [ ] Allow saving administrator password in Keychain
- [ ] Disconnect and reconnect active tunnels on sleep/wake

---

## Tunnel Lifecycle

1. **Start**: `TunnelManager` assembles `ssh` arguments from the `Tunnel` model, retrieves the password/passphrase from Keychain via `SSH_ASKPASS` or `sshpass` / `expect` pattern, spawns the `Process`.
2. **Monitor**: stdout/stderr pipes are read on a background `DispatchQueue`; connection is considered live when the SSH process is running and the local port is bound (verified with a brief `connect()` probe).
3. **Auto-retry**: If `autoReconnect` is true and the process exits unexpectedly, retry with exponential back-off (1 s, 2 s, 4 s … cap 60 s).
4. **Sleep/wake**: If `reconnectOnSleepWake` is true, `SleepWakeObserver` sends `SIGTERM` to active sessions on sleep and restarts them on wake.
5. **Stop**: `SIGTERM` sent to the `ssh` process; the local port is released.
6. **SOCKS proxy teardown**: If `autoConfigureSystemProxy` was set, `SystemProxyService` restores the previous Network Preferences state.

---

## Authentication

- **Password auth**: password retrieved from Keychain and passed to `ssh` via a helper script set as `SSH_ASKPASS` + `DISPLAY=dummy` (standard OpenSSH pattern). Password is never written to disk outside Keychain.
- **Identity file**: path passed via `-i`. If a passphrase exists it is provided through the same `SSH_ASKPASS` mechanism.
- **Host key verification**: When `strictHostKeyChecking = true`, the first connection shows a native dialog displaying the fingerprint with Accept / Reject. Accepted keys are stored in `~/.ssh/known_hosts` by `ssh` itself.

---

## Security Considerations

- All secrets (passwords, passphrases, admin password) are stored exclusively in the macOS Keychain.
- Identity key files must have permissions `0600`; WormholeLink warns the user and can optionally fix permissions before connecting.
- The app does not bundle or ship its own SSH binary; it uses the system-provided `/usr/bin/ssh` (or the path configured in General preferences if the user has a custom install).
- `autoConfigureSystemProxy` requires admin privileges; the admin password can be saved to Keychain under a separate Keychain item.

---

## Out of Scope (v1)

- SSH jump hosts / ProxyJump chains
- Built-in terminal / SSH session window
- VPN mode (tun/tap)
- iOS / iPadOS version
- Cloud-sync of tunnel configurations
