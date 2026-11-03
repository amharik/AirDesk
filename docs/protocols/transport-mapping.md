# Transport mapping

ADFP is semantic and transport-neutral. This document maps its planes to transports without changing protocol meaning.

## Planes

| Plane | Carries | Examples |
| --- | --- | --- |
| Control | Identity, discovery, pairing, policy, workspace coordination, lifecycle | AD-WS, AD-DEV, AD-CAP control |
| Data | Input, files, media, application data, execution output | AD-INPUT, AD-RESOURCE, AD-MEDIA |
| Presentation | Surface composition and display status | AD-DISPLAY, AD-WINDOW |

A single transport adapter may carry more than one plane, but plane separation must remain visible in policy, routing and diagnostics.

## ADFP channel classes

| Channel | Class | Transport semantics | Traffic |
| --- | --- | --- | --- |
| 0 | Control and handshake | Reliable, ordered bidirectional stream | Version negotiation, pairing, capability presentation, lease heartbeats |
| 1 | Pointer-movement hot path | Unreliable QUIC datagram, or the ordered reliable WebSocket binary channel (WebSocket cannot send unordered) | 16-byte `PackedPointerFrame` movement only, with monotonic `seq`; stale frames dropped, not retransmitted. All input edges (`pointerDown`/`Up`/`Click`/`Cancel`, `scroll`, keyboard, text, focus) use a reliable ordered FlatBuffers input-critical channel, never Channel 1 |
| 2..N | Runtime and PTY streams | Reliable bidirectional streams | Per-instance `stdin`/`stdout`/`stderr`/`resize`/`signal` with 256 KiB byte-credit flow control |
| M..K | VFS resource mounts | Reliable bidirectional streams | Plan 9-inspired ADFP `ResourceRpc` ops (`Attach`, `Walk`, `Open`, `Read`, `Write`, `Clunk`, `Stat`, `Wstat`); ADFP op codes, not 9P2000 tags |

## WebTransport certificate rules

- A LAN WebTransport listener uses an ephemeral ECDSA P-256 certificate valid for at most 14 days.
- Certificates rotate every 5 days with a 48-hour dual-hash overlap; mDNS TXT and pairing payloads advertise `certhash_current` and `certhash_next`.
- Clients accept only an advertised hash for that device; unknown, expired or non-ECDSA hashes fail closed.
- Browser endpoints are WebTransport clients only and fall back to WebSocket within 300 ms when UDP is blocked (ADR-014).

## Mapping

| Transport | Control | Data | Presentation | Notes |
| --- | --- | --- | --- | --- |
| Local IPC | Yes | Yes | Yes | Same-device components |
| Loopback HTTP/WS | Yes | Yes | Yes | Browser bootstrap with origin checks |
| WebSocket + TLS | Yes | Limited | Limited | Coordinator and control baseline |
| WebRTC data channels | Signaling | Yes | Limited | Direct device data path |
| QUIC | Yes | Yes | Limited | Qualified native direct path |
| Cast custom messaging | No | No | Yes | Development-only until hardware qualification |
| AirPlay/external display | No | No | Yes | Fallback presentation path |
| WebTransport | Yes | Yes | Limited | Baseline 2026; browser data candidate, not required |
| Relay | Yes | Yes | Limited | Encrypted fallback only |

## Rules

- Behavior must not depend on which transport carries a message.
- Receivers route by channel class before inspecting payloads: Channel 1 is packed movement only, Channel 1R and all other ADFP channels are FlatBuffers envelopes only. The `0xA5` discriminator is defense-in-depth, not the primary router.
- A packed movement frame carries no session, generation or controller identity; the receiver derives them from the authenticated connection. Movement frames are never accepted on shared or unauthenticated paths.
- The control plane must not carry bulk content.
- A failed direct path fails closed unless an encrypted relay is explicitly authorized.
- WebRTC DTLS fingerprints must be bound to authenticated identities.
- Transport discovery does not establish trust.
- Cast is never assumed to be a WebRTC browser.
- Browser endpoints require secure contexts. Threaded WASM additionally requires COOP/COEP, `crossOriginIsolated` and `SharedArrayBuffer`; otherwise use the single-threaded profile.
- WebTransport wire behavior and browser support are versioned separately from ADFP semantics.

## Selection

Selection follows measured evidence:

1. local IPC or loopback where possible;
2. direct authenticated WebSocket/WebRTC/QUIC;
3. WebTransport where supported and benchmarked for browser data;
4. explicit encrypted relay fallback;
5. typed failure with diagnostics if no authorized path exists.

Do not make relay a hidden prerequisite for local operation.
