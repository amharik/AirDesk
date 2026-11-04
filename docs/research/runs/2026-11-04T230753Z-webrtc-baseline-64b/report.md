# T3 — webrtc-datachannel-loopback-baseline

- Date: 2026-11-04T23:08:09.854Z
- Scenario: `T3` webrtc-datachannel-loopback-baseline
- Candidate: `webrtc-datachannel`
- Transport: `webrtc`
- Commit: `375951351389`
- Owner: R0 harness
- Environment: macOS 15.5 x86_64; deno 2.9.4
- Network: loopback
- Build configuration: research
- Samples: 30
- Payload: 64 bytes
- Result: pass

## Hypothesis

Measure a WKWebView WebRTC data channel as a direct peer transport without TURN

## Method

1. Create two local RTCPeerConnections inside one WKWebView
2. Create a reliable ordered data channel before the initial offer
3. Exchange host ICE candidates with non-trickle negotiation
4. Echo bounded binary messages and record round-trip time
5. Close both peers and repeat negotiation to measure reconnect

## Raw measurements

```json
{
  "schema_version": 1,
  "run_id": "2026-11-04T230753Z-webrtc-baseline-64b",
  "scenario": "T3",
  "scenario_name": "webrtc-datachannel-loopback-baseline",
  "evidence_scope": "transport-baseline",
  "candidate": "webrtc-datachannel",
  "transport": "webrtc",
  "commit": "375951351389",
  "dirty": false,
  "build": "research",
  "date": "2026-11-04T23:08:09.854Z",
  "environment": {
    "controller": "deno 2.9.4",
    "host": "macOS 15.5 x86_64",
    "browser": "n/a",
    "network": "loopback"
  },
  "samples": 30,
  "metrics": {
    "control_rtt_ms": {
      "p50": 1,
      "p95": 2,
      "p99": 4,
      "min": 1,
      "max": 4
    },
    "messages_delivered": 30,
    "reconnect_ms": 239
  },
  "diagnostics": {
    "server_messages_received": 30,
    "payload_bytes": 64,
    "timeout_ms": 5000,
    "transport_specific": {
      "ice_gathering_state": "complete",
      "local_candidate_types": [
        "host",
        "host",
        "host",
        "host"
      ],
      "remote_candidate_types": [
        "host",
        "host",
        "host",
        "host"
      ],
      "channel_open_ms": 142,
      "reconnect_echo_ms": 2
    }
  },
  "failures": [],
  "observations": "Research measurement; not a product commitment. Working tree was clean. Transport webrtc. Receiver handled 30 messages.",
  "license_notes": "WebKit WebRTC data channels only; no added dependency.",
  "decision": "trial",
  "pass": true
}
```

## Observed failures

None.

## Recovery behavior

Client reconnected in 239 ms and completed an echo exchange.

## Security notes

Loopback only. No credentials, terminal output, prompts or workspace contents were captured. The generated TLS certificate is ephemeral and scoped to this run.

## License/SBOM notes

WebKit WebRTC data channels only; no added dependency.

## Comparison to baseline

Compare with T1/T2 only when host, network, payload and controller runtime are matched; this run uses macOS WKWebView.

## Decision

trial

## What would change the decision

A failed run keeps the candidate on hold. Candidate evidence requires the scenario corpus on recorded hardware and networks.
