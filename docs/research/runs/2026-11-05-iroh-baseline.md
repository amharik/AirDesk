# Iroh/QUIC Loopback Baseline (T4 transport) — 2026-11-05

- **Scenario:** T4 — relay-free Iroh/QUIC endpoint pair on loopback
- **Environment:** Mac mini (Macmini8,1), Intel Core i5-4278U, 8 GB, macOS 15.5, x86_64
- **Toolchain:** Cargo 1.98.1, Rust release build, iroh 1.4.1
- **Commit:** `46e9341727b3` with a clean working tree
- **Samples:** 30 per payload size, two clean runs
- **Network:** loopback only, client and server bound to `127.0.0.1`
- **Relay:** `RelayMode::Disabled`; zero relay addresses and no address lookup configured
- **Scope:** Rust library API, direct addressing and loopback behavior only; not NAT traversal, relay fallback, iOS or distribution evidence

| Payload | p50 RTT (run A / B) | p95 RTT range | p99 RTT range | Reconnect (run A / B) | Delivered | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 64 B | 0.337 / 0.293 ms | 0.358–1.125 ms | 1.415–2.696 ms | 3.865 / 8.374 ms | 30/30 | pass |
| 1 KiB | 0.303 / 0.309 ms | 0.768–0.947 ms | 1.445–10.511 ms | 2.694 / 2.570 ms | 30/30 | pass |
| 16 KiB | 1.274 / 1.123 ms | 1.320–11.078 ms | 2.178–14.810 ms | 3.743 / 4.537 ms | 30/30 | pass |

The 64 B process is always the first in a runner invocation. First-connect time was noisy across runs (roughly 3–25 ms) and is not used for comparison. Reconnect also showed occasional single-run jitter, but remained in the low-single-digit millisecond range in every run.

## Comparison with recorded loopback baselines

| Payload | T1 WebSocket p50 | T2 WebTransport p50 | T3 WebRTC p50 | T4 Iroh p50 range | T4 reconnect range |
| --- | --- | --- | --- | --- | --- |
| 64 B | 0.212 ms | 1.389 ms | 1 ms | 0.293–0.337 ms | 3.865–8.374 ms |
| 1 KiB | 0.448 ms | 1.073 ms | 1 ms | 0.303–0.309 ms | 2.570–2.694 ms |
| 16 KiB | 0.339 ms | 4.042 ms | 7 ms | 1.123–1.274 ms | 3.743–4.537 ms |

Established Iroh RTT is close to the WebSocket reference at the small payloads and better than the WebTransport and WKWebView WebRTC baselines at 16 KiB. Reconnect is in the same low-single-digit millisecond range as WebSocket and WebTransport, far below WebRTC's ICE renegotiation. These comparisons are loopback-only and use different controller runtimes.

## Interpretation

Iroh 1.4.1 can establish a direct QUIC connection between two explicitly addressed endpoints with relays disabled. The probe verified the endpoint ID plus direct `127.0.0.1` address, bidirectional stream echo up to 16 KiB, connection close and reconnect with zero delivery failures and zero relay addresses.

This removes the basic API-risk question for a Rust Iroh path. It does **not** prove:

- hole punching or NAT traversal across real networks;
- public-key-only dialing once the direct address is not supplied;
- relay fallback behavior or operational cost;
- an iOS/WKWebView path;
- Swift/UniFFI integration, binary-size impact or App Store constraints;
- packet-loss, sleep/wake or network-change behavior.

The current result therefore keeps Iroh at **trial for a labeled two-host network spike**, not an adoption candidate. The public relay default remains unaccepted under the no-hidden-relay policy.

## Reproduce

```bash
scripts/research/run-iroh.sh
```

The runner builds `research/iroh-probe` with the pinned `Cargo.lock`, runs 64 B, 1 KiB and 16 KiB payloads, and writes one JSON result per payload plus `run-index.json`.

Raw results:

- `2026-11-05T081359Z-iroh-loopback-baseline/` — run A
- `2026-11-05T081449Z-iroh-loopback-baseline/` — run B

Next: run a labeled LAN/tailnet comparison between two hosts, test direct hole punching and relay fallback as separate scenarios, and measure Rust/Swift integration size before the R1 transport decision.
