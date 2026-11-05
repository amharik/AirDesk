# T4 Iroh/QUIC Relay Fallback Baseline

- **Run:** `2026-11-05T175723Z-iroh-relay-fallback`
- **Commit:** `e4f9eeeb6b09`
- **Date:** 2026-11-05
- **Controller:** macOS 15.5 x86_64, Cargo 1.98.1
- **Server:** Debian 13 x86_64, Cargo 1.99.1, remote `sillygirl`
- **Network:** Iroh data path over the public n0 relay `https://aps1-1.relay.n0.iroh.link./`; SSH control path over a DERP-relayed tailnet
- **Probe:** pinned `iroh` 1.4.1, research-only

## Method

1. Build the same `research/iroh-probe` crate on the Mac client and the remote Linux host.
2. Bind the server with `RelayMode::Default`, clear all IP transports, and wait for the home relay to become online.
3. Read the server endpoint ID and assigned relay URL from the ready event.
4. Bind the client with `RelayMode::Default` and clear all IP transports.
5. Connect by endpoint ID plus the explicit relay URL, with no direct address.
6. Echo 30 framed payloads on bidirectional QUIC streams, close, reconnect, and echo once more.
7. Fail if no relay address is present, the selected path is not relay, delivery is incomplete or the reconnect is missing.

This is a **forced relay-only** run. Both endpoints had IP transports removed, so it does not observe an automatic direct-to-relay transition after a direct path fails.

## Result

| Payload | Delivered | RTT p50 | RTT p95 | RTT p99 | Connect | Reconnect | Relay paths | Direct paths |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 64 B | 30/30 | 108.812 ms | 129.822 ms | 141.821 ms | 117.068 ms | 249.128 ms | 1 | 0 |
| 1 KiB | 30/30 | 106.112 ms | 178.652 ms | 193.070 ms | 111.782 ms | 262.049 ms | 1 | 0 |
| 16 KiB | 30/30 | 183.924 ms | 289.732 ms | 310.788 ms | 106.956 ms | 466.295 ms | 1 | 0 |

All three payload runs passed: 90/90 deliveries, empty failure lists, `relay_addrs = 1`, `selected_path = relay`, and zero direct paths.

## Comparison

- T4 loopback p50 was `0.293–0.337 / 0.303–0.309 / 1.123–1.274 ms` at 64 B / 1 KiB / 16 KiB.
- T4 two-host tailnet p50 was `54.752–60.641 / 61.215–72.195 / 143.939–162.760 ms`; that run used a Tailscale DERP underlay.
- This relay-only run p50 was `108.812 / 106.112 / 183.924 ms`.

The relay path adds roughly 45–55 ms at 64 B and 1 KiB, and about 20–40 ms at 16 KiB, against the recorded DERP-relayed tailnet direct-address run. These are different routes and not a controlled relay-versus-direct comparison. The relay connection also costs about 107–117 ms to establish and 249–466 ms to reconnect.

## Caveats

- The public n0 relay map is a hidden third-party dependency and is **not** accepted for the product under ADR-013. This is research evidence only.
- The relay sees encrypted QUIC packets but still observes connection metadata. Self-hosted relay operation, access control, retention and availability remain unmeasured.
- IP transports were cleared on both ends, so this is a relay-only path, not an observed fallback after a failed direct attempt.
- Relay loss, relay migration, NAT failure and long-idle behavior were not injected.
- The SSH control channel used a DERP-relayed tailnet; that is separate from the Iroh data path.
- No WKWebView, Swift or iOS-client path was measured.

## Evidence

- `docs/research/runs/2026-11-05T175723Z-iroh-relay-fallback/64b.json`
- `docs/research/runs/2026-11-05T175723Z-iroh-relay-fallback/1024b.json`
- `docs/research/runs/2026-11-05T175723Z-iroh-relay-fallback/16384b.json`
- `docs/research/runs/2026-11-05T175723Z-iroh-relay-fallback/run-index.json`
