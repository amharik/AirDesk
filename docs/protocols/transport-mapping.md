# Transport mapping

ADFP is semantic and transport-neutral. This document maps its planes to transports without changing protocol meaning.

## Planes

| Plane | Carries | Examples |
| --- | --- | --- |
| Control | Identity, discovery, pairing, policy, workspace coordination, lifecycle | AD-WS, AD-DEV, AD-CAP control |
| Data | Input, files, media, application data, execution output | AD-INPUT, AD-RESOURCE, AD-MEDIA |
| Presentation | Surface composition and display status | AD-DISPLAY, AD-WINDOW |

A single transport adapter may carry more than one plane, but plane separation must remain visible in policy, routing and diagnostics.

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
