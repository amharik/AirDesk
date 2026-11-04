# Loopback WebSocket Baseline — 2026-11-04

- **Scenario:** T1 — loopback WebSocket reference transport
- **Commit:** `341bed041afd`
- **Runner:** Mac mini (Macmini8,1), Intel Core i5-4278U, 8 GB, macOS 15.5
- **Toolchain:** Deno 2.9.4
- **Samples:** 30 per payload size
- **Scope:** reference measurement only; no candidate comparison

| Payload | p50 RTT | p95 RTT | p99 RTT | Reconnect | Delivered | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 64 B | 0.212 ms | 1.177 ms | 1.350 ms | 2.118 ms | 30/30 | pass |
| 1 KiB | 0.448 ms | 1.393 ms | 1.773 ms | 4.053 ms | 30/30 | pass |
| 16 KiB | 0.339 ms | 1.667 ms | 2.441 ms | 1.840 ms | 30/30 | pass |

All runs completed without delivery failures or reconnect failures. The loopback numbers are dominated by local scheduling and are not a network budget. The 16 KiB p50 should not be read as faster than 1 KiB; the difference is within local noise.

Raw runs:

- `2026-11-04T133926Z-loopback-websocket-baseline-64b/`
- `2026-11-04T133931Z-loopback-websocket-baseline-1024b/`
- `2026-11-04T133936Z-loopback-websocket-baseline-16384b/`

Next: run the same T1 procedure against WebTransport, WebRTC, Iroh/QUIC and SSH/tmux adapters once each adapter exists.
