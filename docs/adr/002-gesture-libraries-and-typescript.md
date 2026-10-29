# ADR-002: Replace custom gesture/input stack and migrate DesktopShell to TypeScript

- **Status:** Accepted — implementation deferred until P0 stabilization
- **Date:** 2026-10-29
- **Scope:** iOS/iPadOS trackpad input, WKWebView desktop pointer/window interaction, DesktopShell build tooling
- **Supersedes:** None
- **Related:** ADR-001, `docs/backlog/desktop-shell-typescript.md`

## Decision

Adopt **Option 2 — Hybrid**: Apple `UIGestureRecognizer`/`UIScrollView` for the iPad trackpad, and `interact.js` behind a narrow adapter for web window drag/resize/snapping. Migrate DesktopShell to TypeScript with `esbuild` and `tsc --noEmit`.

No code changes are approved by this ADR yet. The P0 stabilization items below must ship first, and the existing custom input path stays in place until the library adapter is validated on device.

Previous alternatives considered:

1. **Native-first:** Apple `UIGestureRecognizer`/`UIScrollView` for the iPad trackpad, and keep a small, typed, DOM pointer controller in the web shell.
2. **Hybrid (selected):** native-first trackpad + `interact.js` behind an adapter for window drag/resize/snapping in the web shell.
3. **Web-gesture:** native-first trackpad + `@use-gesture/vanilla` for web gestures.
4. **Window-manager replacement:** adopt `WinBox.js` or similar for desktop windows.
5. **No new runtime library:** native-first + TypeScript-only rewrite of the current custom logic.

## Context

The current input path has accumulated custom gesture, pointer, snapping, drag, keyboard, and routing logic across Swift and JavaScript. The latest change set introduced unacceptable regressions on device:

- Touch-and-hold freezes the app and then crashes it.
- Tapping a desktop icon moves the cursor to the top-left (`0,0`/`1,1`) and the click does not activate the icon.

These are release-blocking regardless of which library is chosen. The regression surface includes:

- `MacTrackpadUIView` custom `touchesBegan/Moved/Ended` state machine.
- New latching `dragMode` path.
- `snapCursor` running DOM queries and geometry reads on every pointer move.
- `moveCursor`/`clickAt` coordinate handling between native `PointerState`, `InputDispatcher`, `bridge.js`, and `desktop.js`.

The JS shell is also difficult to reason about:

- `desktop.js` is 1,586 lines in a single IIFE.
- `apps.js` is 759 lines, `wanix-shell.js` 355 lines, `bridge.js` 200 lines.
- No module boundaries, no types, no unit-test harness, no linting, no bundler.
- Native and web contracts are implicit string messages, so regressions cross language boundaries silently.

## Decision drivers

1. Device reliability and crash-free touch handling.
2. Predictable click coordinates and drag lifecycle.
3. Small dependency surface; no CDN/runtime downloads inside WKWebView.
4. Maintained, licensed (MIT/Apache-2.0), TypeScript-friendly dependencies.
5. Testability in simulator and on device.
6. Ability to keep the existing desktop visual design and Wanix integration.
7. Incremental migration without a flag-day rewrite.

## Research snapshot (2026-10-29)

### Web drag/resize candidates

| Candidate | Fit | Maintenance signal | Notes |
|---|---|---|---|
| `interact.js` | High | ~12.9k stars; maintenance-only, no release in 24 months, last push ~88 days | Drag, resize, multi-touch, inertia, snapping/restrict modifiers; no DOM movement by default; TypeScript types. Best functional fit, but release cadence is a risk. |
| `@use-gesture/vanilla` | Medium | ~9.6k stars; no human commit in ~910 days; latest 10.3.1 | Good pointer gesture abstraction, but vanilla package is much less used than React; no release cadence. |
| `Draggabilly` | Low/medium | ~3.9k stars; last push 2022 | Drag only; no resize/snapping; Safari 14+. Too narrow. |
| `WinBox.js` | Medium/high only if replacing windows | ~6.5k stars; Apache-2.0 | Full HTML5 window manager. Replacing the shell would be a larger product/UI migration than an input fix. |
| `dockview` | Low for this use | ~3.5k stars; active | Docking/tab layout manager, not floating desktop windows. |
| `Golden Layout` | Low for this use | ~6.7k stars; older architecture | Layout/docking, not macOS-style floating windows. |

### Native iOS gesture candidates

| Candidate | Fit | Notes |
|---|---|---|
| Apple `UIGestureRecognizer` subclasses + `UIScrollView`/`UIPanGestureRecognizer` | High | No dependency; Apple-supported; explicit state, cancellation, simultaneous-recognition delegates, velocity, multi-touch counts. Recommended for the trackpad. |
| `UIKitGesturesForSwiftUI` | Low | New (1.0.0), ~14 stars, iOS 18+/Swift 6, small adoption. Not appropriate for a reliability fix. |
| `TransformGesture` / `Gestures` | Low | Niche SwiftUI conveniences; do not solve the native trackpad state machine or WKWebView bridge contract. |

### TypeScript/bundling

- `TypeScript` + `esbuild` is the lowest-friction path for a WKWebView: `platform: "browser"`, `format: "iife"`, single-file outputs, source maps, fast builds.
- `tsc --noEmit` remains the type checker because esbuild does not type-check.
- Recommended output policy: commit built JS into `AirDesk/Resources/DesktopShell/` and verify in CI that `src` and committed output match. This keeps Xcode builds independent of a local Node install.
- Tests: `vitest` for pure TS modules (input state, coordinate mapping, snapping, window drag math) and the existing `WKWebView` integration harness for bridge/DOM behavior.

## Options

### Option 1 — Native-first, no new web runtime library

- Trackpad: replace custom touch state machine with `UITapGestureRecognizer`, `UIPanGestureRecognizer` (one finger), `UIPanGestureRecognizer`/`UIScrollView` (two finger), `UILongPressGestureRecognizer` + pan (drag), and explicit `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`.
- Web shell: keep a typed pointer/drag controller; remove global snap-on-every-move and replace with target-local CSS/geometry snapping.
- Pros: smallest dependency surface; Apple-supported gestures; easiest to reason about cancellation and crashes.
- Cons: we still own window drag/resize/snapping math; no third-party test coverage for DOM interactions.

### Option 2 — Hybrid: native-first trackpad + `interact.js` in the web shell (recommended)

- Trackpad as Option 1.
- Use `interact.js` only for `.window` drag/resize and optional snapping/restriction modifiers.
- Keep AirDesk's cursor model and input routing; `interact.js` receives synthetic pointer events only through a dedicated adapter.
- Pros: mature DOM drag/resize behavior; snapping/restrict modifiers; TypeScript types; isolates risky math.
- Cons: maintenance-only upstream; synthetic pointer events into `interact.js` must be validated in WKWebView; larger bundle than custom code.

### Option 3 — Native-first + `@use-gesture/vanilla`

- Pros: clean gesture state API; MIT; TypeScript.
- Cons: stale releases; vanilla package adoption much lower than React; still needs an adapter for the WKWebView input bridge.

### Option 4 — Replace window management with `WinBox.js`

- Pros: battle-tested floating windows, drag/resize/minimize, no custom window chrome math.
- Cons: changes visual DOM and accessibility structure; conflicts with existing Wanix terminal/app embedding and tests; largest migration risk. Not recommended for an input regression fix.

### Option 5 — TypeScript rewrite only, no new runtime library

- Pros: no dependency or license risk; directly addresses maintainability.
- Cons: does not by itself fix gesture reliability; we keep owning the bug-prone state machine.

## Recommendation

Adopt **Option 2 (hybrid)** as selected. Implementation order:

1. Replace the custom trackpad touch state machine with Apple gesture recognizers first.
2. Remove global `snapCursor` from `moveCursor`; snap only at interaction end or within target-local hit regions.
3. Fix the click coordinate contract before adding any library:
   - every `pointerClick`/`pointerDown`/`pointerMove`/`pointerUp` must carry the same normalized cursor position;
   - `clickAt` must not clamp a missing coordinate to `0`;
   - add a regression test that clicks a desktop icon and asserts the activated target.
4. Migrate DesktopShell to TypeScript behind the existing message contract before replacing internal gesture logic.

`interact.js` is preferred over `@use-gesture/vanilla` for this specific use because it directly covers drag, resize, snapping, and restrictions, and it has a larger, longer-lived adoption base, despite its maintenance-only status.

## Immediate stabilization backlog (P0, before library work)

These are proposals for a separate fix PR, not part of the library migration.

1. Reproduce touch-and-hold freeze/crash with a device sysdiagnose and Xcode Organizer crash log.
2. Remove or feature-flag the latching `dragMode` path until the crash is understood.
3. Remove `snapCursor` from the per-move path; make snapping opt-in and bounded.
4. Audit `moveCursor`/`clickAt` coordinate defaults; never allow absent coordinates to become `0,0`.
5. Verify `pointerClick` carries `currentPoint` after any pending move flush.
6. Add UI regression: tap desktop icon -> cursor stays on icon and icon activates.
7. Add UI regression: press-and-hold trackpad -> no freeze, no crash, drag ends cleanly.

## Consequences

- Native gestures reduce the code we own for touch recognition.
- A web drag library adds a dependency and an adapter, but removes fragile window math.
- TypeScript plus a committed bundle adds CI surface but makes the shell testable and reviewable.
- The existing visual design can be preserved; this is not a shell rewrite.

## Decision log

- 2026-10-29: Proposed; research snapshot recorded.
- 2026-10-29: Accepted Option 2 (native trackpad gestures + `interact.js` web adapter). Implementation deferred until P0 stabilization and TypeScript toolchain land.

## References

- `interact.js`: https://interactjs.io/ and https://github.com/taye/interact.js
- `@use-gesture`: https://use-gesture.netlify.app/ and https://github.com/pmndrs/use-gesture
- `Draggabilly`: https://github.com/desandro/draggabilly
- `WinBox.js`: https://github.com/nextapps-de/winbox
- `dockview`: https://github.com/dockview/dockview
- Apple `UIGestureRecognizer`: https://developer.apple.com/documentation/uikit/uigesturerecognizer
- `esbuild`: https://esbuild.github.io/
- TypeScript: https://www.typescriptlang.org/
