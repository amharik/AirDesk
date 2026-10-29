# ADR-005: Display profiles, transport, and wire framing

- **Status:** Proposed — hardware and latency qualification required
- **Date:** 2026-10-29
- **Scope:** USB-C/AirPlay external displays, Cast receiver, controller mode, WebSocket/WebRTC transport, binary framing, latency targets
- **Amends:** ADR-001 Cast-first MVP sequencing and transport details; Cast remains receiver-hosted
- **Supersedes:** None
- **Related:** ADR-001, ADR-003, ADR-004, ADR-008

## Decision

Adopt four explicit display modes and prioritize the native external-display path first.

1. **Mode A — Independent external desktop:** the phone runs the controller while the external display presents the desktop. USB-C is the primary target; AirPlay is supported only where the OS and display path actually permit an independent scene.
2. **Mode B — Mirrored presentation:** used when the OS or display route only supports mirroring. The UI must say so and must not imply an independent desktop.
3. **Mode C — Cast desktop:** the receiver hosts the runtime and presents the desktop. Cast custom messaging is tried first; authenticated LAN `wss` is the fallback.
4. **Mode D — Controller/disconnected:** setup, diagnostics, and recovery when no display path is active.

USB-C/AirPlay is the first production milestone. Cast remains receiver-hosted and supported, but follows the native external-display path rather than defining the MVP sequence.

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
