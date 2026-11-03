# ADR-013: Multi-transport architecture and connectivity negotiation

- **Status:** Proposed — benchmark and qualification gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — control, data, media and presentation separated
- **Updated:** 2026-11-03 — research update: WebTransport Baseline 2026, transport evolution negotiation, SAB fallback
- **Updated:** 2026-11-03 — peer review: ephemeral WebTransport certificate rotation and dual-hash advertisement
- **Updated:** 2026-11-03 — peer review round 3: signed/pairing-only cert hashes; WebTransport Baseline date and WKWebView qualification gate
- **Deciders:** Engineering lead, transport owner
- **Scope:** Transport adapters, control/data/media planes, browser and native transport sequencing, WebTransport, relay policy
- **Supersedes:** None
- **Amends:** ADR-005 transport sequencing only; display profiles and Cast messaging remain
- **Related:** ADR-001, ADR-004, ADR-005, ADR-008, ADR-010, ADR-011, ADR-012, ADR-014, ADR-015, ADR-016, ADR-017

## Context

ADR-005 establishes WebSocket and WebRTC as the transport baseline. The device-fabric and browser-endpoint releases add constraints:

- Browser receivers require secure contexts and, for threaded Wanix/WASM, cross-origin isolation and `SharedArrayBuffer`.
- mDNS and local-network discovery are restricted in browsers.
- WebRTC adds ICE, signaling and TURN complexity.
- WebTransport is Baseline 2026 and a named browser-to-host candidate, but it is not required and its wire protocol is still evolving.
- Cast uses custom messaging and cannot be treated as a WebRTC browser.

Transport choice must follow measured need. It must not become a prerequisite for the first usable workspace. A browser endpoint must start with the single-threaded profile when cross-origin isolation or `SharedArrayBuffer` is unavailable.

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

### 1.1 Control, data, media and presentation are separate planes

| Plane | Carries | Examples |
| --- | --- | --- |
| Control | identity, discovery, policy, workspace coordination, lifecycle | pairing, capability leases, placement, runtime status |
| Data | inputs, files, resource transfer, application data | pointer frames, file chunks |
| Media | audio and video streams | camera, microphone, remote surface |
| Presentation | visual composition and interaction | shell, windows, cursor, display endpoint |

- Control must not become the bulk-data path.
- The workspace store and orchestrator are not in the presentation plane.
- Media and bulk transfer must not block control or input.
- A transport adapter may carry more than one channel but must preserve the plane separation.
- Workspace semantics must not depend on which plane or transport carries a message.

### 2. Sequence transports by evidence

| Phase | Transport | Status |
| --- | --- | --- |
| Workspace release | Native IPC / loopback | Local control and presentation |
| Device fabric | WebSocket + TLS | Control and coordinator baseline |
| Device fabric | WebRTC data channels | Preferred direct device data path |
| Device fabric | QUIC | Native direct candidate, qualified by benchmark |
| Browser endpoint | Loopback HTTP/WS to local agent | Required browser bootstrap |
| Browser endpoint | WebTransport over HTTP/3 | Baseline 2026; candidate for browser data, not required |
| Display release | Cast custom messaging | Development-only until hardware qualification |
| Display release | Existing AirPlay/external-display path | Fallback endpoint |
| Later | WebTransport as primary data path | Only after benchmark and wire-version review |
| Later | WebRTC/QUIC relay | Encrypted fallback when direct connectivity fails |
| Future | libp2p adapter | Optional, never mandatory |

The device fabric requires a direct data path. It does not require relay. If a direct path cannot be established, the session fails closed with a diagnostic rather than silently using a control-plane relay.

### 2.1 WebTransport is available but still optional

WebTransport is Baseline 2026 in current browsers, including Safari 26.4 and later, and the W3C specification reached Candidate Recommendation in July 2026. It is a named candidate for the browser-to-host data channel because it provides multiple streams, datagrams and lower head-of-line blocking than WebSocket.

It is not a requirement:

- The browser endpoint must work over loopback WebSocket before WebTransport is enabled.
- Transport negotiation must advertise WebTransport support and fall back explicitly.
- HTTP/3, certificates, proxies and NAT behavior are qualified per deployment.
- The IETF wire protocol and browser API may still change; version negotiation must cover transport bindings, not only ADFP semantics.
- WebTransport does not replace AD-RUNTIME, AD-RESOURCE or capability authorization semantics.

### 2.2 Ephemeral certificate rotation for LAN WebTransport

A LAN host has no publicly trusted CA certificate. WebTransport accepts a self-signed certificate through `serverCertificateHashes`, subject to the W3C rule that the certificate use ECDSA and have a validity period no longer than 14 days.

- Every host running a WebTransport listener generates an ephemeral **ECDSA P-256** certificate with a **7-day** validity at startup.
- The certificate rotates every **5 days** with a **48-hour dual-hash overlap**: mDNS TXT records and pairing payloads advertise both `certhash_current=<sha256>` and `certhash_next=<sha256>`.
- The current SHA-256 fingerprint may also be served over an authenticated bootstrap endpoint or a signed advertisement; it is never accepted from an unsigned mDNS TXT record alone.
- A client accepts a certificate hash only from the pairing payload or a signed advertisement for that device, and pins it for the session; an unknown, unsigned or mismatched hash fails closed.
- Expired, more-than-14-day or non-ECDSA certificates are rejected before connection.
- Rotation does not invalidate an established session; new sessions use the newest advertised hash.

Browser support for `serverCertificateHashes` is a qualification gate, not an assumption. WebTransport reached Baseline in March 2026, but `serverCertificateHashes` availability differs: Chrome 100+, Firefox 125+, and Safari/iOS 26.4+. Before the WKWebView shell enables WebTransport:

- the target runtime must expose `WebTransport` and accept `serverCertificateHashes` with an ECDSA P-256 certificate;
- the shell must verify the certificate hash against the pairing payload, not merely against the handshake;
- if the gate fails, the shell uses the loopback WebSocket path and reports `webtransport_unqualified` in diagnostics.

A native controller may use WebTransport over the LAN once its own qualification passes; this does not relax the browser gate.

### 3. WebRTC channel semantics

When WebRTC is adopted:

- **Control:** reliable, ordered, for session, capability, window and lifecycle messages.
- **Input:** unordered and partially reliable, for pointer movement and other stale-tolerant input.
- **Bulk:** reliable, ordered, for files and resource transfer.
- **Media:** WebRTC media tracks for audio, video, camera and microphone.

Clicks, key releases, text commits and lifecycle transitions must not be sent only on an unreliable channel.

### 4. Cast is not a WebRTC path

Cast uses the existing custom message channels and compact JSON profile. Do not attempt WebRTC inside the Cast receiver sandbox.

Cast remains development-only until physical Chromecast or Google TV qualification passes. Cast is not a browser endpoint dependency.

### 5. Browser receiver requirements are part of transport design

A browser endpoint must account for:

- HTTPS or a secure-context equivalent;
- COOP/COEP headers for cross-origin isolation where threaded WASM is requested;
- `SharedArrayBuffer` availability detection with a single-threaded fallback;
- hosting of receiver assets;
- QR or authenticated rendezvous instead of mDNS;
- browser permission prompts for camera, microphone and clipboard.

In the browser-endpoint release the local host agent serves the receiver over loopback, as specified in ADR-014. A hosted endpoint is not part of that release. Any future hosted endpoint must use a first-party origin, pinned assets with SRI, a strict CSP, a documented update process and a pairing-key threat model. If these cannot be satisfied, the external-display path remains the fallback.

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
- Browser isolation and hosting may block the browser endpoint release.
- `SharedArrayBuffer` or COOP/COEP failures force the single-threaded profile.
- WebTransport availability varies by browser, network and server, so it cannot replace WebSocket yet.
- Multiple transport adapters increase qualification effort.

## Acceptance gates

- A direct browser session meets the defined control and input budget for the supported matrix.
- The browser receiver proves or disproves COOP/COEP and secure-context viability.
- The browser endpoint starts in single-threaded mode without `SharedArrayBuffer` and only selects the threaded profile when isolation is confirmed.
- A direct WebRTC/QUIC/WebTransport versus WebSocket benchmark records p50/p95 latency, CPU, reconnect time and battery impact.
- WebTransport negotiation and fallback are tested on the supported browser matrix.
- A WebTransport LAN endpoint presents an ECDSA P-256 certificate valid ≤14 days, rotates every 5 days and advertises current and next hashes during the 48-hour overlap; unknown, unsigned or expired hashes are rejected.
- WKWebView WebTransport qualification passes (`WebTransport` plus `serverCertificateHashes`, ECDSA P-256, pinned hash from pairing); on failure the shell uses loopback WebSocket and reports `webtransport_unqualified`.
- Concurrent bulk transfer does not create visible pointer latency.
- Disconnect, focus loss and generation changes produce no stuck keys or buttons.
- A failed direct path fails closed; no relay is silently used in the MVP release.
- Cast remains development-only until hardware qualification passes.
- No plaintext LAN transport exists.

## Options considered

| Option | Why not chosen |
| --- | --- |
| WebSocket only | No datagram path, weaker loss handling and no QUIC multiplexing for the input/PTY mix |
| WebRTC first | Requires signaling, ICE and TURN work before a second device ships |
| Require WebTransport | Not qualified in every target browser or network; would block the baseline |
| Layered selection: loopback/WebSocket, WebRTC/QUIC/WebTransport where qualified, relay only when authorized | Chosen: each path is measured and failure is explicit |
| Silent relay fallback | Hides cost, latency and trust changes from the user |

## Out of scope

- Implementing relay or TURN before measured need.
- Making WebTransport, WebRTC, QUIC or libp2p mandatory.
- Production WebRTC relay infrastructure and pricing.
- Production Cast qualification without hardware.
- Multi-user traffic routing or group media.
