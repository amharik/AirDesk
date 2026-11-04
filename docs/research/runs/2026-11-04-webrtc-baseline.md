# Loopback WebRTC Data Channel Baseline — 2026-11-04

- **Scenario:** T3 — WKWebView WebRTC data channel between two local peers
- **Commit:** `375951351389`
- **Runner:** Mac mini (Macmini8,1), Intel Core i5-4278U, 8 GB, macOS 15.5
- **Runtime:** macOS WKWebView, Swift 6.1.2
- **Samples:** 30 per payload size
- **Network:** loopback
- **ICE:** host candidates only; no STUN or TURN
- **Scope:** macOS WKWebView harness only; not iOS 18.6 device evidence

| Payload | p50 RTT | p95 RTT | p99 RTT | Channel open | Reconnect | Delivered | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 64 B | 1 ms | 2 ms | 4 ms | 142 ms | 239 ms | 30/30 | pass |
| 1 KiB | 1 ms | 2 ms | 2 ms | 187 ms | 237 ms | 30/30 | pass |
| 16 KiB | 7 ms | 11 ms | 11 ms | 141 ms | 236 ms | 30/30 | pass |

All runs completed without delivery, echo or reconnect failures. ICE gathering completed with two host candidates on each side. Reconnect includes an intentional 100 ms settle delay, so the transport-specific renegotiation cost is roughly 137–147 ms beyond that delay.

## Comparison with T1 and T2

| Payload | T1 WebSocket p50 | T2 WebTransport p50 | T3 WebRTC p50 | T3 channel open |
| --- | --- | --- | --- | --- |
| 64 B | 0.212 ms | 1.389 ms | 1 ms | 142 ms |
| 1 KiB | 0.448 ms | 1.073 ms | 1 ms | 187 ms |
| 16 KiB | 0.339 ms | 4.042 ms | 7 ms | 141 ms |

For an established loopback channel, WebRTC data-channel RTT is close to the WebSocket reference and substantially better than the T2 WebTransport stream baseline. Its setup and reconnect costs are much higher: ICE negotiation and channel opening take roughly 140–190 ms even on loopback with host candidates.

That trade-off is acceptable only for long-lived sessions where setup is amortized. It is not a drop-in replacement for WebSocket reconnects. Real Wi-Fi, cellular and NAT paths still need separate runs, and TURN may be required when host candidates are unavailable.

## Platform scope

This run proves WebRTC data channels work in **macOS** WKWebView without TURN. It does not prove iOS 18.6 behavior. The iOS repeat must run on the physical-device runner or simulator with the same scenario and must not be inferred from this result.

## Not covered

- iOS or iPadOS WKWebView.
- STUN, TURN or relay paths.
- Silent data-channel loss under packet loss.
- Messages larger than 16 KiB or send-buffer backpressure.
- Battery, CPU and binary-size cost.

Raw runs:

- `2026-11-04T230753Z-webrtc-baseline-64b/`
- `2026-11-04T230810Z-webrtc-baseline-1024b/`
- `2026-11-04T230823Z-webrtc-baseline-16384b/`

Next: repeat T3 inside iOS WKWebView, then add a labeled Wi-Fi/tailnet path before deciding between WebRTC, Iroh/QUIC and the WebSocket fallback.
