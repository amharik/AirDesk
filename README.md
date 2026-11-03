# AirDesk

[![iOS CI](https://github.com/amharik/AirDesk/actions/workflows/ios.yml/badge.svg)](https://github.com/amharik/AirDesk/actions/workflows/ios.yml)

AirDesk turns an iPhone or iPad into a wireless keyboard, trackpad, and remote for a macOS-style desktop. The desktop runs locally in a Wanix WebAssembly workspace and can be shown on a TV, an external display, or a Google Cast receiver while the phone stays in your hand as the controller.

## Status

AirDesk is in active development. It builds and runs on iOS and iPadOS 17+, and the core input, desktop, terminal, and display paths are implemented. It is **not yet App Store-ready**: ADR-007 is still Proposed and the remaining Cast, external-display, performance, and distribution gates must pass first.

| Area | Current state |
| --- | --- |
| iPhone / iPad controller | Working |
| Wanix desktop and WinBox windows | Working |
| WTerm + Ghostty terminal | Working, default |
| Remote SSH PTY | Working, opt-in |
| AirPlay / external display | Implemented |
| Google Cast receiver | Development app |
| Unit tests | 116 passing |
| iPad UI suite | Passing; 1 opt-in test skipped |
| App Store release | Not yet |

## Features

### A real desktop, not a mock

- A macOS-style workspace with a menubar, Dock, Spotlight, desktop icons, context menus, and window controls.
- **Finder**, **Terminal**, and **Notes** share the same Wanix virtual filesystem.
- Windows are managed by WinBox behind an AirDesk-owned adapter, with focus, z-order, minimize, maximize, restore, close, drag, and resize.
- The desktop shell is served from a loopback-only asset server with a strict Content Security Policy. Wanix, WTerm, fonts, and terminal cores do not require a runtime CDN.

### Precise remote input

- Normalized pointer movement, tap, drag, scroll, text, and key events over one native bridge.
- Pointer ballistics and trackpad-style gestures for precise control on a phone or tablet.
- On-screen keyboard deck plus optional physical keyboard and mouse capture, with a clear capture/release state.
- Long-press drag mode and window drag mode for controlling a desktop from a touch screen.
- The same normalized event stream powers the phone preview and external display, and is the basis for Cast input.

### Terminal built for real work

- **WTerm** with the **Ghostty** core is the default terminal renderer.
- The local terminal attaches to the live Wanix shell and supports selection, copy/paste, scrollback, and transcript replay after a reload.
- A legacy `wanix-term` renderer remains available as an explicit rollback path.
- **Remote SSH** replaces the local shell with a native SwiftNIO SSH PTY. The app pins the server host key, stores the password in the Keychain, and defaults to `tmux new -A -s airdesk` so reconnects attach to the same remote session.
- Terminal window resize is bridged into the shell environment. See [current state and limitations](#current-state-and-limitations) for the current boundary.

### Flexible output

- **Extended desktop** sends the workspace to an AirPlay or external display while the phone remains a controller.
- **Mirror iPhone screen** renders the desktop full-screen on the phone and lets iOS mirror the whole screen to a TV.
- A separate **CastReceiver** development app is included for Google Cast work.
- A phone preview mode keeps the desktop visible while the floating remote stays available.

### Pro runtime

- The standalone **Wanix Kernel** runtime requires a Pro entitlement.
- Pro products are wired through StoreKit 2 and the local `AirDesk.storekit` configuration for development.

## Requirements

- iPhone or iPad running **iOS / iPadOS 17 or later**.
- A Mac for building the app.
- **Xcode 16.4** or later and **XcodeGen**.
- **Node.js 22** only when changing the bundled desktop shell.
- Optional: an AirPlay receiver, external display, Cast receiver, or an SSH host for the remote terminal.

## Quick start

AirDesk is currently built from source.

```bash
brew install xcodegen
git clone git@github.com:amharik/AirDesk.git
cd AirDesk
xcodegen generate
open AirDesk.xcodeproj
```

In Xcode, select the **AirDesk** scheme, choose your development team under Signing & Capabilities, select an iPhone or iPad, and run.

To build and test on a simulator without signing:

```bash
./scripts/ci-ios.sh
```

Override the default simulator with an Xcode destination:

```bash
AIRDESK_DESTINATION='platform=iOS Simulator,name=iPad Pro (11-inch) (3rd generation)' ./scripts/ci-ios.sh
```

## Using AirDesk

1. Launch AirDesk on your iPhone or iPad.
2. Choose the **Wanix Desktop** runtime and connect. A demo session is available for trying the interface without a second device.
3. Send the desktop to a display with AirPlay, an external display, or a Cast receiver.
4. Open **Preview Desktop** to use the workspace on the phone. Use the floating remote for pointer, keyboard, and window actions.
5. Use **Session → Remote Terminal** in Settings to point the terminal at an SSH host instead of the local Wanix shell.

### Remote terminal setup

Remote SSH is opt-in and uses the native SSH stack, not the web shell.

- Host, port, username, password, and pinned host key are entered in Settings.
- The default startup command is `tmux new -A -s airdesk`.
- Applying new settings restarts an open Terminal window so the new transport takes effect immediately.
- Turning the feature off returns the Terminal to the local Wanix shell.

## Runtime modes

| Mode | What it is | Access |
| --- | --- | --- |
| **Wanix Desktop** | Default local desktop with the embedded Wanix namespace | Free |
| **Wanix Kernel** | Standalone live Wanix kernel surface | Pro |
| **Puter** | Remote Puter.js adapter | Present but not configured in this build |

## Current state and limitations

- ADR-007 (WinBox + WTerm) is **Proposed**. WinBox parity, WTerm conformance, and hardware qualification gates remain.
- Hardware and release gates still pending: Cast parity, external-display and safe-area behavior, 60 FPS at 1080p, signed offline install, Xcode 26 Cast SDK, and category-D parity.
- Terminal resize currently updates `COLUMNS` and `LINES` for subsequent shell commands. A running full-screen program does not receive a true PTY resize yet; that remains blocked on an upstream Wanix/`rc` change. Rotating the device alone does not resize the floating terminal window.
- Transcript replay restores terminal text after a reload, but the Wanix shell process restarts. Byte-exact PTY reconnect and live process resumption are not implemented.
- The real OpenSSH smoke test is opt-in because it needs a reachable SSH host and throwaway credentials. The default UI suite uses an in-process fixture.
- Puter is not configured in the current build.

## Architecture at a glance

```mermaid
flowchart LR
  Phone["iPhone / iPad<br/>SwiftUI controller"] -->|"pointer, keys, text"| Bridge["RuntimeBridge"]
  Bridge --> Shell["WKWebView desktop shell"]
  Shell --> Wanix["Wanix WebAssembly namespace"]
  Wanix --> Apps["Finder · Terminal · Notes"]
  Shell --> Display["AirPlay / external display"]
  Shell -.-> Cast["Cast receiver"]
  Phone -->|"native SSH PTY"| Remote["Remote terminal"]
```

The phone sends normalized input through one bridge. The desktop shell owns the workspace and routes input to windows, fields, or the terminal. A native loopback asset server provides cross-origin isolation for the WebAssembly runtime. See [ADR-005](docs/adr/005-display-and-transport.md), [ADR-007](docs/adr/007-winbox-and-wterm.md), and [ADR-008](docs/adr/008-input-and-control-protocol.md) for the decisions behind the architecture.

## Development

### Project layout

```text
AirDesk/
  App/                 App entry, routing, lifecycle
  Features/            Welcome, pairing, remote, keyboard, settings
  Session/             Session state machine and coordinator
  Display/             WKWebView surface and external display scenes
  Runtime/             Wanix and Puter runtime adapters
  Input/               Input schema, dispatcher, pointer ballistics
  Web/                 Swift-to-JavaScript bridge, loopback asset server
  Security/            Origin and navigation policy
  Store/               StoreKit 2 entitlement manager
  Resources/
    DesktopShell/      index.html, desktop.js, apps.js, shell.css, bundled assets
AirDeskTests/          Unit tests
AirDeskUITests/        UI and device tests
CastReceiver/          Google Cast receiver development app
scripts/               Build, CI, simulator, and smoke-test helpers
protocol/              FlatBuffers schema and language bindings
docs/adr/              Architecture decision records
project.yml            XcodeGen project definition
```

### Desktop shell

The shell source lives in `web/src`; generated bundles are committed under `AirDesk/Resources/DesktopShell`.

```bash
cd web
npm ci
npm run check
npm run build
```

`npm run check` runs TypeScript, lint, tests, a committed-bundle freshness check, and the license policy. `npm run sbom` writes `web/build/sbom.cdx.json`. Bundled third-party notices live under `third_party/`.

### Protocol bindings

`protocol/airdesk.fbs` is the source of truth for input and control messages. Install `flatc` 25.12.19, then regenerate the checked-in Swift, TypeScript, and Rust bindings:

```bash
./protocol/generate.sh
cd web && npm run check
cargo test --manifest-path ../protocol/rust/Cargo.toml
```

### Tests and CI

- `AirDeskTests`: 116 unit tests covering input, runtime routing, SSH PTY, reconnect, terminal messages, and entitlements.
- `AirDeskUITests`: controller and desktop flows, terminal typing, resize, transcript replay, remote SSH, and WinBox lifecycle.
- `.github/workflows/ios.yml` runs the CI-equivalent checks on macOS through `scripts/ci-ios.sh`.

For a real OpenSSH smoke test on a Mac with `sshd` and Xcode:

```bash
scripts/real-ssh-smoke.sh
```

## Security and privacy

- The desktop asset server binds to loopback and enforces COOP/COEP and a strict CSP.
- No runtime CDN is required for Wanix, WTerm, fonts, or terminal cores.
- Remote SSH uses the native SwiftNIO stack with a pinned OpenSSH host key.
- Passwords are stored in the device Keychain. SSH credentials and private keys are not bundled into the web shell or committed to the repository.
- The `airdeskTerminal` bridge carries only PTY input, output, resize, and lifecycle messages.

## Documentation

- [ADR-001: Multi-runtime architecture](docs/adr/001-multi-runtime-architecture.md)
- [ADR-005: Display and transport](docs/adr/005-display-and-transport.md)
- [ADR-006: Remote windowing](docs/adr/006-remote-windowing.md)
- [ADR-007: WinBox and WTerm](docs/adr/007-winbox-and-wterm.md)
- [ADR-008: Input and control protocol](docs/adr/008-input-and-control-protocol.md)
- [ADR-009: Workspace persistence and recovery](docs/adr/009-workspace-persistence-and-recovery.md)
- [ADR-010: AirDesk Fabric Protocol](docs/adr/010-airdesk-fabric-protocol.md)
- [ADR-011: Device identity, discovery and pairing](docs/adr/011-device-identity-discovery-pairing.md)
- [ADR-012: Capability advertisement and authorization](docs/adr/012-capability-advertisement-and-authorization.md)
- [ADR-013: Multi-transport and connectivity](docs/adr/013-multi-transport-and-connectivity.md)
- [Workspace Fabric plan](docs/planning/workspace-fabric-plan.md)

## License

No license file is currently included in this repository. All rights are reserved unless a license is added.
