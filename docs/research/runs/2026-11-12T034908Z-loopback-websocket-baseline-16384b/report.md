# T1 — loopback-websocket-baseline

- Date: 2026-11-12T03:49:14.235Z
- Scenario: `T1` loopback-websocket-baseline
- Candidate: `loopback-websocket-baseline`
- Transport: `websocket`
- Commit: `1c1f5e8e2501` (dirty)
- Owner: R0 harness
- Environment: macOS 15.5 x86_64; deno 2.9.4
- Hardware: Macmini8,1; Intel(R) Core(TM) i5-4278U CPU @ 2.60GHz; 8589934592 bytes RAM
- Network: loopback
- Build configuration: research
- Samples: 30
- Payload: 16384 bytes
- CPU: 92.825%
- Peak memory: n/a
- Result: pass

## Hypothesis

Measure the loopback WebSocket reference transport under the transport metric protocol

## Method

1. Start a loopback WebSocket echo endpoint
2. Exchange bounded binary control messages at the recorded payload size
3. Disconnect the client and establish a fresh connection
4. Write the raw result before generating the report

## Raw measurements

```json
{
  "schema_version": 1,
  "run_id": "2026-11-12T034908Z-loopback-websocket-baseline-16384b",
  "scenario": "T1",
  "scenario_name": "loopback-websocket-baseline",
  "evidence_scope": "transport-baseline",
  "candidate": "loopback-websocket-baseline",
  "transport": "websocket",
  "commit": "1c1f5e8e2501",
  "dirty": true,
  "build": "research",
  "date": "2026-11-12T03:49:14.235Z",
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
      "p50": 0.384,
      "p95": 1.939,
      "p99": 3.014,
      "min": 0.191,
      "max": 3.014
    },
    "messages_delivered": 30,
    "reconnect_ms": 3.279,
    "cpu_percent": 92.825,
    "process_cpu_seconds": 0.056,
    "peak_memory_bytes": null,
    "controller_rss_bytes": 51056640
  },
  "diagnostics": {
    "server_messages_received": 31,
    "payload_bytes": 16384,
    "timeout_ms": 5000
  },
  "failures": [],
  "observations": "Research measurement; not a product commitment. Working tree was dirty; preserve the diff with this run. Transport websocket. Receiver handled 31 messages.",
  "license_notes": "Deno runtime and WebSocket standard only; no added dependency.",
  "decision": "trial",
  "pass": true
}
```

## Observed failures

None.

## Recovery behavior

Client reconnected in 3.279 ms and completed an echo exchange.

## Security notes

Loopback only. No credentials, terminal output, prompts or workspace contents were captured. The generated TLS certificate is ephemeral and scoped to this run.

## License/SBOM notes

Deno runtime and WebSocket standard only; no added dependency.

## Comparison to baseline

Reference baseline only; this run is not a candidate comparison.

## Decision

trial

## What would change the decision

A failed run keeps the candidate on hold. Candidate evidence requires the scenario corpus on recorded hardware and networks.
