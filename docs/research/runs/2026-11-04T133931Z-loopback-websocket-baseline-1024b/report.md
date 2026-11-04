# T1 — loopback-websocket-baseline

- Date: 2026-11-04T13:39:35.508Z
- Scenario: `T1` loopback-websocket-baseline
- Candidate: `loopback-websocket-baseline`
- Commit: `341bed041afd`
- Owner: R0 harness
- Environment: macOS 15.5 x86_64; deno 2.9.4
- Network: loopback
- Build configuration: research
- Samples: 30
- Result: pass

## Hypothesis

The R0 transport runner can produce a reproducible raw result and report without credentials, external services or workspace contents.

## Method

1. Start a loopback WebSocket echo endpoint
2. Exchange bounded binary control messages at the recorded payload size
3. Disconnect the client and establish a fresh connection
4. Write the raw result before generating the report

## Raw measurements

```json
{
  "schema_version": 1,
  "run_id": "2026-11-04T133931Z-loopback-websocket-baseline-1024b",
  "scenario": "T1",
  "scenario_name": "loopback-websocket-baseline",
  "evidence_scope": "transport-baseline",
  "candidate": "loopback-websocket-baseline",
  "commit": "341bed041afd",
  "dirty": false,
  "build": "research",
  "date": "2026-11-04T13:39:35.508Z",
  "environment": {
    "controller": "deno 2.9.4",
    "host": "macOS 15.5 x86_64",
    "browser": "n/a",
    "network": "loopback"
  },
  "samples": 30,
  "metrics": {
    "control_rtt_ms": {
      "p50": 0.448,
      "p95": 1.393,
      "p99": 1.773,
      "min": 0.189,
      "max": 1.773
    },
    "messages_delivered": 30,
    "reconnect_ms": 4.053
  },
  "diagnostics": {
    "server_messages_received": 31,
    "payload_bytes": 1024,
    "timeout_ms": 5000
  },
  "failures": [],
  "observations": "R0 harness smoke; not candidate evidence. Working tree was clean. Server received 31 messages.",
  "license_notes": "Deno runtime and WebSocket standard only; no added dependency.",
  "decision": "trial",
  "pass": true
}
```

## Observed failures

None.

## Recovery behavior

Client reconnected in 4.053 ms and completed an echo exchange.

## Security notes

Loopback only. No credentials, terminal output, prompts or workspace contents were captured.

## License/SBOM notes

Deno runtime and the WebSocket standard only; no runtime dependency was added.

## Comparison to baseline

Baseline self-test only; this run is not a candidate comparison.

## Decision

trial

## What would change the decision

A failed smoke keeps R1 blocked. Candidate evidence requires the S1-S8 scenarios on recorded hardware and networks.
