# ADR-007: Adopt WinBox for window mechanics and wterm for terminal emulation

- **Status:** Proposed — WinBox parity and wterm qualification gates required
- **Date:** 2026-10-29
- **Updated:** 2026-10-30 — terminal decision revised from Ghostty to wterm
- **Scope:** DesktopShell window management, window chrome integration, terminal emulation, WKWebView/Cast/native parity
- **Supersedes:** ADR-002 decision to use `interact.js` for web window drag/resize/snapping and its rejection of `WinBox.js`. All other ADR-002 decisions remain in force.
- **Related:** ADR-002, ADR-003, ADR-005

## Context

The current DesktopShell is a custom IIFE window manager in `desktop.js`. It now passes the P0 input-stability work, but it still owns window creation, z-order, focus, drag, resize, minimize, maximize, close, Dock coordination, pointer routing, and terminal lifecycle. That is a large surface to maintain commercially.

The terminal is currently a `wanix-term` custom element backed by an xterm-compatible implementation. The shell depends on both the element contract and xterm-specific DOM/CSS hooks.

The original terminal choice was Ghostty. After reviewing the integration surface, the product direction changed to **wterm** as the primary terminal stack. wterm provides a small built-in VT core, native DOM text selection and accessibility, pluggable cores, and adapters for an offline just-bash shell and WebSocket transports. Ghostty is no longer the default web terminal; `@wterm/ghostty` remains an optional compatibility core only if the built-in core fails conformance.

ADR-002 selected `interact.js` for web drag/resize and rejected WinBox as too large a migration during an input regression fix. That was the correct decision for P0. The product direction has since changed: AirDesk will adopt tested third-party libraries where they reduce owned surface area, even when that requires a controlled compositor migration.

## Decision

Adopt a library-backed compositor and terminal stack, behind AirDesk-owned adapters:

1. **WinBox.js** owns window mechanics: creation, drag, resize, focus, z-order, minimize, maximize, close, and viewport constraints.
2. **AirDesk owns the chrome and shell**: title bars, traffic lights, menubar, Dock, Spotlight, desktop icons, context menus, wallpaper, and input routing remain AirDesk components.
3. **Full replacement, not a hybrid**: the custom window manager is replaced behind a `DesktopWindowManager` adapter after parity tests pass.
4. **wterm owns terminal emulation and rendering** by default in WKWebView and Cast. The DOM renderer (`@wterm/dom`) and built-in core (`@wterm/core`) are the baseline.
5. **wterm sits behind a `TerminalEngine` adapter** implementing the current `wanix-term` contract. Wanix is not forked.
6. **Wanix remains the authoritative live shell.** The `#task/shell/term` PTY is the product terminal. `@wterm/just-bash` is an offline/local shell adapter and demo fallback, not a replacement for Wanix and not an automatic silent fallback.
7. **SSH uses a transport, not the renderer.** `WebSocketTransport` or an equivalent backend is permitted only after the ADR-005 authenticated `wss` and certificate gates pass. No SSH keys or credentials are bundled into the web shell.
8. **`@wterm/ghostty` is optional and not shipped by default.** Adopt it only if the built-in core fails the conformance matrix and the larger Ghostty WASM bundle is justified by measured results.
9. **`interact.js` is retained only for non-WinBox drag surfaces**, if any remain. It is no longer the window drag/resize layer.
10. **Thin upstream-first forks are allowed only for WinBox**, and only if AirDesk chrome cannot be preserved through supported extension points. wterm is not forked.

Exact versions must be pinned under ADR-003. The selected candidates are WinBox `0.2.82` (Apache-2.0), wterm `0.5.7` (Apache-2.0), and `just-bash` `3.6.0` (Apache-2.0). All require release, checksum, license, and platform verification before Trial.

## Architecture

### Window manager

`DesktopWindowManager` is the only code allowed to call WinBox. The adapter exposes AirDesk-level operations:

- open, close, focus, minimize, maximize/restore;
- set bounds, title, icon, and app identity;
- query focus order and z-order;
- apply viewport insets for menubar and Dock;
- notify shell state when geometry, focus, or lifecycle changes;
- convert native normalized pointer coordinates into window-local coordinates;
- cancel drag/resize on display disconnect, rotation, or session teardown.

The shell must not reach into WinBox internals. If WinBox requires DOM ownership that conflicts with AirDesk chrome, the adapter injects AirDesk chrome through supported options or a thin patch. A fork must be pinned, documented, and kept upstream-first.

### Terminal

`TerminalEngine` preserves the existing terminal contract: `write`, `input`, `paste`, `fit`, `focus`, `connect`, scrollback, resize, and the `_term` compatibility shim used by `wanix-live.js`. The adapter owns DOM/CSS translation, key encoding, and reconnect behavior.

The wterm adapter maps terminal input to the Wanix PTY and PTY output back to `WTerm.write`. Remote controller input must go through the adapter's `input` path rather than synthesizing DOM keyboard events into wterm's textarea. WTerm's native textarea remains the accessible local input surface and must keep its label, selection, copy/paste, search, and focus behavior.

The just-bash adapter runs against its own virtual filesystem and must be visibly identified as an offline sandbox. It must not masquerade as the Wanix workspace or silently receive writes intended for the live PTY. SSH is a separate authenticated transport; the renderer alone does not provide remote access.

wterm and just-bash assets are bundled locally; no runtime CDN dependency is permitted inside WKWebView, Cast, or offline sessions.

### Dependency evidence

| Package | Version | License | SHA-512 integrity |
| --- | --- | --- | --- |
| `winbox` | `0.2.82` | Apache-2.0 | `sha512-fMHaLnnuhyw1mLvzmCTWMpRKDfXUK/Z08VdbyBqDaITFFAd3Fx2BGDCF6rzGSkWrQgo8fHTFpFICofyM36FTnA==` |
| `@wterm/core` | `0.5.7` | Apache-2.0 | `sha512-Dc12KwlWaCrTLABYNqm2OIxlC8vFsTejcJb8uql9oNucn5hj/YVldNOuBDddtSXJCasLBTPJQxdCnhnGZRYHKg==` |
| `@wterm/dom` | `0.5.7` | Apache-2.0 | `sha512-yqnn43PnPdexno0ZHEC94iYIOBhximQBTVDr3qhRuhO3IQ69TjbFHNf7d5+ooRaXcEmPYz38bDNV7OXG+qzV/A==` |
| `@wterm/just-bash` | `0.5.7` | Apache-2.0 | `sha512-pis8+Lgv9egxgNyLc2y33msRJOb1yyJak2zRaSZCm0mpq15qPT0ftJlUywZOiT7R5MVwA+9AOowscVMu5L4XWw==` |
| `just-bash` | `3.6.0` | Apache-2.0 | `sha512-2COjEgcHdqKXeQSiNfPAHmpwQx4S8wATaIwog83g2t645U5tom6FED4CBBdr3M+0ioX4xZ26eODw3/nD6RQ6xw==` |
| `@wterm/ghostty` (optional) | `0.5.7` | Apache-2.0 | `sha512-shvpcqzIaz5QuLoTqZ0miotG9GU6/cWPm/7ntjwylhozDRX+wt7DYwvXQenJJ2WtaSSn+wmoMJYplHXDFLjHIQ==` |

## Migration plan

1. **Qualification spike:** WinBox with AirDesk chrome, native pointer input, safe areas, 1080p Cast, focus/z-order, and the P0 long-press/click regressions.
2. **Adapter build:** implement `DesktopWindowManager` and a parity harness against the current shell.
3. **Window cutover:** swap the custom window manager for the adapter, keep a rollback flag, then delete the replaced `desktop.js` window code.
4. **wterm spike:** implement `TerminalEngine` over the Wanix PTY; run VT conformance, complex-script, scrollback, resize, and reconnect tests. Add a just-bash smoke path only after the PTY path passes.
5. **Terminal cutover:** ship wterm web first, retain the xterm path as a fallback until release metrics pass, then remove it.
6. **SSH follow-up:** integrate an authenticated `wss` transport only after the ADR-005 certificate and relay gates pass.
7. **Native follow-up:** a native terminal engine is a separate decision. GhosttyKit is not the default follow-up merely because an earlier draft selected Ghostty.

Each cutover is independently reversible until its fallback is removed.

## Qualification spike results — 2026-10-30

### WinBox

- Pinned `winbox@0.2.82` under ADR-003 with npm integrity `sha512-fMHaLnnuhyw1mLvzmCTWMpRKDfXUK/Z08VdbyBqDaITFFAd3Fx2BGDCF6rzGSkWrQgo8fHTFpFICofyM36FTnA==`.
- The upstream ESM source was exercised directly in JSDOM, not a mock. WinBox accepts an AirDesk `template` and preserves all resize handles and `.wb-drag` behavior.
- The custom template keeps AirDesk traffic lights, title icon/title, dialog semantics, and app identity while WinBox owns focus, z-order, minimize, maximize/restore, close, and geometry.
- Added the `WinBoxWindowManager` adapter with focus history, viewport insets, close vetoes, lifecycle callbacks, and client-to-window coordinate conversion.
- Four adapter tests pass against the real upstream implementation, including chrome preservation, focus/z-order, traffic-light routing, close vetoes, and duplicate-id focus behavior.
- A debug-only `-AirDeskWinBoxPreview` route loads a bundled three-window harness through the real `DesktopSurface` and WKWebView preview sheet. The harness uses the shipped `shell.css` and upstream WinBox assets.
- The simulator XCUITest covers focus/z-order, titlebar drag, minimize, maximize/restore, and close. It exposed a traffic-light bug where a second maximize tap did not restore; the adapter now toggles correctly and the regression is covered by both unit and UI tests.
- Full local verification passes: 18 web tests, 99 iOS unit tests, 6 iOS UI tests, 6 Rust tests, and `npm run check`.
- Upstream distribution sizes are 11.0 kB for minified JS and 4.8 kB for CSS; the bundled build is 16.0 kB. No fork is required for the supported chrome path.
- License text and attribution are recorded under `third_party/winbox/`.

Still pending before Trial: WKWebView/Cast 60 FPS measurement at 1080p, safe-area/rotation/external-display checks, physical native pointer and long-press regressions, VoiceOver/accessibility review, visual screenshots, CSP/offline packaging, and the category-D parity harness (the simulator harness now covers the adapter lifecycle path).

### wterm

- Package metadata, licenses, and integrities were verified for wterm `0.5.7` and just-bash `3.6.0`.
- The documented architecture provides a DOM renderer with native selection, copy/paste, search, accessibility, OSC 8 links, pluggable cores, and an inlined approximately 26 kB Zig/WASM VT core.
- `@wterm/just-bash` depends on `just-bash ^3.4.2`; the selected peer pin is `3.6.0`.
- No wterm runtime spike, WKWebView test, Wanix PTY integration, or conformance measurement has been completed yet. The status remains **Proposed**.

## Acceptance gates

### WinBox

- 60 FPS drag/resize in WKWebView and Cast at 1080p.
- Native pointer coordinates remain correct; no `0,0` regression.
- Long-press, drag-mode, and pointer-capture behavior remain crash-free.
- Focus, z-order, minimize, maximize, close, and Dock coordination pass parity tests.
- Menubar/Dock insets, rotation, external-display changes, and safe areas are correct.
- AirDesk chrome is preserved without a fork; if forked, the patch is minimal and upstreamable.
- Keyboard focus, accessibility labels, and screen-reader order do not regress.
- Offline/CSP behavior is verified and the WinBox bundle stays within the agreed size budget.

### wterm

- VT conformance suite passes against the current terminal behavior.
- Devanagari, Arabic, CJK, emoji, combining marks, and wide characters render correctly.
- 5,000-line scrollback, alternate screen, mouse reporting, and bracketed paste pass.
- `fit`, resize, focus, and reconnect replay preserve terminal state without byte loss.
- Key encoding matches native input, and remote controller input reaches the PTY without DOM event synthesis.
- The `wanix-term` contract and required `_term` compatibility hooks are preserved through the adapter.
- The live Wanix PTY remains the default shell; just-bash is clearly labeled, optional, and isolated from the Wanix filesystem.
- SSH remains disabled until an authenticated `wss` transport passes ADR-005 security and reconnect gates.
- WASM load time, memory, and offline bundle size meet the agreed budget.
- Text selection, copy/paste, find, focus order, and VoiceOver behavior pass in WKWebView.
- No runtime CDN is required for wterm, just-bash, fonts, or cores.
- `@wterm/ghostty`, if evaluated, passes the same conformance matrix and has a measured size or compatibility justification.

## Consequences

- AirDesk stops owning fragile window geometry and terminal parsing code.
- wterm becomes the primary terminal dependency; Ghostty is no longer the default path.
- just-bash provides an offline demo and test shell, but it is not a general POSIX environment, a Wanix replacement, or a network client.
- SSH remains a transport product, not a renderer feature; it cannot ship before authenticated remote transport exists.
- Two mature libraries enter the production surface, with new pins, upgrades, and qualification work.
- The compositor migration temporarily carries both implementations and a rollback flag.
- WinBox’s DOM ownership may force a thin fork; that fork becomes a maintained asset and must be tracked as a supply-chain item.
- wterm is still pre-1.0; its xterm and Ghostty-core compatibility is not assumed, so the adapter and conformance suite are mandatory.
- ADR-002 remains valid for native trackpad gestures and TypeScript tooling, but its web window-manager decision is replaced once this ADR is accepted.
