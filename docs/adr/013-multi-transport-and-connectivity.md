# ADR-013: Multi-transport architecture and connectivity negotiation

- **Status:** Proposed — benchmark and qualification gates required
- **Date:** 2026-11-03
- **Scope:** Transport adapters, channel semantics, browser and native transport sequencing, relay policy
- **Supersedes:** None
- **Amends:** ADR-005 transport sequencing only; display profiles and Cast messaging remain
- **Related:** ADR-001, ADR-004, ADR-005, ADR-008, ADR-010, ADR-011, ADR-012

## Context

ADR-005 establishes WebSocket and WebRTC as the transport baseline. The browser-first MVP creates new constraints:

- Browser receivers require secure contexts and, for Wanix/WASM, cross-origin isolation.
- mDNS and local-network discovery are restricted in browsers.
- WebRTC adds ICE, signaling and TURN complexity.
- WebTransport and QUIC may be useful later but are not required for the first endpoint.
- Cast uses custom messaging and cannot be treated as a WebRTC browser.

Transport choice must follow measured need. It must not become a prerequisite for the first usable workspace.

## Decision

### 1. Transport adapters implement one logical contract

Define a transport adapter interface covering:

- session open and close;
- control channel;
- input channel;
- optional bulk-transfer channel;
- optional media channel;
- reconnect and generation handling;
- capability and latency reporting.

The logical message model is independent of transport. Transport choice must not change input or workspace semantics.

### 2. Sequence transports by evidence

| Phase | Transport | Status |
| --- | --- | --- |
| MVP | WebSocket + TLS | Baseline |
| MVP | Cast custom messaging | Development-only until hardware qualification |
| MVP | Existing AirPlay/external-display path | Fallback endpoint |
| After benchmark | WebRTC data channels | Candidate for browser/native direct sessions |
| After browser support qualification | WebTransport | Candidate for browser-to-host |
| After native benchmark | QUIC | Candidate for host-to-host |
| Future | libp2p adapter | Optional, never mandatory |

No transport beyond WebSocket/TLS is required for the browser MVP unless the feasibility spike proves it is necessary.

### 3. WebRTC channel semantics

When WebRTC is adopted:

- **Control:** reliable, ordered, for session, capability, window and lifecycle messages.
- **Input:** unordered and partially reliable, for pointer movement and other stale-tolerant input.
- **Bulk:** reliable, ordered, for files and resource transfer.
- **Media:** WebRTC media tracks for audio, video, camera and microphone.

Clicks, key releases, text commits and lifecycle transitions must not be sent only on an unreliable channel.

### 4. Cast is not a WebRTC path

Cast uses the existing custom message channels and compact JSON profile. Do not attempt WebRTC inside the Cast receiver sandbox.

Cast remains development-only until physical Chromecast or Google TV qualification passes. Cast is not a browser MVP dependency.

### 5. Browser receiver requirements are part of transport design

A browser endpoint must account for:

- HTTPS or a secure-context equivalent;
- COOP/COEP headers for cross-origin isolation;
- hosting of receiver assets;
- QR or authenticated rendezvous instead of mDNS;
- browser permission prompts for camera, microphone and clipboard.

If these cannot be satisfied, the external-display path remains the MVP fallback.

### 6. Connectivity is direct-first, relay-second

The future connectivity policy is:

1. Local direct connection.
2. Direct peer-to-peer connection.
3. Encrypted relay for control and data.
4. Video relay only when necessary.

No relay or TURN service is implemented in this cycle. Relay economics must be measured before a free-tier promise is made.

### 7. No plaintext fallback and no stuck input

- Plain `ws://` is prohibited outside loopback.
- Transport disconnect, focus loss and generation changes release pressed keys and buttons.
- Input frames are bounded and validated at the transport boundary.
- Stale pointer samples may be dropped; required control and key events may not be silently lost.

## Consequences

### Positive

- The browser endpoint can be built without committing to WebRTC or QUIC.
- Transport experiments are isolated behind adapters.
- Cast remains compatible with its constrained channel.
- Input semantics remain stable across transports.

### Negative

- WebSocket may not meet every future latency or peer-to-peer requirement.
- Adding WebRTC later requires signaling, ICE and TURN work.
- Browser isolation and hosting may block the browser MVP.
- Multiple transport adapters increase qualification effort.

## Acceptance gates

- A WebSocket/TLS browser session meets the defined control and input budget for the supported matrix.
- The browser receiver proves or disproves COOP/COEP and secure-context viability.
- A WebSocket versus WebRTC benchmark records p50/p95 latency, CPU, reconnect time and battery impact.
- Concurrent bulk transfer does not create visible pointer latency.
- Disconnect, focus loss and generation changes produce no stuck keys or buttons.
- Cast remains development-only until hardware qualification passes.
- No plaintext LAN transport exists.

## Out of scope

- Implementing WebRTC, WebTransport, QUIC or libp2p in this cycle.
- TURN relay infrastructure and pricing.
- Production Cast qualification without hardware.
- Multi-user traffic routing or group media.
