# Transport Metadata Baseline

- **Date:** 2026-11-12
- **Status:** Loopback harness validation; not candidate qualification
- **Commit:** `1c1f5e8e2501` with the runner changes uncommitted (`dirty: true`)
- **Host:** Mac mini (Macmini8,1), Intel Core i5-4278U @ 2.60 GHz, 8 GB RAM, macOS 15.5 x86_64
- **Runtimes:** Deno 2.9.4, Cargo 1.98.1, Rust release probe, Swift/WebKit probe

## Method

- Every transport run records `commit`, `dirty`, `build`, controller runtime, host OS/architecture, host model, CPU, memory, network and p50/p95/p99 latency.
- T1 WebSocket and T2 WebTransport use `Deno.cpuUsage()` around the transport phase.
- T3 WebRTC wraps the Swift/WebKit probe with `/usr/bin/time -l`; the child user plus system CPU is included in `process_cpu_seconds`.
- T4 Iroh wraps the release probe with `/usr/bin/time -l`; `scripts/research/run_metrics.sh` injects CPU, peak RSS and hardware metadata into each raw JSON result.
- `cpu_percent = (process user + process system) / transport wall time * 100`. Values above 100 are possible on a multicore host or when the Deno server and client share one process.
- Deno runs record current controller RSS in `controller_rss_bytes`; peak RSS is recorded only when `/usr/bin/time -l` wraps the measured process.

## Results

| Run | p50 / p95 / p99 ms | CPU % | Peak RSS | Reconnect ms |
| --- | --- | --- | --- | --- |
| WebSocket 64 B | 0.257 / 1.254 / 1.666 | 98.827 | n/a | 3.038 |
| WebSocket 1 KiB | 0.254 / 1.298 / 2.185 | 120.764 | n/a | 2.501 |
| WebSocket 16 KiB | 0.384 / 1.939 / 3.014 | 92.825 | n/a | 3.279 |
| WebTransport 64 B | 1.295 / 2.700 / 8.741 | 110.801 | n/a | 7.694 |
| WebTransport 1 KiB | 1.328 / 7.170 / 7.878 | 104.256 | n/a | 6.219 |
| WebTransport 16 KiB | 2.945 / 9.005 / 11.698 | 112.153 | n/a | 6.877 |
| WebRTC 64 B | 1.000 / 3.000 / 4.000 | 46.694 | 293150720 B | 242 |
| WebRTC 1 KiB | 1.000 / 1.000 / 1.000 | 61.541 | 294707200 B | 236 |
| WebRTC 16 KiB | 6.000 / 7.000 / 9.000 | 59.018 | 294608896 B | 276 |
| Iroh 64 B | 0.230 / 0.559 / 0.634 | 52.632 | 14802944 B | 2.715 |
| Iroh 1 KiB | 0.235 / 0.537 / 0.890 | 55.000 | 14909440 B | 2.953 |
| Iroh 16 KiB | 1.021 / 1.177 / 1.720 | 70.588 | 15024128 B | 6.530 |

All 12 runs delivered 30/30 samples and completed a reconnect echo.

## Scope

This validates the P1-10 evidence fields on loopback only. The runs are dirty because the runner/reporting changes were still uncommitted; they are harness evidence, not candidate performance evidence. LAN, cellular, relay, physical-device and cross-host matrices remain part of P5-06 and are not claimed here.
