# T2 — webtransport-loopback-baseline

- Date: 2026-11-12T03:49:39.809Z
- Scenario: `T2` webtransport-loopback-baseline
- Candidate: `webtransport-over-http3`
- Transport: `webtransport`
- Commit: `1c1f5e8e2501` (dirty)
- Owner: R0 harness
- Environment: macOS 15.5 x86_64; deno 2.9.4
- Hardware: Macmini8,1; Intel(R) Core(TM) i5-4278U CPU @ 2.60GHz; 8589934592 bytes RAM
- Network: loopback
- Build configuration: research
- Samples: 30
- Payload: 1024 bytes
- CPU: 104.256%
- Peak memory: n/a
- Result: pass

## Hypothesis

Measure loopback WebTransport over HTTP/3 as a direct-path candidate reference

## Method

1. Generate an ephemeral local TLS certificate and DER hash
2. Start a loopback QUIC endpoint and accept WebTransport sessions
3. Exchange bounded binary control messages on bidirectional streams
4. Disconnect the client and establish a fresh WebTransport session
5. Write the raw result before generating the report

## Raw measurements

```json
{
  "schema_version": 1,
  "run_id": "2026-11-12T034934Z-webtransport-baseline-1024b",
  "scenario": "T2",
  "scenario_name": "webtransport-loopback-baseline",
  "evidence_scope": "transport-baseline",
  "candidate": "webtransport-over-http3",
  "transport": "webtransport",
  "commit": "1c1f5e8e2501",
  "dirty": true,
  "build": "research",
  "date": "2026-11-12T03:49:39.809Z",
  "environment": {
    "controller": "deno 2.9.4",
    "host": "macOS 15.5 x86_64",
    "host_model": "Macmini8,1",
    "cpu": "Intel(R) Core(TM) i5-4278U CPU @ 2.60GHz",
    "memory_bytes": 8589934592,
    "browser": "n/a",
    "network": "loopback"
  },
  "samples": 30,
  "metrics": {
    "control_rtt_ms": {
      "p50": 1.328,
      "p95": 7.17,
      "p99": 7.878,
      "min": 0.896,
      "max": 7.878
    },
    "messages_delivered": 30,
    "reconnect_ms": 6.219,
    "cpu_percent": 104.256,
    "process_cpu_seconds": 0.175,
    "peak_memory_bytes": null,
    "controller_rss_bytes": 49917952
  },
  "diagnostics": {
    "server_messages_received": 31,
    "payload_bytes": 1024,
    "timeout_ms": 5000
  },
  "failures": [],
  "observations": "Research measurement; not a product commitment. Working tree was dirty; preserve the diff with this run. Transport webtransport. Receiver handled 31 messages.",
  "license_notes": "Deno unstable WebTransport/QUIC runtime only; no added dependency.",
  "decision": "trial",
  "pass": true
}
```

## Observed failures

None.

## Recovery behavior

Client reconnected in 6.219 ms and completed an echo exchange.

## Security notes

Loopback only. No credentials, terminal output, prompts or workspace contents were captured. The generated TLS certificate is ephemeral and scoped to this run.

## License/SBOM notes

Deno unstable WebTransport/QUIC runtime only; no added dependency.

## Comparison to baseline

Compare with T1 only when host, network and payload are matched.

## Decision

trial

## What would change the decision

A failed run keeps the candidate on hold. Candidate evidence requires the scenario corpus on recorded hardware and networks.
