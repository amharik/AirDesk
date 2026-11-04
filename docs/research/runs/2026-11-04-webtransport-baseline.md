# Loopback WebTransport Baseline — 2026-11-04

- **Scenario:** T2 — loopback WebTransport over HTTP/3
- **Commit:** `1ea8d855e0ab`
- **Runner:** Mac mini (Macmini8,1), Intel Core i5-4278U, 8 GB, macOS 15.5
- **Toolchain:** Deno 2.9.4 (`--unstable-net`), OpenSSL
- **Samples:** 30 per payload size
- **Network:** loopback
- **Scope:** harness reference only; not a candidate comparison against a deployed network

| Payload | p50 RTT | p95 RTT | p99 RTT | Reconnect | Delivered | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 64 B | 1.389 ms | 7.104 ms | 15.612 ms | 7.778 ms | 30/30 | pass |
| 1 KiB | 1.073 ms | 3.207 ms | 9.672 ms | 8.101 ms | 30/30 | pass |
| 16 KiB | 4.042 ms | 22.912 ms | 29.830 ms | 8.609 ms | 30/30 | pass |

All runs completed without delivery failures or reconnect failures. Each sample uses one bidirectional stream with a 4-byte length frame, so the measurement includes stream setup and teardown rather than only a message echo.

## Comparison with T1 WebSocket

| Payload | T1 p50 | T2 p50 | T1 p95 | T2 p95 | T1 reconnect | T2 reconnect |
| --- | --- | --- | --- | --- | --- | --- |
| 64 B | 0.212 ms | 1.389 ms | 1.177 ms | 7.104 ms | 2.118 ms | 7.778 ms |
| 1 KiB | 0.448 ms | 1.073 ms | 1.393 ms | 3.207 ms | 4.053 ms | 8.101 ms |
| 16 KiB | 0.339 ms | 4.042 ms | 1.667 ms | 22.912 ms | 1.840 ms | 8.609 ms |

On loopback, WebTransport does not beat the WebSocket reference. The gap is consistent with QUIC/TLS and per-message stream setup, but loopback cannot show a WAN traversal or head-of-line benefit. Do not generalize these numbers to LAN, tailnet or relay paths.

## Platform constraint

Safari and iOS Safari support WebTransport from 26.4, and WKWebView compatibility data lists iOS 26.4. The current iPhone 16 Pro baseline is iOS 18.6, so the product's current WKWebView cannot use this transport. WebTransport is therefore a `hold` for the current product baseline and a possible future/native-controller candidate only. WebSocket remains the required fallback.

## Failure found during setup

The first 16 KiB attempt failed because the stream echo read only the first QUIC chunk and closed the stream. The harness now uses a length-framed reader that buffers until the declared frame length is available. The failed run was removed rather than recorded as transport evidence; the fix is committed in `1ea8d85`.

Raw runs:

- `2026-11-04T135713Z-webtransport-baseline-64b/`
- `2026-11-04T135720Z-webtransport-baseline-1024b/`
- `2026-11-04T135726Z-webtransport-baseline-16384b/`

Next: record the WKWebView support gap in the R1 pre-screen, then compare WebRTC, Iroh/QUIC and SSH/tmux using separate labeled network scopes.
