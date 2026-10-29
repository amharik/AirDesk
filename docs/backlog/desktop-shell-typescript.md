# DesktopShell TypeScript migration backlog

- **Status:** Proposed — not started
- **Date:** 2026-10-29
- **Related:** ADR-002
- **Goal:** Make DesktopShell modules typed, testable, and buildable without changing the native message contract or visual design.

## Current state

| File | Lines | Role |
|---|---:|---|
| `desktop.js` | 1,586 | desktop shell, windows, pointer/drag, menus, spotlight, keyboard |
| `apps.js` | 759 | app definitions and content |
| `wanix-shell.js` | 355 | Wanix terminal integration |
| `wanix-live.js` | 277 | live desktop bootstrap |
| `bridge.js` | 200 | native bridge protocol |
| `wanix-file-worker-fix.js` | 110 | worker compatibility shim |
| **Total JS** | **3,287** | no modules, no types, no tests |

## Target layout

```text
web/
  package.json
  tsconfig.json
  src/
    desktop/
      main.ts
      shell.ts
      windows.ts
      pointer.ts
      drag.ts
      menus.ts
      spotlight.ts
      keyboard.ts
      apps.ts
      wanix/
        shell.ts
        live.ts
        file-worker-fix.ts
      bridge/
        protocol.ts
        bridge.ts
      shared/
        dom.ts
        geometry.ts
        types.ts
  test/
    pointer.test.ts
    drag.test.ts
    bridge.test.ts
```

Built output remains in `AirDesk/Resources/DesktopShell/` so the iOS app keeps loading local files with no CDN or runtime network dependency.

## Phase 0 — Stabilize current input (blocking)

- [x] Capture device watchdog logs: touch-and-hold ended in `0x8BADF00D` scene-update watchdogs while SwiftUI was updating the view graph.
- [x] Fix the drag update loop: drag state is no longer published app-wide, `dragMode` only reacts to real changes, and `endDrag` resets to idle.
- [x] Reproduce icon click failure: `#window-layer` covered the icons with pointer events; it now passes clicks through while windows remain interactive.
- [x] Remove snap-on-move and harden click coordinates so missing coordinates keep the last pointer position instead of jumping to `0,0`.
- [x] Add regressions for desktop-icon clicks and trackpad long-press.
- [x] Re-run simulator unit, integration, and UI suites.
- [ ] Device smoke test after the next signed Xcode build (`Cmd+R`).

Implemented in `8a139d0`.

**Exit:** no freeze/crash on press-and-hold, icon click activates at cursor location, existing typing tests pass.

## Phase 1 — Toolchain

- [x] Add `web/package.json` with `typescript`, `esbuild`, `vitest`, `eslint`.
- [x] Add strict `tsconfig.json` (`strict`, `noUncheckedIndexedAccess`, `noImplicitOverride`).
- [x] Add `build` script emitting IIFE bundles with source maps.
- [x] Add `check` script running `tsc --noEmit`, ESLint, tests, and the bundle freshness check.
- [x] Add CI job verifying committed output matches `web/src`.
- [x] Document the build in `README.md`.

**Exit:** `npm run build` reproduces the committed bundle; Xcode build requires no Node install.

## Phase 2 — Protocol types first

- [~] Define bridge `InputEvent`, `ControlMessage`, and API types in `web/src/bridge/types.ts`; move shared state/window/runtime types next.
- [x] Type `bridge.js` first; keep runtime behavior unchanged.
- [~] Type the bridge payloads and validate incoming messages with a small runtime guard; type remaining DesktopShell payloads next.
- [x] Add contract tests for generation/session gating and malformed messages.
- [ ] Generate Swift-side constants or a shared schema document so native and web cannot drift.

**Exit:** bridge and native input messages are type-checked; no behavior change.

## Phase 3 — Pointer and drag split

- [ ] Extract `moveCursor`, hit-testing, click, hover, and snapping into `pointer.ts`.
- [ ] Extract window move/resize lifecycle into `drag.ts` with explicit `idle -> pressed -> dragging -> ended` states.
- [ ] Remove per-move DOM queries; cache hit targets only for the duration of a gesture.
- [ ] Add unit tests for coordinate normalization, bounds clamping, and drag math.
- [ ] Add WKWebView integration test: bridge pointer sequence moves a real `.window`.

**Exit:** drag math is unit-tested; no global snapping on every move.

## Phase 4 — Shell/window modules

- [ ] Split `desktop.js` into `shell`, `windows`, `menus`, `spotlight`, `keyboard`.
- [ ] Keep CSS selectors and DOM structure stable.
- [ ] Add typed window manager interface (`open`, `focus`, `move`, `resize`, `close`, `restore`).
- [ ] Add tests for focus order, z-index, minimize/restore.
- [ ] Benchmark startup and pointer latency before/after.

**Exit:** `desktop.js` entry point is under 150 lines and only wires modules together.

## Phase 5 — Apps and Wanix adapters

- [ ] Type `apps.ts` app definitions.
- [ ] Type Wanix terminal and live-shell adapters.
- [ ] Keep worker compatibility shim isolated and documented.
- [ ] Add tests for terminal text input and keyboard routing through the bridge.

**Exit:** all DesktopShell JS is authored in TypeScript.

## Phase 6 — Gesture library integration (after ADR decision)

- [ ] Add the chosen trackpad gesture implementation (native recognizers first).
- [ ] If Option 2: add `interact.js` adapter for window drag/resize only.
- [ ] Keep a feature flag to fall back to the typed custom controller.
- [ ] Add device tests for one-finger move, tap, double-tap drag, three-finger drag, two-finger scroll, and cancellation.
- [ ] Remove the losing implementation after one release of validation.

**Exit:** ADR-002 decision implemented, flags removed, device validation recorded.

## Acceptance criteria

1. No crash or main-thread freeze during 100 press-and-hold cycles.
2. Icon tap activates the icon under the visible cursor; cursor never jumps to `0,0`.
3. Window drag works with physical mouse, virtual trackpad drag mode, and three-finger drag.
4. Terminal and Notes accept physical and virtual keyboard input.
5. `tsc --noEmit`, unit tests, UI tests, and device build pass.
6. Committed web bundle is reproducible from `web/src`.

## Risks

- `interact.js` is maintenance-only; pin an exact version and keep the adapter thin.
- WKWebView synthetic pointer events may not match browser behavior; validate on device, not only simulator.
- Committing built artifacts can drift; CI must fail when source and output differ.
- A parallel TS rewrite risks behavior drift; migrate module-by-module behind unchanged entry points.
