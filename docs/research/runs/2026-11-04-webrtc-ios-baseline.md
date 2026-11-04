# iOS WKWebView WebRTC Probe — 2026-11-04

- **Scenario:** T3 repeat — WKWebView WebRTC data channel between two local peers
- **Environment:** iPhone 16 Pro simulator, iOS 18.6
- **Host:** Mac mini (Macmini8,1), Intel Core i5-4278U, 8 GB, macOS 15.5
- **Toolchain:** Xcode 16.4, Swift 6.1.2, Deno not used
- **Samples:** 30 per payload size
- **Network:** simulator loopback
- **ICE:** host candidates only; no STUN or TURN
- **Scope:** simulator API and loopback behavior only; not physical-device or real-network evidence

| Payload | p50 RTT | p95 RTT | p99 RTT | Channel open | Reconnect | Delivered | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 64 B | 1 ms | 4 ms | 7 ms | 165 ms | 283 ms | 30/30 | pass |
| 1 KiB | 2 ms | 5 ms | 6 ms | 193 ms | 256 ms | 30/30 | pass |
| 16 KiB | 12 ms | 29 ms | 31 ms | 186 ms | 314 ms | 30/30 | pass |

All runs completed with host candidates on both sides, no TURN, no delivery failures and no reconnect failures. Reconnect includes an intentional 100 ms settle delay, so the observed renegotiation cost is roughly 156–214 ms beyond that delay.

## Interpretation

The iOS 18.6 simulator exposes `RTCPeerConnection` and `RTCDataChannel`, negotiates a reliable ordered data channel, and echoes binary messages up to 16 KiB without TURN on loopback. This removes the API-availability risk for the WebRTC candidate on the current iOS baseline.

It does not establish physical-device performance, Wi-Fi/cellular behavior, TURN fallback, silent data-channel loss handling or battery cost. Those remain separate runs.

## Reproduce

```bash
scripts/research/run-webrtc-ios.sh
```

The runner sets the probe defaults in the simulator, builds once, records 64 B, 1 KiB and 16 KiB results, and writes raw probe JSON under the run directory. The probe test skips in normal CI unless explicitly enabled.

Raw results:

- `2026-11-04T231742Z-webrtc-ios-baseline/`

Next: repeat on the physical iPhone 16 Pro when signing is available, then run a labeled Wi-Fi/tailnet path with and without TURN.
