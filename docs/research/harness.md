# Fabric Research Harness

- **Status:** R0 implementation — loopback and two-host transport runners active
- **Date:** 2026-11-05
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
    iroh-tailnet-baseline.json
    iroh-relay-fallback.json
    ssh-reattach-baseline.json
    ssh-termination-baseline.json
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
    run-iroh-net.sh
    run-iroh-relay.sh
    run-ssh-reattach.sh
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
      2026-11-05T184314Z-ssh-reattach-baseline/
        run.json
        report.md
        test-summary.log
      2026-11-05T185114Z-ssh-termination-baseline/
        run.json
        report.md
        test-summary.log
```

The exact scripts are created when the first spike begins. They must fail on missing device, network or build metadata rather than silently producing a partial result.

## 3. Scenario schema

Each scenario file describes a reproducible procedure, not a claim:

```json
{
  "id": "S2",
  "name": "ssh-tmux-reattach-baseline",
  "candidate": "ssh-tmux-baseline",
  "transport": "ssh",
  "requires": ["mac-host", "ios-simulator", "ssh-host", "tmux", "tailnet-network"],
  "network": "tailnet",
  "steps": [
    "start remote terminal with a heartbeat",
    "background the controller",
    "reattach from the same controller",
    "verify new remote output"
  ],
  "metrics": ["reattach_ms", "process_survived", "transcript_truthful"],
  "failure_injection": ["app-background-and-ssh-drop"],
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
AIRDESK_IROH_SERVER_SSH=user@tailnet-host AIRDESK_IROH_SERVER_IP=<tailnet-ipv4> scripts/research/run-iroh-net.sh
AIRDESK_IROH_SERVER_SSH=user@tailnet-host scripts/research/run-iroh-relay.sh
AIRDESK_S2_REMOTE_SSH=user@tailnet-host AIRDESK_SIMULATOR_ID=<simulator-udid> scripts/research/run-ssh-reattach.sh
AIRDESK_S2_MODE=termination AIRDESK_S2_REMOTE_SSH=user@tailnet-host AIRDESK_SIMULATOR_ID=<simulator-udid> scripts/research/run-ssh-reattach.sh
scripts/real-ssh-smoke.sh
```

`run-webrtc-ios.sh` runs the opt-in `WebRTCLoopbackProbeTests` in the iOS 18.6 simulator and writes raw probe JSON. The test skips in normal CI unless the simulator probe defaults are enabled.

T3 runs a Swift/WebKit probe on the Mac and records macOS WKWebView behavior, not iOS 18.6 behavior. The iOS repeat requires the device runner.

`run-iroh.sh` builds the separate `research/iroh-probe` Rust crate with its pinned `Cargo.lock`, runs the T4 relay-free loopback scenario at 64 B, 1 KiB and 16 KiB, and writes one JSON result per payload. The probe is research-only and is not part of the product dependency graph.

`run-iroh-net.sh` runs the same probe across two hosts. It copies the crate to the remote SSH target, builds it there, binds the server to the remote tailnet IPv4 address with Iroh relays disabled, and runs the Mac client against the explicit endpoint ID plus direct address. It records the Tailscale underlay path (`tailscale-direct` or `tailscale-derp`) in `run-index.json` because a Tailscale DERP hop is outside Iroh but still a relay dependency. The local Linux workspace container lacks the Rust toolchain; the Mac is the client and the remote Linux runner is the server. Neither is a product dependency.

`run-iroh-relay.sh` copies the same probe to the remote host and runs the forced relay-only scenario. It binds both ends with `RelayMode::Default`, clears IP transports, waits for the server's home relay, and connects the Mac client by endpoint ID plus the assigned relay URL. It writes `iroh-relay-fallback` JSON with relay/direct path counts and fails unless the selected path is relay. The 2026-11-05 run passed 90/90 through the public n0 relay `aps1-1.relay.n0.iroh.link` at p50 108.8/106.1/183.9 ms for 64 B/1 KiB/16 KiB. This is not automatic direct-to-relay fallback and the public relay map is not accepted for the product.

`real-ssh-smoke.sh` is the SSH/tmux interop smoke, not an S2 result. It starts a temporary local Mac OpenSSH server on `127.0.0.1:22222` with generated Ed25519 keys, optionally uses `tmux new -A -s <smoke-session>` as the startup command, and runs the opt-in `RealSSHTerminalTests` in the iOS 18.6 simulator. It does not exercise app suspension, a second device, a remote network or transcript truthfulness.

`run-ssh-reattach.sh` is the S2 runner. It requires a Mac controller, a remote Linux/macOS SSH host with tmux, a booted iOS simulator and a tailnet path. It generates a throwaway Ed25519 key, appends it to the remote `authorized_keys`, pins the remote host key, starts a unique tmux session with a remote heartbeat, writes the test defaults, runs the configured cycle mode and writes a run directory with `run.json`, `report.md` and `test-summary.log`. `AIRDESK_S2_MODE=background` (default) backgrounds each cycle; `AIRDESK_S2_MODE=termination` terminates the app process and measures cold relaunch recovery. Both modes use `-AirDeskUITestOpenPreview` to avoid menu-navigation flakiness. It records whether the Tailscale underlay is direct or DERP-relayed. The 2026-11-05 runs completed 3/3 background reattaches and 3/3 termination recoveries with process survival and truthful transcripts; physical-device and second-device coverage remain open.

### Recorded runner

The iOS T3 repeat runner was recorded on 2026-11-04: iPhone 16 Pro simulator, iOS 18.6, Xcode 16.4 and Swift 6.1.2 on the Mac mini host.

The T4 loopback runner was recorded on 2026-11-05: relay-free Iroh 1.4.1 on the same Mac mini host, Cargo 1.98.1, Rust release build, commit `46e9341727b3`, two clean runs at 30 samples per payload.

The T4 two-host tailnet runner was recorded on 2026-11-05: macOS client at `2beb77a37cdd`, Debian 13 x86_64 server with Cargo 1.99.1, two clean runs at 30 samples per payload. The Tailscale underlay was DERP-relayed in both runs; the additional-host runner is recorded, but a direct-underlay path is not.

The T4 relay-only runner was recorded on 2026-11-05: macOS client at `e4f9eeeb6b09`, Debian 13 x86_64 server with Cargo 1.99.1, 30 samples per payload and three clean runs. The public n0 home relay was `https://aps1-1.relay.n0.iroh.link./`; all 90 deliveries selected the relay path. The Tailscale SSH control underlay was DERP-relayed.

The S2 runner was recorded on 2026-11-05: iPhone 16 Pro simulator `3B46FDF8-1482-4517-99F3-D6EF46A85133` on iOS 18.6, Xcode 16.4, macOS 15.5 x86_64, remote Debian 13 x86_64 host `sillygirl` with tmux 3.5a, commit `472537a22a19`, 3 cycles and a 5-second background. The auto-preview background run reattached 3/3 at p50 6.9 s (max 8.2 s); the termination run recovered 3/3 at p50 57.6 s (max 70.8 s) for the full cold relaunch path. The Tailscale underlay was DERP-relayed.

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
- [x] Additional-host runner recorded for the T4 tailnet spike.
- [ ] Physical-device runner recorded.
- [ ] Security owner reviews log redaction and fixture handling.

The loopback smoke run was recorded on macOS 15.5 x86_64 with Deno 2.9.4. It validates the runner only; it is not transport-candidate evidence.
