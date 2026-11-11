# Terminal engine benchmark — 2026-11-12

## Question

P4-07 asks whether AirDesk should replace the current WTerm renderer and
`@wterm/ghostty` core with `libghostty-vt`, and what evidence is required before
any replacement.

## Candidates

| Candidate | Version | Role |
| --- | --- | --- |
| `@wterm/dom` + `@wterm/ghostty` | 0.5.7 | Current production renderer and WASM core |
| `libghostty-vt` | 0.6.3 | Unofficial TypeScript binding over native libghostty-vt |

## Method

Commands were run on the macOS verification host on 2026-11-12.

```sh
cd web
node_modules/.bin/vitest run test/wterm-conformance.test.ts test/wterm-ghostty.test.ts

for f in AirDesk/Resources/DesktopShell/terminal.js \
         AirDesk/Resources/DesktopShell/terminal.css \
         AirDesk/Resources/DesktopShell/terminal-core.wasm; do
  stat -f "%z" "$f"
  gzip -9 -c "$f" | wc -c
done

npm view libghostty-vt name version license dist.unpackedSize repository.url
npm pack libghostty-vt@0.6.3
tar -xzf libghostty-vt-0.6.3.tgz
du -sk package
file package/prebuilds/*/*
rg -n "bun:ffi|wasm|window|document" package/dist/index.js
find package -maxdepth 2 -iname "*license*"
```

The web conformance suite exercises both the built-in core and the Ghostty core
against the same six scenarios: wide/emoji/combining/Devanagari/Arabic clusters,
alternate screen, scrollback accounting, bracketed paste/mouse/focus/cursor-key/
title/synchronized-output modes, palette/true-color SGR, and resize retention.

## Results

### Size

| Artifact | Bytes | gzip -9 |
| --- | ---: | ---: |
| `terminal.js` (current production bundle) | 355,162 | 91,275 |
| `terminal.css` (current production bundle) | 13,537 | 3,262 |
| `terminal-core.wasm` (`@wterm/ghostty` 0.5.7) | 597,635 | 196,490 |
| `libghostty-vt` npm tarball | 6,594,867 | — |
| `libghostty-vt` unpacked package | 19,077,833 | — |
| `libghostty-vt` JavaScript | 111,499 | 22,442 |

The current browser payload is about 966 kB uncompressed including the WASM
core. `libghostty-vt` is a 6.3 MB tarball and 18 MB unpacked because it ships
native libraries for six desktop targets, but that native library is not usable
from WKWebView.

### Browser and platform fit

- Current: `@wterm/dom` runs in the browser and `@wterm/ghostty` is loaded as
  `terminal-core.wasm` inside the cross-origin-isolated WKWebView. The committed
  WASM hash is `d8f93f5e38550958f459b34db9c4680bb4a935161a7a75a999d18e392b3c98d8`.
- `libghostty-vt` imports `bun:ffi`, `dlopen` and `JSCallback` from `bun:ffi`.
  Its package declares `"engines": { "bun": ">=1.3.13" }`, has no browser export,
  no WASM target and no iOS/WKWebView target.
- Its prebuilds cover `darwin-arm64` plus Linux glibc/musl on arm64/x64. There is
  no `darwin-x64` build, no iOS build and no browser build.

### VT coverage

- Current: 12 tests pass across the two cores. The Ghostty core covers the six
  scenarios above with zero unhandled sequences for the tested cluster and mode
  inputs, retains at least 5,000 lines without discard at 16 MiB scrollback, and
  supports OSC 133 shell integration through the wterm core.
- `libghostty-vt` exposes a `Terminal`/`RenderState` API with `vtWrite`, resize,
  snapshot, dirty rows/cells, scroll viewport, palette and key encoding. It could
  be assessed with a separate Node/Bun fixture suite, but it cannot run in the
  product web surface without a new browser transport, renderer and input layer.
  No such adapter exists in this repository, and none is provided by the package.

### Selection and accessibility

- Current: WTerm provides DOM-native selection (`getSelectionText`, `selectAll`,
  `selectWord`, `selectLine`, `selectRectangle`, `clearSelection`), accessible
  labels propagated from host elements to the input, an exit-hint live region,
  output announcements, search, and DOM text for assistive technology. The
  DesktopShell terminal is part of the normal DOM and is independently
  accessible.
- `libghostty-vt` provides no DOM, selection model, clipboard integration or
  accessibility tree. Those layers would have to be rebuilt, and no browser
  selection/accessibility tests could be run against its native FFI binding.

### License and distribution

- Current packages: `@wterm/core`, `@wterm/dom` and `@wterm/ghostty` are
  Apache-2.0 and ship a `LICENSE` file; dependency policy passes.
- `libghostty-vt` metadata declares Apache-2.0 for the binding and MIT for the
  redistributed Ghostty binary, but the inspected 0.6.3 tarball contains only
  `LICENSE_GHOSTTY` and no `LICENSE` file for the binding. It also redistributes
  platform native binaries that cannot be used by the iOS app or web surface.
  This is a distribution/license gate, not merely a bundle-size concern.

## Decision

Retain WTerm plus the `@wterm/ghostty` WASM core. Do not adopt
`libghostty-vt` as the browser terminal engine. Record the decision in
ADR-027.

## Follow-up gates for any future replacement

1. A browser/WASM build with a supported WKWebView loading path.
2. A DOM adapter with selection, clipboard, IME/composition, search and
   accessibility parity.
3. VT conformance fixtures matching or exceeding the current two-core matrix.
4. Full Apache-2.0 and upstream MIT license files in the distributed package.
5. A measured payload budget against the current 355 kB JS + 13.5 kB CSS +
   598 kB WASM baseline.
6. A rollback path that keeps `@wterm/ghostty` selectable in production until
   the replacement passes the browser, Cast and iOS gates.
