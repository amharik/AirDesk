# Fabric Research Baseline and Measurement Protocol

- **Status:** R0 baseline — T1 WebSocket, T2 WebTransport, T3 WebRTC and T4 Iroh/QUIC loopback measurements recorded; T3 repeated in the iOS 18.6 simulator; T4 repeated across two hosts on a DERP-relayed tailnet and on a forced public-relay path; SSH/tmux pre-screen complete and S2 simulator reattach passes 3/3 on a DERP-relayed tailnet
- **Date:** 2026-11-05
- **Parent:** `universal-compute-fabric-research.md`
- **Scope:** Reproducible measurement rules, candidate matrix, scenario procedures and results template for the universal compute fabric research track

## 1. Purpose

This document keeps the 100x research program honest. It defines how a candidate becomes evidence rather than a demo.

A valid result must identify:

- the exact change set and build;
- the device, OS, runtime and browser/WebView versions;
- the network path and failure injection;
- the scenario being exercised;
- the measured metric and sample count;
- what failed, what recovered and what was lost.

No result may be generalized across simulator, physical device, LAN, relay or different hardware without a separate run.

## 2. Baseline matrix

The matrix is filled as hardware and candidate builds become available. “Required” means the scenario must run before a candidate can advance. “Optional” means it informs the decision but does not block R0/R1.

| Environment | Role | Current baseline | Required for |
| --- | --- | --- | --- |
| iPhone 16 Pro, iOS 18.6 | Controller and workspace host | Simulator tests pass; T3 WebRTC probe passes in the simulator; real-device signing blocked | S1, S2, S3, S5, S8 |
| iPad simulator | Second controller/display | UI suite exists | S1, S3, S11 |
| Mac, macOS + Xcode | Native host, SSH host, browser endpoint | Swift/Xcode/cargo/Deno available on the Mac | S1, S2, S4, S5, S7 |
| Mac browser | Presentation endpoint | Loopback asset server exists | S1, S8 |
| Linux devbox | Remote execution | SSH/tmux path exists | S2, S4 |
| Windows host | Remote application window | No implementation | S7 |
| Linux Xpra host | Remote application window | No implementation | S7 |
| Android device | Browser/native agent | No implementation | Optional |
| Chromium/Firefox browser | Threaded browser candidate | Not baseline | Optional |

Hardware availability must be recorded per run. A missing device is reported as missing, not replaced by a simulator result.

## 3. Baseline candidates

### 3.1 Transport

| Candidate | Baseline role | License and platform questions | Exit strategy |
| --- | --- | --- | --- |
| Loopback WebSocket | Required reference | Existing local asset server and bridge | Keep as fallback |
| WebTransport over HTTP/3 | Browser/native candidate | Safari/WKWebView support starts at 26.4, so iOS 17–26.3 need a fallback; `serverCertificateHashes`, ECDSA certificate handling | Hold for the iOS 18.6 baseline; WebSocket fallback |
| WebRTC data channels | Direct-peer candidate | macOS WKWebView and iOS 18.6 simulator loopback work with host candidates; physical device, TURN fallback and silent-loss behavior remain open | Adapter behind transport interface; trial only |
| Iroh/QUIC | Direct-peer research candidate | Relay-free loopback and two-host tailnet pass in Rust; the tailnet underlay was DERP-relayed, so direct NAT traversal remains unproven. A forced relay-only run passes 90/90 at p50 108.8/106.1/183.9 ms for 64 B/1 KiB/16 KiB through the public n0 relay, but does not prove automatic fallback or self-hosted relay operation | Spike only until R1 gate |
| SSH/tmux | Remote execution reference | Native NIOSSH path with pinned host key, Keychain password and tmux default; license/platform pre-screen passes; S2 simulator reattach passes 3/3 at p50 5.7 s and max 14.2 s, with 3/3 process survival and truthfulness on a DERP-relayed tailnet | Keep for remote host workflows; physical-device and second-device reattach remain open |

### 3.2 State and authority

| Candidate | Baseline role | Questions | Exit strategy |
| --- | --- | --- | --- |
| Manifest + `WorkspaceHost` | Required reference | Single-writer availability, handoff, degraded mode | Keep local authority |
| Operation log over host sequencer | Synchronization candidate | Ordering, replay, compaction and recovery cost | Adapter behind store/sync boundary |
| Loro or equivalent CRDT | Selected-domain candidate | Merge semantics, binary size, Swift/WASM support, schema migration | Confine to documents or geometry; do not replace identity/placement |
| Hybrid | Likely candidate | Which domains can merge automatically, which stay manual | Explicit merge-class policy |

### 3.3 Execution and migration

| Candidate | Baseline role | Questions | Exit strategy |
| --- | --- | --- | --- |
| Local Wanix provider | Required reference | Existing runtime provider path | Keep local provider |
| Remote Wanix over 9P/WebSocket | Remote placement candidate | Namespace scoping, latency, leases, failure modes | Provider adapter |
| SSH-backed terminal/application | Remote placement reference | Existing SSH PTY; no application model yet | Keep terminal baseline |
| Cooperative checkpoint | First migration candidate | App support, fidelity reporting, provider differences | Keep existing checkpoint lifecycle |
| WALI/MVVM-style snapshot | Research candidate | Kernel/runtime dependency, security, source availability | Hold unless a named workload requires it |
| v86 | Legacy x86 baseline | Startup, throughput, memory, security | Keep as fallback for named workloads |
| elfconv | Cross-ISA research candidate | Build reproducibility, syscall fidelity, license | Reject if not reproducible |
| CheerpX | Cross-ISA research candidate | Commercial license, App Store terms, performance | Reject if distribution or cost is unacceptable |

### 3.4 Remote presentation

| Candidate | Baseline role | Questions | Exit strategy |
| --- | --- | --- | --- |
| No remote window | Required fallback | Remote terminal already works | Keep terminal-only mode |
| Xpra seamless | Linux candidate | GPL server-side boundary, HTML5 adapter, reattach | Server-only; no GPL in client |
| IronRDP RAIL/EGFX | Windows candidate | Rust/UniFFI, WASM client, codec, NLA proxy | Isolated adapter |
| macOS ScreenCaptureKit host | macOS candidate | Screen-recording/accessibility permissions, per-window capture | Separate host agent |

### 3.5 Agent and browser dependencies

| Candidate | Baseline role | Questions | Exit strategy |
| --- | --- | --- | --- |
| PTY/tmux observation | Agent baseline | Session discovery, notifications, approval capture | Keep as default |
| Optional remote hook | Agent enhancement | Authentication, prompt injection, data exposure | Feature-flagged |
| WebMCP | Browser/agent research only | WebKit support, security boundary, actual need | Defer or reject if unsupported |
| Loopback browser endpoint | Presentation candidate | COOP/COEP, origin, pairing, evictable storage | Local-only unless separately authorized |

## 4. Metric definitions

| Metric | Definition | Unit |
| --- | --- | --- |
| Control latency | Message dispatch to authenticated peer acknowledgement | ms, p50/p95/p99 |
| Input-to-frame latency | Controller dispatch to display-side frame application | ms, p50/p95/p99 |
| Reconnect time | Disconnect detection to restored usable session | ms, p50/p95 |
| Cold start | Process launch to first interactive workspace | ms |
| Warm restore | Process launch to a restored workspace with truthful report | ms |
| Remote placement time | Placement request to running observed state | ms |
| Checkpoint time | Checkpoint request to confirmed checkpoint | ms |
| Restore time | Restore request to usable application state | ms |
| Restore fidelity | Explicit restored/restarted/lost fields | categorical |
| Remote window latency | Input dispatch to decoded frame presentation | ms, p50/p95 |
| Terminal throughput | Bytes parsed and rendered per second under a recorded workload | MB/s |
| Drop/discard rate | Movement frames discarded as stale | percent |
| Recovery failure | Runs that cannot reach a truthful usable state | count |
| Binary size delta | Incremental install size attributable to the candidate | MB |
| Memory delta | Steady-state and peak memory attributable to the candidate | MB |
| Energy delta | Battery drain over a fixed scenario | percent/hour, if measurable |
| Dependency risk | License, maintainer, pin, SBOM and exit-strategy status | categorical |

## 5. Scenario procedures

### T1 — Loopback WebSocket transport baseline

1. Select `research/scenarios/loopback-websocket-baseline.json`.
2. Run `scripts/research/run-transport.sh --payload-bytes 64`, then repeat for `1024` and `16384`.
3. Verify every sample is echoed byte-for-byte and the client reconnects.
4. Record p50/p95/p99 RTT, delivery count, reconnect time and the exact payload size.
5. Treat this as a reference measurement, not a comparison with an unimplemented candidate.

### T2 — WebTransport over HTTP/3 baseline

1. Select `research/scenarios/webtransport-baseline.json`.
2. The runner generates an ephemeral local certificate, DER hash and QUIC endpoint.
3. Run the same payload sizes as T1 and verify stream echo plus session reconnect.
4. Record p50/p95/p99 RTT, delivery count, reconnect time and any TLS/QUIC setup failure.
5. Compare with T1 only when host, network and payload sizes match.

### T3 — WebRTC data channel baseline

1. Select `research/scenarios/webrtc-baseline.json`.
2. Create two local peer connections inside one WKWebView and negotiate a reliable ordered data channel.
3. Run the same payload sizes as T1 and verify binary echo plus peer reconnect.
4. Record p50/p95/p99 RTT, delivery count, channel open time, reconnect time and ICE candidate types.
5. Report the controller runtime; macOS WKWebView and iOS WKWebView are separate scopes.

### T4 — Iroh/QUIC loopback, tailnet and relay baselines

1. Select `research/scenarios/iroh-baseline.json` for loopback, `research/scenarios/iroh-tailnet-baseline.json` for two hosts or `research/scenarios/iroh-relay-fallback.json` for the forced relay path.
2. Build the pinned `research/iroh-probe` crate with Cargo release mode.
3. For direct runs, bind with `RelayMode::Disabled` and connect by endpoint ID plus an explicit direct address.
4. For the relay run, bind with `RelayMode::Default`, clear IP transports, wait for the home relay, and connect by endpoint ID plus the assigned relay URL.
5. Run the same payload sizes as T1 and verify bidirectional stream echo plus connection reconnect.
6. Record p50/p95/p99 RTT, direct/relay address counts and paths, first connect, reconnect time and delivery failures.
7. For the tailnet run, record whether the Tailscale underlay is direct or DERP-relayed.
8. Treat these as Rust API baselines; do not generalize to WKWebView, NAT traversal, automatic direct-to-relay fallback or self-hosted relay operation.

### S1 — Cross-endpoint presentation

1. Create or open a workspace on the host.
2. Connect a Mac browser endpoint over the documented path.
3. Verify workspace identity, layout, desired state, focus ownership and input release on disconnect.
4. Record cold/warm start and reconnect time.
5. Fail if the endpoint becomes authority, rewrites identity or silently loses layout.

### S2 — Remote agent or terminal reattach

1. Start a remote SSH/tmux session from the phone.
2. Generate output while detaching the controller or suspending the app.
3. Reattach from the same or a second device.
4. Verify the remote process survived, the transcript is truthful and no keys remain pressed.
5. Record reattach time and failure classification.

Status: simulator pass. The 2026-11-05 run used an iPhone 16 Pro simulator on iOS 18.6, a remote Debian 13 host (`sillygirl`), tmux 3.5a and a DERP-relayed tailnet path. All 3 cycles reattached (5.7 s p50, 4.7–14.2 s), the tmux heartbeat process survived 3/3, and new output was visible 3/3. This does not cover physical-device backgrounding, a second device, app termination, a direct-underlay path or keys-held-on-disconnect behavior.

### S3 — Offline multi-device state

1. Open the same workspace on two eligible devices.
2. Disconnect one device.
3. Apply non-conflicting changes, then conflicting changes.
4. Reconnect and reconcile.
5. Verify declared merge behavior and manual escalation; fail on silent divergence.

### S4 — Remote placement

1. Start a qualified workload locally.
2. Request explicit remote placement on an eligible provider.
3. Verify provider identity, capability lease, observed state and resource references.
4. Lose the remote provider and verify typed failure and desired-state preservation.
5. Record placement and failure timings.

### S5 — Host loss and degraded mode

1. Open a workspace with a live display and a running workload.
2. Suspend or kill the host.
3. Verify running workloads and input leases continue; structural writes fail typed.
4. Reconnect the host and reconcile.
5. Verify no second writer or silent queue exists.

### S6 — Cross-ISA workload

1. Select a named CLI workload with known inputs and output.
2. Run it in v86, elfconv and CheerpX where available.
3. Record cold start, runtime, memory, output fidelity, failure modes and license constraints.
4. Fail any candidate that cannot reproduce output or cannot be distributed lawfully.

### S7 — Remote application window

1. Launch a supported remote application on a Windows, Linux or macOS host.
2. Map it to an AirDesk window identity.
3. Exercise focus, move, resize, minimize, restore, close and reconnect.
4. Disconnect, blur and revoke input; verify no stuck keys or buttons.
5. Record input-to-frame latency and reattach fidelity.

### S8 — Capability revocation

1. Pair a device and issue a scoped capability lease.
2. Revoke the device during active use.
3. Verify new requests fail, existing leases expire or are revoked and the workspace remains.
4. Verify no stale credential survives reconnect or host handoff.

## 6. Failure injection

At minimum, record results under:

- clean LAN;
- added latency;
- packet loss;
- abrupt disconnect;
- network change;
- app background/suspend;
- host unavailable;
- provider unavailable;
- clock/skew and replay attempts;
- revoked capability;
- corrupted or future-schema state.

Failure injection must be documented. A happy-path run is not a qualification.

## 7. Results file template

Each spike report should use this structure:

```text
Title:
Date:
Candidate and version:
Commit:
Owner:
Scenario:
Environment:
Network:
Build configuration:
Hypothesis:
Method:
Raw measurements:
Observed failures:
Recovery behavior:
Security notes:
License/SBOM notes:
Comparison to baseline:
Decision: adopt | trial | hold | reject
What would change the decision:
```

Reports live under `docs/research/runs/`. Recorded harness baselines:

- T1: `docs/research/runs/2026-11-04-loopback-websocket-baseline.md`
- T2: `docs/research/runs/2026-11-04-webtransport-baseline.md`
- T3: `docs/research/runs/2026-11-04-webrtc-baseline.md`
- T3 iOS simulator: `docs/research/runs/2026-11-04-webrtc-ios-baseline.md`
- T4 loopback: `docs/research/runs/2026-11-05-iroh-baseline.md`
- T4 two-host tailnet: `docs/research/runs/2026-11-05-iroh-tailnet-baseline.md`
- T4 forced public relay: `docs/research/runs/2026-11-05-iroh-relay-fallback.md`
- S2 simulator SSH/tmux reattach: `docs/research/runs/2026-11-05T171939Z-ssh-reattach-baseline/report.md`

Candidate comparisons across recorded networks remain open. The T4 tailnet run used a DERP-relayed Tailscale underlay, so it is a separate network label and not a direct-underlay result. The T4 relay run cleared IP transports on both ends and used the public n0 relay map, so it is a forced relay-only result, not an automatic fallback or self-hosted-relay result. SSH/tmux is a stream/session reference and is not part of the T1–T4 payload comparison; its S2 simulator baseline passes 3/3 but still needs physical-device, second-device and direct-underlay evidence.

## 8. R0 exit checklist

- [x] Research plan and scenario corpus written.
- [x] Measurement definitions and baseline matrix written.
- [x] Candidate dependency pre-screen drafted in `docs/research/dependency-prescreen.md`; formal ADR-003 review pending.
- [x] Threat-model delta drafted in `docs/research/fabric-threat-model-delta.md`; security review pending.
- [x] Harness location, artifact schema and automation approach selected in `docs/research/harness.md`.
- [ ] First scenario and runner script committed and smoke-tested.
- [ ] Owners and hardware availability recorded.
