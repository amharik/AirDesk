# ADR-005: Display profiles, transport, and wire framing

- **Status:** Proposed — hardware and latency qualification required
- **Date:** 2026-10-29
- **Updated:** 2026-11-03 — display endpoints separated from workspace authority
- **Updated:** 2026-11-03 — peer review: Cast message pacing and payload fragmentation limits
- **Scope:** USB-C/AirPlay external displays, Cast receiver, browser and TV endpoints, controller mode, transport, binary framing, latency targets
- **Amends:** ADR-001 display sequencing and transport details; Cast remains receiver-hosted but not workspace-authoritative
- **Supersedes:** None
- **Amended by:** ADR-013 (transport planes), ADR-014 (browser endpoint), ADR-016 (workspace authority), ADR-017 (orchestration)
- **Related:** ADR-001, ADR-003, ADR-004, ADR-008, ADR-010, ADR-013, ADR-014, ADR-016, ADR-017

## Decision

Adopt four explicit display modes and prioritize the native external-display path first.

1. **Mode A — Independent external desktop:** the phone runs the controller while the external display presents the desktop. USB-C is the primary target; AirPlay is supported only where the OS and display path actually permit an independent scene.
2. **Mode B — Mirrored presentation:** used when the OS or display route only supports mirroring. The UI must say so and must not imply an independent desktop.
3. **Mode C — Cast desktop:** the receiver hosts an approved runtime provider and presents the workspace. Cast custom messaging is tried first; authenticated LAN `wss` is the fallback. The receiver is not the workspace authority.
4. **Mode D — Controller/disconnected:** setup, diagnostics, and recovery when no display path is active.

USB-C/AirPlay is the first native milestone. A browser endpoint follows the personal device fabric, not the first workspace release. Cast remains receiver-hosted and supported, but follows the native external-display path rather than defining the MVP sequence.

The modes are presentation outcomes, not a second profile model:

| ADR-005 mode | ADR-001 profile | Note |
| --- | --- | --- |
| Mode A | iOS extended | Independent external scene |
| Mode B | iOS mirrored | Mirrored scene only |
| Mode C | Cast | Receiver hosts a runtime provider; workspace remains independent |
| Mode D | None / preview or disconnected | Controller, setup or recovery |

`ProfileResolver` remains the authority for the profile axes; the mode resolver reports the local presentation outcome.

### Display sessions do not own the workspace

- A workspace may have zero, one or many display sessions.
- A display session stores presentation state, focus and controller attachment.
- Window layout preferences may be persisted by the workspace; transient display state is session-scoped.
- A display reconnect must not recreate or overwrite the workspace.
- A browser, TV or Cast endpoint cannot become the canonical workspace owner.
- Closing a display session does not stop unrelated runtimes or delete application definitions.

## Display rules

- External display presentation uses a `UIWindowScene`, not global `UIScreen` assumptions.
- The phone scene owns the controller UI; the external scene owns the desktop surface where independent mode is supported.
- The coordinator must verify the resolved mode at runtime and report it truthfully.
- On disconnect, cancel active drags, clear pressed modifiers, stop cursor motion, and move to Mode D or the selected fallback.
- A Cast session must not also start a local runtime on the phone.
- A mirrored session must not claim independent-window capability.
- AirPlay independent-display support is a qualification item, not an assumption.

## Transport baseline

Adopt **WebSocket + WebRTC data channel** as the transport baseline.

- **WebSocket** carries control, capability negotiation, fallback input, remote sessions, and WebRTC signaling.
- **WebRTC data channel** is used for direct LAN input when ICE succeeds. It is not used inside the Cast receiver because the Cast Chromium sandbox is reported to block local ICE host candidates.
- **Cast custom messaging** is the primary Cast input path. It is text-only and uses a compact JSON profile with pointer coalescing.
- **Cast pacing and fragmentation:** Cast messages are bounded to the receiver's documented payload size and rate. Larger payloads are fragmented with sequence and reassembly metadata; a slow or stalled receiver causes production to pause, not to drop input or grow an unbounded queue.
- **QUIC** is deferred until a measured need justifies another transport.
- All transports share one logical message model and session/generation/sequence rules; transport choice must not change input semantics.

### WebRTC channels

Use two data channels when WebRTC is active:

- `control`: reliable and ordered, for lifecycle and control messages.
- `input`: unreliable and unordered, with retransmits disabled, for pointer deltas and other latency-sensitive input.

Control messages must not be sent on the unreliable channel. Input frames must be safe to drop or reorder according to sequence rules.

## Wire format

Adopt a hybrid framing model:

- **Pointer input:** a packed, fixed-layout binary frame with a versioned envelope, session/generation identifiers, sequence number, event type, flags, timestamp, and pointer payload.
- **Control/window metadata:** FlatBuffers with a versioned schema.
- **Cast:** a compact JSON profile using the same logical fields; binary framing is not forced through a text-only Cast channel.
- **WebSocket and WebRTC:** binary frames for production input; JSON only for diagnostics or Cast compatibility.
- **rkyv:** not used as a cross-language wire format. It may remain an internal Rust optimization only.

ADR-008 owns the canonical event list and semantic validation. ADR-005 owns the transport envelope and frame encoding.

## Latency target

- **LAN, including Cast when it meets the budget:** 50 ms p95 from controller input timestamp to applied pointer position.
- **Remote sessions:** 100 ms p95.
- Local gesture processing and dispatch targets are defined with the input protocol in ADR-008.

Instrumentation must record the controller timestamp and the display-side application time. Averages are not sufficient; qualification uses p95 and p99 over a defined scenario.

## Security

- A LAN WebSocket fallback must use `wss://` with a trusted certificate and a short-lived 256-bit session token. Plain `ws://` is prohibited.
- Pinned self-signed certificates are not the baseline. A trusted-certificate provisioning strategy is required before the wss fallback can be promoted.
- WebRTC signaling runs over the authenticated WebSocket. DTLS protects the data channel; token and origin checks still apply.
- Cast custom messages must validate session, generation, origin, message size, and token freshness.
- iOS local-network permission and Cast receiver origin restrictions must be handled explicitly.
- No transport may load executable code from a remote origin.

## Acceptance gates

- USB-C and AirPlay scene attach/detach passes on hardware, with truthful independent-versus-mirrored reporting.
- External-display input coordinates and disconnect cleanup pass the existing P0 regressions.
- Cast hardware confirms whether custom messaging meets 50 ms p95; otherwise the authenticated wss fallback is used.
- The Cast receiver never starts a second local runtime.
- Cast payloads stay within the receiver's size and rate limits; oversized payloads fragment and reassemble, and a stalled receiver pauses production without dropping input.
- WebRTC direct LAN succeeds where ICE is available and falls back cleanly to WebSocket when it is not.
- WebRTC is not attempted inside the Cast receiver.
- Packed pointer frames and FlatBuffers control messages round-trip across Swift, TypeScript, and Rust, with malformed-frame rejection.
- No plaintext `ws://` path exists, and the trusted-certificate strategy is documented.
- p95/p99 measurements are recorded for USB-C, AirPlay, Cast, WebRTC LAN, wss LAN, and remote WebSocket.

## Consequences

- Native external display becomes the first commercial display milestone; Cast remains supported but is no longer the sequencing anchor.
- WebRTC adds signaling, ICE, and dual-channel complexity, but provides a direct LAN path outside the Cast sandbox.
- The trusted-certificate requirement for LAN wss may force a relay or certificate-provisioning design; the fallback must not silently downgrade to plaintext.
- FlatBuffers adds schema generation and cross-language build steps.
- Cast’s text-only channel requires a separate compact JSON profile, which must be tested for semantic drift against the binary protocol.
- QUIC remains an option without expanding the initial transport matrix.
