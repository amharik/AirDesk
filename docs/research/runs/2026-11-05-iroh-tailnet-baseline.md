# Iroh/QUIC Two-Host Tailnet Baseline (T4 transport) — 2026-11-05

- **Scenario:** T4 — relay-free Iroh/QUIC endpoint pair over two hosts on the same tailnet
- **Client environment:** Mac mini (Macmini8,1), Intel Core i5-4278U, 8 GB, macOS 15.5, x86_64
- **Server environment:** Debian 13 Linux, x86_64, kernel 6.12.101
- **Toolchain:** Cargo 1.98.1 on the client, Cargo 1.99.1 on the server, Rust release build, iroh 1.4.1
- **Commit:** `2beb77a37cdd` with a clean working tree
- **Samples:** 30 per payload size, two clean runs
- **Network:** Tailscale tailnet IPv4; client on macOS, server bound to its tailnet address
- **Underlay:** `tailscale ping` reported `via DERP(blr)` and `direct connection not established` in both runs
- **Relay:** Iroh `RelayMode::Disabled`; zero Iroh relay addresses and no address lookup configured
- **Scope:** Two-host direct IP path on the tailnet overlay; not a direct underlay, public NAT traversal, Iroh relay fallback, iOS or distribution evidence

| Payload | p50 RTT (run A / B) | p95 RTT range | p99 RTT range | Reconnect (run A / B) | Delivered | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 64 B | 60.641 / 54.752 ms | 120.875–143.688 ms | 128.810–207.724 ms | 220.245 / 167.977 ms | 30/30 | pass |
| 1 KiB | 72.195 / 61.215 ms | 100.160–191.793 ms | 160.386–192.238 ms | 202.835 / 152.588 ms | 30/30 | pass |
| 16 KiB | 143.939 / 162.760 ms | 287.589–372.132 ms | 300.272–1308.685 ms | 198.756 / 300.290 ms | 30/30 | pass |

Tailnet ping was 70.505 ms in run A and 63.039 ms in run B. Small-payload Iroh p50 is close to that network RTT. The 16 KiB p50 is roughly two times the network RTT, and one run recorded a 1308.685 ms p99 outlier. Reconnect is 152–300 ms, far above loopback but without WebRTC ICE negotiation.

## Comparison with the Iroh loopback baseline

| Payload | T4 loopback p50 range | T4 tailnet p50 (run A / B) | T4 loopback reconnect range | T4 tailnet reconnect (run A / B) |
| --- | --- | --- | --- | --- |
| 64 B | 0.293–0.337 ms | 60.641 / 54.752 ms | 3.865–8.374 ms | 220.245 / 167.977 ms |
| 1 KiB | 0.303–0.309 ms | 72.195 / 61.215 ms | 2.570–2.694 ms | 202.835 / 152.588 ms |
| 16 KiB | 1.123–1.274 ms | 143.939 / 162.760 ms | 3.743–4.537 ms | 198.756 / 300.290 ms |

The difference is almost entirely network path and connection setup, not the Iroh transport loop. Do not compare these numbers with loopback or WebRTC results without the network label.

## Interpretation

Iroh 1.4.1 established, echoed and reconnected a two-host QUIC session using an explicit endpoint ID plus a direct tailnet IPv4 address, with Iroh relays disabled. Every run selected one direct IP path, opened zero relay paths, delivered 30/30 samples and passed.

This is evidence that the relay-free API and direct-addressing model work across two hosts. It is **not** evidence of a direct underlay path: Tailscale reported a DERP relay and no direct connection. The Iroh path is direct on the tailnet interface, while the tailnet itself is relayed. That is a visible, external relay rather than an Iroh relay, but it still invalidates any claim that the measured path was relay-free end to end.

The result therefore keeps Iroh at **trial**. Still unproven:

- public NAT traversal and direct underlay establishment;
- Iroh relay fallback and self-hosted relay cost;
- public-key-only dialing without an explicitly supplied direct address;
- packet loss, sleep/wake, network change and DERP outage behavior;
- an iOS/WKWebView path, Swift/UniFFI integration, binary size or App Store constraints.

The public Iroh relay default remains unaccepted under the no-hidden-relay policy. Tailnet DERP is likewise a relay dependency and must be labeled in any future comparison.

## Reproduce

```bash
AIRDESK_IROH_SERVER_SSH=user@tailnet-host \
AIRDESK_IROH_SERVER_IP=<tailnet-ipv4> \
scripts/research/run-iroh-net.sh
```

The runner copies `research/iroh-probe` to the remote host, builds it there with the pinned `Cargo.lock`, starts a relay-disabled server bound to the tailnet IPv4 address, records the Tailscale underlay path, and runs 64 B, 1 KiB and 16 KiB payloads from the Mac client. It writes one JSON result per payload plus `run-index.json`.

Raw results:

- `2026-11-05T094700Z-iroh-tailnet-baseline/` — run A
- `2026-11-05T094733Z-iroh-tailnet-baseline/` — run B

Next: establish a direct Tailscale or LAN underlay and repeat T4 without any relayed network hop, then run Iroh relay fallback as a separate explicitly authorized scenario. The SSH/tmux pre-screen remains the next no-hardware R1 comparison.
