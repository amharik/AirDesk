# ADR-027: Standardize on WTerm with the Ghostty WASM core

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** AirDesk terminal and web platform
- **Related:** ADR-003, ADR-007, P4-07, P4-08, P4-09, P4-10

## Context

ADR-007 selected WTerm with `@wterm/ghostty` as the production terminal stack,
but left the decision `Proposed` and required a qualification gate. P4-07 asks
for a benchmark of `libghostty-vt` and `@wterm/ghostty` against the current
engine for size, VT coverage, selection, accessibility and license before any
replacement.

The product terminal runs inside a cross-origin-isolated WKWebView and is also
used by the bundled DesktopShell and preview surfaces. It must remain offline,
must not regress DOM selection or accessibility, and must keep the current
`TerminalEngine` adapter and OSC 133 semantic/agent features.

## Decision

1. **WTerm remains the production terminal.** `@wterm/dom` owns rendering,
   input, native DOM selection, search, clipboard coordination and accessibility.
2. **`@wterm/ghostty` remains the production core.** The pinned 0.5.7 WASM core
   is loaded from the bundled `terminal-core.wasm` with a 16 MiB scrollback
   budget. The built-in `@wterm/core` remains the lightweight fallback/preview
   core.
3. **`libghostty-vt` is not adopted as the browser engine.** Version 0.6.3 is an
   unofficial Bun/native FFI binding (`bun:ffi`, `dlopen`, `JSCallback`) with no
   browser or WASM export, no iOS/WKWebView target, no DOM selection or
   accessibility layer, and an 18 MB unpacked native package. Its inspected
   tarball also omits the binding's Apache-2.0 `LICENSE` file.
4. **No replacement is scheduled.** A future engine change must first satisfy
   the gates in “Consequences” and be recorded in a new ADR.
5. **P4-10 may rely on WTerm's `renderingPaused` API** for inactive-pane
   painting suspension; no terminal-engine replacement is a prerequisite.

## Evidence

The benchmark method, commands and measurements are in
`docs/research/terminal-engine-benchmark-2026-11-12.md`. Key results:

| Measure | WTerm + `@wterm/ghostty` | `libghostty-vt` 0.6.3 |
| --- | --- | --- |
| Browser delivery | 355,162 B JS + 13,537 B CSS + 597,635 B WASM | Native Bun FFI; no browser/WASM export |
| Packaged size | Three Apache-2.0 npm packages | 6.59 MB tarball, 19.08 MB unpacked |
| VT conformance | 12 passing tests across built-in and Ghostty cores | No browser harness; native API only |
| Selection | DOM-native selection and history selection | None provided |
| Accessibility | Labels, input hints, live announcements, DOM text | None provided |
| License | Apache-2.0 with `LICENSE` files | Apache-2.0/MIT metadata; missing binding `LICENSE` in tarball |
| Platforms | WKWebView, DesktopShell, previews | macOS arm64 and Linux; no iOS or darwin-x64 |

The current Ghostty core also retains the 5,000-line scrollback gate with zero
discarded lines and exposes `renderingPaused`, so P4-10 does not need an engine
migration.

## Consequences

- The terminal stack remains WTerm plus the Ghostty WASM core, behind the
  existing `TerminalEngine` adapter.
- `libghostty-vt` remains a research reference only; it cannot be shipped in the
  iOS web surface or used as a replacement for the DOM renderer.
- ADR-007 remains the historical selection record and is amended in practice by
  this standardization decision; its remaining qualification gaps are tracked by
  P4-07/P4-10 rather than by an engine swap.
- A future replacement must provide:
  1. a browser/WASM build with a WKWebView loading path;
  2. DOM selection, clipboard, IME/composition, search and accessibility parity;
  3. VT fixtures matching or exceeding the current two-core matrix;
  4. complete Apache-2.0 and upstream MIT license files;
  5. a measured payload budget against the current baseline;
  6. a production rollback path to `@wterm/ghostty`.
- No Cast, physical-device or performance claim follows from this decision.
