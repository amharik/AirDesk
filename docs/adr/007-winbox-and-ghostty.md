# ADR-007: Adopt WinBox for window mechanics and Ghostty for terminal emulation

- **Status:** Proposed — parity and qualification gates required
- **Date:** 2026-10-29
- **Scope:** DesktopShell window management, window chrome integration, terminal emulation, WKWebView/Cast/native parity
- **Supersedes:** ADR-002 decision to use `interact.js` for web window drag/resize/snapping and its rejection of `WinBox.js`. All other ADR-002 decisions remain in force.
- **Related:** ADR-002, ADR-003

## Context

The current DesktopShell is a custom IIFE window manager in `desktop.js`. It now passes the P0 input-stability work, but it still owns window creation, z-order, focus, drag, resize, minimize, maximize, close, Dock coordination, pointer routing, and terminal lifecycle. That is a large surface to maintain commercially.

The terminal is currently a `wanix-term` custom element backed by an xterm-compatible implementation. The shell depends on both the element contract and xterm-specific DOM/CSS hooks.

ADR-002 selected `interact.js` for web drag/resize and rejected WinBox as too large a migration during an input regression fix. That was the correct decision for P0. The product direction has since changed: AirDesk will adopt tested third-party libraries where they reduce owned surface area, even when that requires a controlled compositor migration.

## Decision

Adopt a library-backed compositor and terminal stack, behind AirDesk-owned adapters:

1. **WinBox.js** owns window mechanics: creation, drag, resize, focus, z-order, minimize, maximize, close, and viewport constraints.
2. **AirDesk owns the chrome and shell**: title bars, traffic lights, menubar, Dock, Spotlight, desktop icons, context menus, wallpaper, and input routing remain AirDesk components.
3. **Full replacement, not a hybrid**: the custom window manager is replaced behind a `DesktopWindowManager` adapter after parity tests pass.
4. **Ghostty owns terminal emulation**: `ghostty-web` ships first in WKWebView and Cast; `GhosttyKit` is the later native path.
5. **Ghostty sits behind a `TerminalEngine` adapter** implementing the current `wanix-term` contract. Wanix is not forked.
6. **`interact.js` is retained only for non-WinBox drag surfaces**, if any remain. It is no longer the window drag/resize layer.
7. **Thin upstream-first forks are allowed only for WinBox**, and only if AirDesk chrome cannot be preserved through supported extension points. Ghostty is not forked.

Exact versions must be pinned under ADR-003. The 2026 catalog candidates are WinBox `v0.2.82` (Apache-2.0) and `ghostty-web` `v0.4.0` (MIT); both require release, checksum, license, and platform verification before Trial.

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

Ghostty web assets are bundled locally; no runtime CDN dependency is permitted inside WKWebView, Cast, or offline sessions. Native GhosttyKit is a separate later adapter with the same behavioral contract.

## Migration plan

1. **Qualification spike:** WinBox with AirDesk chrome, native pointer input, safe areas, 1080p Cast, focus/z-order, and the P0 long-press/click regressions.
2. **Adapter build:** implement `DesktopWindowManager` and a parity harness against the current shell.
3. **Window cutover:** swap the custom window manager for the adapter, keep a rollback flag, then delete the replaced `desktop.js` window code.
4. **Ghostty spike:** `ghostty-web` behind `TerminalEngine`; run VT conformance, complex-script, scrollback, resize, and reconnect tests.
5. **Terminal cutover:** ship Ghostty web first, retain the xterm path as a fallback until release metrics pass, then remove it.
6. **Native follow-up:** add GhosttyKit for native panes only after web parity is stable.

Each cutover is independently reversible until its fallback is removed.

## Qualification spike results — 2026-10-30

- Pinned `winbox@0.2.82` under ADR-003 with npm integrity `sha512-fMHaLnnuhyw1mLvzmCTWMpRKDfXUK/Z08VdbyBqDaITFFAd3Fx2BGDCF6rzGSkWrQgo8fHTFpFICofyM36FTnA==`.
- The upstream ESM source was exercised directly in JSDOM, not a mock. WinBox accepts an AirDesk `template` and preserves all resize handles and `.wb-drag` behavior.
- The custom template keeps AirDesk traffic lights, title icon/title, dialog semantics, and app identity while WinBox owns focus, z-order, minimize, maximize/restore, close, and geometry.
- Added the `WinBoxWindowManager` adapter with focus history, viewport insets, close vetoes, lifecycle callbacks, and client-to-window coordinate conversion.
- Four adapter tests pass against the real upstream implementation, including chrome preservation, focus/z-order, traffic-light routing, close vetoes, and duplicate-id focus behavior.
- Upstream distribution sizes are 11.0 kB for minified JS and 4.8 kB for CSS; the bundled build is 16.0 kB. No fork is required for the supported chrome path.
- License text and attribution are recorded under `third_party/winbox/`.

Still pending before Trial: WKWebView/Cast 60 FPS measurement at 1080p, safe-area/rotation/external-display checks, physical native pointer and long-press regressions, VoiceOver/accessibility review, visual screenshots, CSP/offline packaging, and the category-D parity harness. The status remains **Proposed**.

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

### Ghostty

- VT conformance suite passes against the current terminal behavior.
- Devanagari, Arabic, CJK, emoji, combining marks, and wide characters render correctly.
- 5,000-line scrollback, alternate screen, mouse reporting, and bracketed paste pass.
- `fit`, resize, focus, and reconnect replay preserve terminal state without byte loss.
- Key encoding matches native input and existing typing tests.
- `wanix-term` contract and required CSS hooks are preserved through the adapter.
- WASM load time, memory, and offline bundle size meet the agreed budget.
- Web and native terminal behavior share one conformance matrix.

## Consequences

- AirDesk stops owning fragile window geometry and terminal parsing code.
- Two mature libraries enter the production surface, with new pins, upgrades, and qualification work.
- The compositor migration temporarily carries both implementations and a rollback flag.
- WinBox’s DOM ownership may force a thin fork; that fork becomes a maintained asset and must be tracked as a supply-chain item.
- Ghostty’s xterm compatibility is not assumed; the adapter and conformance suite are mandatory.
- ADR-002 remains valid for native trackpad gestures and TypeScript tooling, but its web window-manager decision is replaced once this ADR is accepted.
