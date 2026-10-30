# ADR-006: Seamless remote windowing and application remoting

- **Status:** Proposed — post-MVP, qualification spikes required
- **Date:** 2026-10-29
- **Scope:** Windows/Linux/macOS application remoting, remote window integration, decode paths, remote-host security
- **Supersedes:** None
- **Related:** ADR-001, ADR-003, ADR-004, ADR-005, ADR-007, ADR-008

## Decision

Remote windowing is a **post-MVP phase**. It must not block the local Wanix runtime, native external display, transport, WinBox, wterm, or input-protocol work.

When it enters scope:

1. **Windows and RAIL-capable Linux hosts:** use IronRDP RAIL + EGFX for individual application windows.
2. **iOS client:** run the IronRDP core as native Rust through UniFFI.
3. **Cast/browser client:** use `ironrdp-wasm` in the web runtime.
4. **Decode:** VideoToolbox on iOS; WebCodecs in Cast/browser; server-side JPEG/VP8 fallback only if the H.264 path cannot meet the budget.
5. **Linux fallback:** integrate Xpra seamless first because it is operationally simpler. Treat patched `wslg` + FreeRDP as a later spike, not an initial dependency.
6. **macOS:** use a ScreenCaptureKit host with AirDesk’s own per-window metadata and input protocol. Sill is a reference implementation, not an embedded dependency.
7. **Presentation:** remote windows are ordinary `DesktopWindowManager` windows with a remote surface, not a single full-screen remote desktop.

No remote host implementation ships inside the AirDesk client. Remote backends are separate services or host agents.

## Client architecture

### Windows and RAIL

- IronRDP provides the RDP connection, RAIL window channel, and EGFX surface channel.
- The native Rust core exposes session, window, surface, and input APIs through UniFFI.
- The web client uses `ironrdp-wasm` only in Cast/browser contexts.
- The client maps RAIL `windowId` to an AirDesk window identity and EGFX `surfaceId` to that window’s drawable surface.
- Surface acknowledgment must pace the server encoder without blocking input dispatch.
- RAIL window create, show, move, resize, minimize, maximize, restore, and close must map to the compositor lifecycle.
- The web canvas must release all pressed inputs on blur or focus loss.

### EGFX decode

- iOS uses VideoToolbox for H.264 decode where available.
- Cast/browser uses a Web Worker plus WebCodecs for EGFX decode; decode must not run on the main thread.
- A server-side JPEG/VP8 surface path is a qualification fallback, not the default.
- The decoder path must preserve the `enable_server_pointer` behavior required by the selected IronRDP version.
- Main-thread stalls, dropped frames, and input starvation are release-blocking.

### Linux fallback

Xpra is the first Linux seamless backend:

- Run Xpra server-side only, under the GPLv2+ server-side boundary in ADR-003.
- Use Xpra’s seamless window model to enumerate and control application windows.
- Start with the HTML5 client in the web runtime as the integration reference; build a thin AirDesk adapter if native integration is required.
- Do not bundle GPL Xpra code into the iOS client.

Patched `wslg` + FreeRDP remains a later spike:

- Pin the exact Weston/FreeRDP fork and patches, including the WSLg issue #1501 fixes.
- Build reproducibly and record patches in the SBOM.
- Do not promote it until RAIL windows appear reliably and the patch set is either upstreamed or maintained as a documented fork.
- It is server-side only.

### macOS

- A macOS host agent captures individual windows with ScreenCaptureKit.
- AirDesk defines its own window metadata, z-order, geometry, focus, and input messages; RDP is not required for macOS.
- Input injection uses the macOS accessibility APIs with explicit user permission.
- Sill informs the capture/input architecture but is not a runtime dependency.
- The host must handle display sleep, window destruction, secure input fields, and screen-recording permission revocation.

## Display integration

- Remote windows participate in the same focus, z-order, minimize, maximize, and close model as local windows.
- Window identity must be stable across reconnects and generation changes.
- Remote window titles and app identity are untrusted strings and must be bounded and sanitized.
- On disconnect, remote windows are marked disconnected, inputs are released, and stale surfaces are discarded.
- The compositor must distinguish local and remote window ownership for diagnostics.
- A remote full-screen desktop is not a substitute for per-window remoting and must not be presented as seamless mode.

## Security

- Credentials are handled in native Rust or the secure platform store; they are never exposed to the web shell.
- NLA/CredSSP is expected to use an RDCleanPath-style proxy where required, with certificate validation and no silent trust bypass.
- Remote hosts authenticate with short-lived session tokens; tokens are bound to session generation and transport.
- Clipboard, file transfer, audio, and drive redirection are off by default until separately reviewed.
- Remote window metadata is validated like any other untrusted network input.
- A remote disconnect or canvas blur must release all keys and buttons to prevent stuck input.
- Transport security follows ADR-005; no plaintext remote session is permitted.

## Qualification gates

### Windows / IronRDP

- RAIL window creation, mapping, movement, resize, minimize, maximize, close, and z-order pass against a real Windows host.
- EGFX surface mapping and acknowledgment work for multiple simultaneous windows.
- 1080p30 video and normal desktop interaction meet the ADR-005 latency budgets without starving input.
- Native iOS and WASM Cast clients share the same conformance suite where behavior overlaps.
- The selected IronRDP version is pinned and its known issues are recorded.

### Linux / Xpra

- Seamless window enumeration, geometry updates, focus, and close pass against a real Xpra host.
- GPL server-side distribution boundary and source-offer obligations are documented.
- The HTML5 integration spike proves whether a native adapter is needed.

### Linux / wslg

- The pinned fork builds reproducibly.
- RAIL windows appear, map, and receive input.
- The C-level patches are documented and either upstreamed or carried with an owner and review date.

### macOS

- Per-window capture, resize, minimize, focus, and input injection pass with screen-recording and accessibility permissions.
- Secure input fields and permission revocation fail safely.
- Window z-order and app identity remain stable across reconnects.

## Consequences

- Remote windowing stays out of the critical path until the local product is stable.
- Native Rust and WASM clients increase test matrix; shared Rust core and conformance suites limit divergence.
- Xpra first reduces Linux integration risk but introduces a GPL server-only component and a separate seamless model.
- wslg remains high-risk and may never be promoted; that is acceptable.
- macOS requires a separately distributed host agent with OS permissions, not just a client-library integration.
- Remote window security, credential handling, and clipboard policy need dedicated review before any commercial release.
