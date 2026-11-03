# ADR-013: Multi-transport architecture and connectivity negotiation

- **Status:** Proposed — benchmark and qualification gates required
- **Date:** 2026-11-03
- **Deciders:** Engineering lead, transport owner
- **Scope:** Transport adapters, channel semantics, browser and native transport sequencing, relay policy
- **Supersedes:** None
- **Amends:** ADR-005 transport sequencing only; display profiles and Cast messaging remain
- **Related:** ADR-001, ADR-004, ADR-005, ADR-008, ADR-010, ADR-011, ADR-012, ADR-014, ADR-015

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
| MVP | Loopback HTTP/WS to local agent | Required browser bootstrap |
| MVP | WebSocket + TLS | Control and coordinator baseline |
| MVP | WebRTC data channels | Required direct browser data path where the endpoint supports it |
| MVP | QUIC | Native direct candidate, qualified by benchmark |
| MVP | Cast custom messaging | Development-only until hardware qualification |
| MVP | Existing AirPlay/external-display path | Fallback endpoint |
| Post-MVP | WebTransport | Candidate for browser-to-host after support qualification |
| Post-MVP | WebRTC/QUIC relay | Encrypted fallback when direct connectivity fails |
| Future | libp2p adapter | Optional, never mandatory |

The MVP requires a direct data path. It does not require relay. If a direct path cannot be established, the session fails closed with a diagnostic rather than silently using a control-plane relay.

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

In the MVP the local agent serves the receiver over loopback, as specified in ADR-014. A hosted receiver is not part of the MVP. Any future hosted receiver must use a first-party origin, pinned assets with SRI, a strict CSP, a documented update process and a pairing-key threat model. If these cannot be satisfied, the external-display path remains the MVP fallback.

### 6. Connectivity is direct-first, relay-second

The connectivity policy is:

1. Local loopback or local direct connection.
2. Direct peer-to-peer connection over WebRTC or QUIC.
3. Encrypted relay for control and data, post-MVP.
4. Video relay only when necessary.

No relay or TURN service is implemented in this cycle. The coordinator may provide signaling and connection hints but is not the data-plane relay. Relay economics and privacy must be measured before a free-tier promise is made.

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

- A direct browser session meets the defined control and input budget for the supported matrix.
- The browser receiver proves or disproves COOP/COEP and secure-context viability.
- A direct WebRTC/QUIC versus WebSocket benchmark records p50/p95 latency, CPU, reconnect time and battery impact.
- Concurrent bulk transfer does not create visible pointer latency.
- Disconnect, focus loss and generation changes produce no stuck keys or buttons.
- A failed direct path fails closed; no relay is silently used in the MVP.
- Cast remains development-only until hardware qualification passes.
- No plaintext LAN transport exists.

## Out of scope

- Implementing relay, TURN, WebTransport or libp2p in this cycle.
- Production WebRTC relay infrastructure and pricing.
- Production Cast qualification without hardware.
- Multi-user traffic routing or group media.
