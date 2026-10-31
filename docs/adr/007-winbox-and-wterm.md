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

The original terminal choice was Ghostty. After reviewing the integration surface, the product direction changed to **wterm** as the primary terminal stack. wterm provides native DOM text selection and accessibility, pluggable cores, and adapters for an offline just-bash shell and WebSocket transports. The built-in core retained only 1,000 scrollback lines, so the production shell now uses `@wterm/ghostty` as the wterm core while keeping the wterm renderer, input model, and adapter. A standalone GhosttyKit terminal is still not the default path.

ADR-002 selected `interact.js` for web drag/resize and rejected WinBox as too large a migration during an input regression fix. That was the correct decision for P0. The product direction has since changed: AirDesk will adopt tested third-party libraries where they reduce owned surface area, even when that requires a controlled compositor migration.

## Decision

Adopt a library-backed compositor and terminal stack, behind AirDesk-owned adapters:

1. **WinBox.js** owns window mechanics: creation, drag, resize, focus, z-order, minimize, maximize, close, and viewport constraints.
2. **AirDesk owns the chrome and shell**: title bars, traffic lights, menubar, Dock, Spotlight, desktop icons, context menus, wallpaper, and input routing remain AirDesk components.
3. **Full replacement, not a hybrid**: the custom window manager is replaced behind a `DesktopWindowManager` adapter after parity tests pass.
4. **wterm owns terminal emulation and rendering** by default in WKWebView and Cast. The DOM renderer (`@wterm/dom`) is the baseline and the production core is `@wterm/ghostty` with a 16 MiB scrollback budget; the built-in `@wterm/core` remains the lightweight preview/fallback core.
5. **wterm sits behind a `TerminalEngine` adapter** implementing the current `wanix-term` contract. Wanix is not forked.
6. **Wanix remains the authoritative live shell.** The `#task/shell/term` PTY is the product terminal. `@wterm/just-bash` is an offline/local shell adapter and demo fallback, not a replacement for Wanix and not an automatic silent fallback.
7. **SSH uses a transport, not the renderer.** `WebSocketTransport` or an equivalent backend is permitted only after the ADR-005 authenticated `wss` and certificate gates pass. No SSH keys or credentials are bundled into the web shell.
8. **`@wterm/ghostty` is the production core.** The built-in core failed the 5,000-line scrollback gate, so Ghostty is shipped locally with an explicit byte budget. The added 598 kB WASM asset is accepted pending the remaining conformance, memory, and Cast gates.
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
| `@wterm/ghostty` | `0.5.7` | Apache-2.0 | `sha512-shvpcqzIaz5QuLoTqZ0miotG9GU6/cWPm/7ntjwylhozDRX+wt7DYwvXQenJJ2WtaSSn+wmoMJYplHXDFLjHIQ==` |

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
- Added production integration and made WinBox the default. `index.html` loads `window-manager.js` and `window-manager.css`; `?windowManager=legacy` or `airdesk.window-manager=legacy` opts back into the legacy manager.
- The production path keeps `desktop.js` app, Dock, and menu state while delegating window creation, focus, z-order, drag, resize, minimize/maximize, and close to WinBox. Compatibility classes preserve the existing `.window` and `.window-body` app/CSS contracts.
- Native protocol pointer events are converted to synthetic pointer plus mouse-compatibility DOM events for WinBox, whose upstream drag path listens for mouse/touch input. The default production XCUITest now covers native drag; physical device drag and long-press still require verification.
- The debug `-AirDeskWinBoxDesktop` route loads the production `index.html` with an explicit WinBox override. The production XCUITest exercises the default path without an override and covers maximize, restore, close, and native drag.
- Hidden desktop WebViews can report `window.innerWidth` as `2` or `10` before the preview surface is attached. Initial windows use `window.screen` dimensions as a fallback viewport instead of opening at that zero-width layout, and the production resize path refreshes WinBox bounds once the real viewport is visible.
- WinBox can retain a stale internal root width after a hidden or late layout. Maximize now dispatches a viewport refresh, then explicitly reprojects the maximized bounds from the live viewport when WinBox's calculated size is smaller. The UI test polls through WinBox's 300 ms size transition instead of reading the frame immediately after the tap.
- Rotation and inset changes reproject non-maximized window origins back inside the visible area through `clampToViewport()`, covered by the window-manager unit test.
- The production adapter bundle is 32.8 kB JS with 8.1 kB CSS. No fork is required.
- Full local verification passes: 37 web tests across 7 files, 99 iOS unit tests, 9 iOS UI tests, 6 Rust tests, and `npm run check`.
- Upstream distribution sizes are 11.0 kB for minified JS and 4.8 kB for CSS; the bundled preview build is 16.0 kB.
- License text and attribution are recorded under `third_party/winbox/`.

Still pending before Trial: WKWebView/Cast 60 FPS measurement at 1080p, safe-area/rotation/external-display checks, physical native pointer and long-press regressions, VoiceOver/accessibility review, visual screenshots, signed-app network-disabled packaging, and the category-D parity harness (the simulator harness now covers the adapter lifecycle path).

### wterm

- Package metadata, licenses, and integrities were verified for wterm `0.5.7` and just-bash `3.6.0`.
- Wanix `0.4.0-rc2` is now vendored instead of loaded from jsDelivr. Runtime JS (`sha256 9c0c9f19806b578faf4f9fb15f63d1d1e4ee275a3f056b1a63df42093d1cd47b`), kernel WASM (`sha256 d84e0502d23fb97a45dedf1fd9501c5b58063d464e385679d49c3bd8611f7b86`), and rc shell WASM (`sha256 d37d17954d57267efa9e812b1b7b659c017a508828dddfcdf7ac5b9b60ad8cca`) live under `DesktopShell/wanix/`, with MIT attribution under `third_party/wanix/`. The production desktop and live-kernel route no longer require network access to start Wanix.
- All four desktop pages now carry a restrictive CSP: local scripts and WASM only, local styles, data/blob images, local/blob workers, and no object/form/base targets. `script-src` includes `'unsafe-eval'` because Wanix's Go runtime constructs functions dynamically. Wanix also injects its Go/TinyGo `wasm_exec` glue as an inline script, so the policy allows the two exact runtime hashes (`sha256-a5qOmWtV4zivHG9TzYCcBDIYXWtamE0rSi+b/aPFeYw=` and `sha256-vWvTHbd5URFC6ZXdJfBcriueY7hIyWP2o0+8ycL5u40=`) instead of `'unsafe-inline'`. The live-kernel bootstrap moved out of an inline script, and no remote origins are allowed.
- The documented architecture provides a DOM renderer with native selection, copy/paste, search, accessibility, OSC 8 links, pluggable cores, and an inlined approximately 26 kB Zig/WASM VT core.
- `@wterm/just-bash` depends on `just-bash ^3.4.2`; the selected peer pin is `3.6.0`.
- `@wterm/core`, `@wterm/dom`, and `@wterm/ghostty` are production dependencies. `@wterm/just-bash` and `just-bash` are development dependencies for the offline debug spike, not the production Wanix shell.
- Added a `TerminalEngine` contract and a `WTermEngine` adapter. The adapter queues output until initialization, maps user input to the transport, forwards applied resize dimensions, and keeps remote input out of synthesized DOM events.
- Three headless tests exercise the real `BashShell`: virtual-file `cat`, `cd`/`pwd`, and the `wterm-ok` self-test marker.
- Twelve headless conformance tests exercise both the real `WasmBridge` and real `GhosttyCore`: wide/CJK/emoji/combining/Devanagari/Arabic clusters, alternate-screen restore, scrollback retention/accounting, bracketed paste, mouse/SGR, focus events, application cursor keys, synchronized output, title OSC, palette and true-color SGR, and resize retention. Core-specific expectations cover palette representation and scrollback discard behavior.
- The built-in core retains 1,000 scrollback lines and reports discarded history. The production path no longer uses it for the Wanix terminal.
- `@wterm/ghostty@0.5.7` is now the production core with a 16 MiB `scrollbackLimit`. A 6,000-line headless test at 80 columns retains at least 5,000 lines with zero discarded, so the 5,000-line gate is met for the production core. The packaged WASM is 597,635 bytes and bundled locally as `terminal-core.wasm`.
- Ghostty runs the same parameterized VT matrix as the built-in core, plus a dedicated 5,000-line scrollback gate at 80 columns.
- A debug-only `-AirDeskWTermPreview` route loads a real `WTerm` with `BashShell` and just-bash in WKWebView. The preview auto-runs `echo wterm-ok` and verifies the rendered output through `readText()`.
- The simulator XCUITest passes the `-AirDeskWTermPreview` route and waits for the rendered self-test marker.
- The debug bundle is 2.1 MB unminified with a 57.4 kB CSS bundle. This is not a production size measurement; the preview includes the full just-bash environment.
- just-bash's browser bundle imports an unused `node:zlib` path. The build aliases it to a local shim; gzip is intentionally unavailable in the offline shell.
- Initializing the preview while its sheet is hidden produced a one-column auto-sized grid. The harness uses an explicit 80x24 grid until the surface is visible. The production adapter must initialize after the surface has a real size or re-fit on visibility.
- Added a production terminal path behind `?terminal=wterm` or `airdesk.terminal=wterm`. It lazily loads a 328.1 kB JS / 10.4 kB CSS bundle plus the 598 kB Ghostty WASM asset, waits for the Wanix task PTY, opens `${task.term}/data` read/write streams, and keeps `wanix-term` as the default until conformance passes.
- The WTerm adapter preserves the desktop's `_term` focus/input/paste compatibility hooks, and `desktop.js` now recognizes both `wanix-term` and `.wterm-term`.
- A `-AirDeskWTermDesktop` route drives the production shell with wterm. Its XCUITest verifies engine selection, Ghostty core selection, live Wanix PTY attachment, and keyboard typing through the native bridge.
- The shell now forwards WTerm resize dimensions to `#task/shell/term/winch` as `"<cols> <rows>\n"`. Wanix currently broadcasts that signal but upstream's rc design notes leave signal/resize handling unimplemented, so no running program consumes it yet. Real PTY resize remains blocked on an upstream Wanix/rc change; reconnect/replay semantics also remain unverified.
- SSH transport and the default cutover remain incomplete. The status remains **Proposed**.

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
- No runtime CDN is required for Wanix, wterm, just-bash, fonts, or cores.
- The adopted `@wterm/ghostty` core passes the same conformance matrix and keeps its measured size within the agreed bundle/memory budget.

## Consequences

- AirDesk stops owning fragile window geometry and terminal parsing code.
- wterm remains the primary terminal stack; its production core is now Ghostty, while a standalone Ghostty terminal is still not the default path.
- just-bash provides an offline demo and test shell, but it is not a general POSIX environment, a Wanix replacement, or a network client.
- SSH remains a transport product, not a renderer feature; it cannot ship before authenticated remote transport exists.
- Two mature libraries enter the production surface, with new pins, upgrades, and qualification work.
- The compositor migration temporarily carries both implementations and a rollback flag.
- WinBox’s DOM ownership may force a thin fork; that fork becomes a maintained asset and must be tracked as a supply-chain item.
- wterm is still pre-1.0; its xterm and Ghostty-core compatibility is not assumed, so the adapter and conformance suite are mandatory.
- ADR-002 remains valid for native trackpad gestures and TypeScript tooling, but its web window-manager decision is replaced once this ADR is accepted.
