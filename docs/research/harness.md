# Fabric Research Harness

- **Status:** R0 implementation — loopback transport smoke runner active
- **Date:** 2026-11-04
- **Parent:** `docs/planning/universal-compute-fabric-research.md`
- **Baseline:** `docs/planning/fabric-research-baseline.md`

## 1. Decision

Use the smallest harness that can produce reproducible evidence:

- **Scenario definitions:** versioned JSON under `research/scenarios/`.
- **Runner scripts:** shell entry points under `scripts/research/`.
- **Raw results:** machine-readable JSON under `docs/research/runs/<date>-<candidate>/`.
- **Reports:** a short markdown report in the same run directory.
- **Existing tests first:** extend `AirDeskTests`, `web/test/` and `scripts/` before adding a new framework.

No new test framework, dashboard or telemetry service is introduced for R0/R1.

## 2. Directory layout

```text
research/
  scenarios/
    transport.json
    loopback-websocket-baseline.json
    webtransport-baseline.json
    webrtc-baseline.json
    iroh-baseline.json
    state.json
    remote-placement.json
    remote-window.json
  iroh-probe/
    Cargo.toml
    Cargo.lock
    src/main.rs
scripts/
  research/
    run-transport.sh
    transport_bench.ts
    run-webrtc-ios.sh
    webrtc_probe.swift
    run-iroh.sh
    run-state.sh
    run-placement.sh
    run-remote-window.sh
docs/
  research/
    dependency-prescreen.md
    fabric-threat-model-delta.md
    harness.md
    runs/
      2026-11-04-websocket-baseline/
        run.json
        report.md
```

The exact scripts are created when the first spike begins. They must fail on missing device, network or build metadata rather than silently producing a partial result.

## 3. Scenario schema

Each scenario file describes a reproducible procedure, not a claim:

```json
{
  "id": "S2",
  "name": "remote-agent-reattach",
  "candidate": "ssh-tmux-baseline",
  "transport": "ssh",
  "requires": ["iphone", "mac-host", "ssh-host"],
  "network": "lan-or-tailnet",
  "payload_bytes": 64,
  "steps": [
    "start remote terminal",
    "generate bounded output",
    "suspend controller",
    "reattach from second device"
  ],
  "metrics": ["reattach_ms", "process_survived", "transcript_truthful"],
  "failure_injection": ["abrupt-disconnect", "app-suspend"],
  "pass": {
    "process_survived": true,
    "transcript_truthful": true
  }
}
```

No scenario may contain credentials, private keys, tokens or personal paths. Use generated fixtures or throwaway accounts.

## 4. Result schema

Every run records at least:

```json
{
  "scenario": "S2",
  "candidate": "ssh-tmux-baseline",
  "transport": "ssh",
  "commit": "dc46125",
  "build": "debug",
  "date": "2026-11-04T12:00:00Z",
  "environment": {
    "controller": "iPhone 16 Pro / iOS 18.6",
    "host": "macOS 15.x",
    "browser": "n/a",
    "network": "LAN 5 GHz"
  },
  "samples": 30,
  "metrics": {
    "reattach_ms": {
      "p50": null,
      "p95": null
    }
  },
  "failures": [],
  "observations": "None",
  "license_notes": "n/a",
  "decision": "trial"
}
```

Use `null` for unavailable measurements. Do not invent values.

## 5. Runner rules

- Record the git commit before starting.
- Record the build configuration and toolchain versions.
- Refuse to run if the required device, host, credentials fixture or network is missing.
- Write raw results before generating a report.
- Keep secrets out of stdout, files and shell history.
- Stop on a failed precondition instead of continuing with a fallback that changes the scenario.
- Treat simulator, LAN, cellular, relay and different hardware as separate result sets.
- Preserve failing runs; do not delete them.

## 6. Baseline commands

Existing checks remain the first regression gate:

```bash
scripts/check-core.sh
scripts/ci-ios.sh
protocol/check.sh
cd web && deno run --allow-all node_modules/vitest/vitest.mjs run
cargo test --manifest-path protocol/rust/Cargo.toml
scripts/research/run-transport.sh
scripts/research/run-transport.sh --scenario research/scenarios/loopback-websocket-baseline.json --payload-bytes 1024
scripts/research/run-transport.sh --scenario research/scenarios/webtransport-baseline.json --payload-bytes 1024
scripts/research/run-transport.sh --scenario research/scenarios/webrtc-baseline.json --payload-bytes 1024
scripts/research/run-webrtc-ios.sh
scripts/research/run-iroh.sh
```

`run-webrtc-ios.sh` runs the opt-in `WebRTCLoopbackProbeTests` in the iOS 18.6 simulator and writes raw probe JSON. The test skips in normal CI unless the simulator probe defaults are enabled.

T3 runs a Swift/WebKit probe on the Mac and records macOS WKWebView behavior, not iOS 18.6 behavior. The iOS repeat requires the device runner.

`run-iroh.sh` builds the separate `research/iroh-probe` Rust crate with its pinned `Cargo.lock`, runs the T4 relay-free loopback scenario at 64 B, 1 KiB and 16 KiB, and writes one JSON result per payload. The probe is research-only and is not part of the product dependency graph.

On the current Linux environment these toolchains are absent. The research runner must execute on the Mac or another qualified host.

### Recorded runner

The iOS T3 repeat runner was recorded on 2026-11-04: iPhone 16 Pro simulator, iOS 18.6, Xcode 16.4 and Swift 6.1.2 on the Mac mini host.

The T4 transport runner was recorded on 2026-11-05: relay-free Iroh 1.4.1 on the same Mac mini host, Cargo 1.98.1, Rust release build, commit `46e9341727b3`, two clean runs at 30 samples per payload.

The first qualified runner was recorded on 2026-11-04:

| Field | Value |
| --- | --- |
| Model | Mac mini (Macmini8,1) |
| CPU | Intel Core i5-4278U, 2.60 GHz |
| Memory | 8 GB |
| OS | macOS 15.5 (24F74) |
| Xcode | 16.4 (16F6) |
| Swift | 6.1.2 |
| Cargo | 1.98.1 |
| Deno | 2.9.4 |

Scope: loopback harness smoke and local Swift/Cargo/Deno checks only. Physical iPhone/iPad, Windows, Linux Xpra and Android runners remain unrecorded. Security review ownership remains unassigned.

## 7. Privacy and security

- No terminal output, prompts, workspace contents or credentials in committed results.
- Use synthetic workloads with bounded input and output.
- Hash or redact host names and device identifiers in published reports.
- Never commit a capture file that contains a session token or private key.
- A failing security scenario is a result, not a reason to loosen the scenario.

## 8. R0 exit checklist

- [x] Harness layout and artifact schema selected.
- [x] Runner rules and baseline commands documented.
- [x] First scenario file created: `research/scenarios/transport.json`.
- [x] First runner script created and smoke-tested: `scripts/research/run-transport.sh`.
- [x] First scenario and runner committed.
- [x] Qualified Mac runner recorded.
- [ ] Physical-device and additional-host runners recorded.
- [ ] Security owner reviews log redaction and fixture handling.

The loopback smoke run was recorded on macOS 15.5 x86_64 with Deno 2.9.4. It validates the runner only; it is not transport-candidate evidence.
