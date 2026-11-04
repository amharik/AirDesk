# T2 — webtransport-loopback-baseline

- Date: 2026-11-04T13:57:31.343Z
- Scenario: `T2` webtransport-loopback-baseline
- Candidate: `webtransport-over-http3`
- Transport: `webtransport`
- Commit: `1ea8d855e0ab`
- Owner: R0 harness
- Environment: macOS 15.5 x86_64; deno 2.9.4
- Network: loopback
- Build configuration: research
- Samples: 30
- Payload: 16384 bytes
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
  "run_id": "2026-11-04T135726Z-webtransport-baseline-16384b",
  "scenario": "T2",
  "scenario_name": "webtransport-loopback-baseline",
  "evidence_scope": "transport-baseline",
  "candidate": "webtransport-over-http3",
  "transport": "webtransport",
  "commit": "1ea8d855e0ab",
  "dirty": false,
  "build": "research",
  "date": "2026-11-04T13:57:31.343Z",
  "environment": {
    "controller": "deno 2.9.4",
    "host": "macOS 15.5 x86_64",
    "browser": "n/a",
    "network": "loopback"
  },
  "samples": 30,
  "metrics": {
    "control_rtt_ms": {
      "p50": 4.042,
      "p95": 22.912,
      "p99": 29.83,
      "min": 2.594,
      "max": 29.83
    },
    "messages_delivered": 30,
    "reconnect_ms": 8.609
  },
  "diagnostics": {
    "server_messages_received": 31,
    "payload_bytes": 16384,
    "timeout_ms": 5000
  },
  "failures": [],
  "observations": "Research measurement; not a product commitment. Working tree was clean. Transport webtransport. Server received 31 messages.",
  "license_notes": "Deno unstable WebTransport/QUIC runtime only; no added dependency.",
  "decision": "trial",
  "pass": true
}
```

## Observed failures

None.

## Recovery behavior

Client reconnected in 8.609 ms and completed an echo exchange.

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
