# Transport Harness Smoke

- Date: 2026-11-04T11:24:07.792Z
- Scenario: `S0` transport-harness-smoke
- Candidate: `loopback-websocket-baseline`
- Commit: `dc46125c3687` (dirty)
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
2. Exchange bounded binary control messages
3. Disconnect the client and establish a fresh connection
4. Write the raw result before generating the report

## Raw measurements

```json
{
  "schema_version": 1,
  "run_id": "2026-11-04T112403Z-transport-harness-smoke",
  "scenario": "S0",
  "scenario_name": "transport-harness-smoke",
  "evidence_scope": "harness-smoke",
  "candidate": "loopback-websocket-baseline",
  "commit": "dc46125c3687",
  "dirty": true,
  "build": "research",
  "date": "2026-11-04T11:24:07.792Z",
  "environment": {
    "controller": "deno 2.9.4",
    "host": "macOS 15.5 x86_64",
    "browser": "n/a",
    "network": "loopback"
  },
  "samples": 30,
  "metrics": {
    "control_rtt_ms": {
      "p50": 0.224,
      "p95": 1.066,
      "p99": 2.011,
      "min": 0.116,
      "max": 2.011
    },
    "messages_delivered": 30,
    "reconnect_ms": 1.941
  },
  "diagnostics": {
    "server_messages_received": 31,
    "payload_bytes": 64,
    "timeout_ms": 5000
  },
  "failures": [],
  "observations": "R0 harness smoke; not candidate evidence. Working tree was dirty; preserve the diff with this run. Server received 31 messages.",
  "license_notes": "Deno runtime and WebSocket standard only; no added dependency.",
  "decision": "trial",
  "pass": true
}
```

## Observed failures

None.

## Recovery behavior

Client reconnected in 1.941 ms and completed an echo exchange.

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
