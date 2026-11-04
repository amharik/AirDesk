# Universal Compute Fabric Research Plan

- **Status:** Active — research-first; no product-release commitment
- **Date:** 2026-11-04
- **Scope:** Validate or reject the 100x universal compute fabric before committing product sequencing or implementation
- **Active checkout:** `/tmp/opencode/AirDesk`
- **Supersedes:** The active execution order in `workspace-fabric-plan.md` and `release-roadmap.md` only until the R6 decision gate
- **Related:** ADR-003, ADR-004, ADR-006, ADR-010, ADR-013, ADR-016, ADR-017, ADR-020, `docs/architecture/device-fabric.md`, `docs/architecture/runtime-architecture.md`, `fabric-research-baseline.md`, `docs/research/dependency-prescreen.md`

## 1. Decision

The selected direction is the **universal compute fabric first**, as a **100x research program**, with no product release deadline.

This means:

- The active work is evidence gathering, not Release 1–5 feature sequencing.
- The existing workspace, host, input, runtime-provider and protocol work remains the baseline to test against.
- Research prototypes are governed by ADR-003 `Spike` status and must not leak into production paths.
- Product principles remain promotion gates. “No premature distribution” still applies to shipped features; it does not prohibit isolated research spikes.
- No proposed ADR is promoted, and no new production dependency is admitted, until the R6 decision gate.

“100x” here means a qualitative capability jump, not a claim that every component must be 100 times faster. The research program must prove a coherent fabric, not a collection of benchmarks.

## 2. Definition of the target

A universal compute fabric means:

- One workspace identity spans devices, runtimes, execution locations and display endpoints.
- Devices contribute presentation, execution, storage, input and platform capabilities explicitly.
- Workloads can run locally or remotely under explicit placement, authorization and resource policy.
- A display or runtime disconnect does not recreate or corrupt the workspace.
- Live or checkpointed work can be resumed on a different eligible device where policy allows.
- Remote applications can participate in the local window model rather than appearing as a single streamed desktop.
- Cross-device synchronization and authority handoff have explicit conflict and failure semantics.
- The fabric remains usable without a cloud authority for local operation.

This is not a cloud desktop, a distributed operating system, an automatic cluster scheduler or an implicit multi-writer database.

## 3. What already exists

The research program starts from these implemented or documented assets:

| Asset | Current state | Research use |
| --- | --- | --- |
| Versioned workspace manifest and native store | Implemented | Baseline for state and migration experiments |
| Single-writer `WorkspaceHost` and `host_epoch` | Implemented | Baseline for handoff and multi-device authority experiments |
| Desired/observed state separation | Implemented | Prevents research prototypes from corrupting workspace definitions |
| Runtime provider registry and Wanix adapter | Implemented | Baseline for local and remote placement experiments |
| Input protocol v2 and channel split | Implemented locally; production transport binding open | Baseline for transport latency experiments |
| SSH PTY with pinned host key and tmux default | Implemented | Baseline for remote execution and reconnect experiments |
| Local asset server with COOP/COEP | Implemented | Baseline for browser endpoint experiments |
| External display and Cast development path | Partial | Baseline for presentation experiments |
| ADFP, ADR-010 through ADR-020 | Proposed architecture | Candidate fabric semantics to validate |

The research program must not pretend these assets are complete. It also must not restart them.

## 4. Research questions and kill criteria

| ID | Question | Working hypothesis | Required evidence | Kill or hold criterion |
| --- | --- | --- | --- | --- |
| Q1 | Which direct transport can carry fabric control, reliable edges and stale-tolerant movement without hidden relay? | WebSocket is the baseline; WebTransport/QUIC can improve direct paths; Iroh may solve traversal but is not required | p50/p95 latency, reconnect, CPU, battery, binary size, NAT behavior, WKWebView support, license | A candidate is held if it cannot meet the direct-path budget, cannot fall back cleanly or adds unacceptable client size or distribution risk |
| Q2 | Can workspace state span devices without either silent corruption or a workspace-wide CRDT? | Keep `WorkspaceHost` for structural authority; use explicit merge classes; confine CRDTs to documents or geometry where needed | Conflict corpus, offline edits, host handoff, revocation, crash recovery | A CRDT-first model is rejected if it cannot preserve authority, migration and manual-merge semantics |
| Q3 | Can workloads execute on remote providers while workspace identity and observed-state truthfulness survive? | Remote Wanix/SSH providers fit the existing provider contract; explicit placement is sufficient | Placement matrix, capability leases, provider loss, reconnect, quota enforcement | Remote placement is deferred if failure cannot be made visible and recoverable without rewriting desired state |
| Q4 | Can live or suspended work move between devices? | Cooperative checkpoints are feasible; transparent process migration is not required for the first fabric | State capture, restore fidelity, time-to-resume, provider differences, security | Transparent migration is rejected if it requires unsafe host access or cannot report fidelity honestly |
| Q5 | Can remote application windows behave like local windows? | Xpra-style persistent reattach is the safest Linux path; IronRDP RAIL is a Windows path; macOS needs a separate host agent | Latency, input starvation, reconnect, window identity, GPL/distribution boundary | A remote-windowing backend is held if it cannot preserve window identity or stay outside the client’s copyleft boundary |
| Q6 | Can cross-ISA or legacy workloads run in the portable tier? | v86 is the existing fallback; elfconv and CheerpX are research candidates, not commitments | Startup, throughput, memory, fidelity, license, App Store viability | Cross-ISA execution is rejected if licensing, binary size or performance makes it a product liability |
| Q7 | Can agents be supervised without making `WebMCP` or a browser API a dependency? | Terminal/PTY observation and explicit approval are sufficient for the fabric baseline | Approval flow, audit, prompt injection boundaries, background behavior | WebMCP is deferred if it is unsupported, unsafe or unnecessary for the tested scenarios |
| Q8 | Can a browser endpoint present the fabric without becoming authority? | Loopback host agent plus ADFP is viable; browser storage remains evictable | Pairing, COOP/COEP, reconnect, capability denial, origin policy | Browser hosting stays local-only if origin, asset or threat-model gates fail |

## 5. Scenario corpus

Every spike is evaluated against the same scenarios. A candidate that only works in a demo or on one device is not sufficient.

| ID | Scenario | Pass condition |
| --- | --- | --- |
| T1 | Measure the loopback WebSocket reference transport across payload sizes | Runner records p50/p95/p99 RTT, delivery and reconnect without losing samples |
| S1 | Start on iPhone; present the same workspace in a Mac browser endpoint | Workspace identity, layout and desired state survive session creation |
| S2 | Start a terminal or agent on a remote devbox; detach and reattach from an iPad | Remote work survives controller disconnect; reconnect reports truthfully |
| S3 | Edit workspace layout on two devices while one is offline | Conflict rules converge or fail manually; no silent corruption |
| S4 | Move a qualified WASI workload from local Wanix to a remote provider | Placement is explicit; identity and observed state remain correct |
| S5 | Lose the host while a display session is still running | Input and running runtimes continue; structural writes fail typed; reconnect reconciles |
| S6 | Run an x86 Linux CLI in the portable tier | Startup, throughput, memory and failure modes are measured and bounded |
| S7 | Present a remote application window beside local windows | Focus, z-order, resize, reconnect and input release behave correctly |
| S8 | Revoke a device during an active session | New capability requests fail; existing leases expire or are revoked; workspace remains |

Optional extension scenarios:

- S9: Move a workspace host from phone to desktop agent.
- S10: Resume a checkpointed application on a different eligible device.
- S11: Two controllers with distinct cursors and one keyboard focus owner.
- S12: Browser endpoint on a non-loopback origin, used only to prove why it must remain out of scope.

## 6. Program phases

### R0 — Research harness and baseline (1 week)

Deliverables:

- This plan and the scenario corpus.
- `fabric-research-baseline.md`, including the measurement protocol, candidate matrix and results template.
- `docs/research/dependency-prescreen.md`, covering the initial candidates under ADR-003.
- `docs/research/fabric-threat-model-delta.md`, covering remote execution, host handoff, browser endpoints, remote windows and agent supervision.
- `docs/research/harness.md`, covering the runner layout, scenario schema and result schema.

Exit: each research question has an owner, test method and candidate list.

### R1 — Transport bake-off (2–3 weeks)

Candidates:

- loopback WebSocket baseline;
- WebTransport over HTTP/3 where supported;
- WebRTC data channels;
- Iroh/QUIC;
- SSH/tmux for remote execution comparison;
- no relay, except as an explicitly labeled control experiment.

Measure:

- control and input p50/p95 latency;
- reconnect time and failure classification;
- behavior under packet loss, NAT, sleep/wake and network change;
- CPU, battery, binary size and dependency/license cost;
- WKWebView and browser support.

Gate: choose a primary direct-path candidate, a documented fallback and the conditions under which relay work would be justified. Do not ship a transport dependency from this phase.

### R2 — State and authority bake-off (2–3 weeks)

Candidates:

- current manifest plus `WorkspaceHost` and merge metadata;
- an operation-log synchronization layer;
- Loro or another CRDT for selected domains;
- hybrid: single-writer structure plus CRDT documents or layout.

Build a conflict corpus covering offline edits, host handoff, force takeover, revocation, schema skew, duplicate delivery, partial writes and corrupted journals.

Gate: select a state model that preserves authority, recovery truthfulness and manual resolution where automatic merge is unsafe. Reject CRDT-everything if it cannot pass the corpus.

### R3 — Execution placement and remote namespaces (3–4 weeks)

Experiments:

- remote Wanix lifecycle;
- 9P/WebSocket namespace import with capability scoping;
- SSH-backed terminal and application placement;
- provider loss and circuit-breaker behavior;
- resource references and quotas.

Gate: demonstrate one workload executing remotely with explicit placement, visible observed state and no workspace-authority leak.

### R4 — Checkpoint, restore and cross-ISA research (3–4 weeks)

Experiments:

- cooperative application checkpoint and restore through the existing lifecycle;
- WALI/MVVM-style snapshot experiments, if licensable and testable;
- v86 baseline for legacy x86;
- elfconv and CheerpX feasibility, licensing and App Store review;
- restore fidelity reporting and failed-restore behavior.

Gate: decide whether any checkpoint/migration path is credible beyond cooperative app-level checkpoints. Reject claims that cannot state exactly what was restored or lost.

### R5 — Remote presentation (3–4 weeks)

Experiments:

- Xpra seamless HTML5 integration for Linux;
- IronRDP RAIL/EGFX for Windows;
- macOS ScreenCaptureKit host agent feasibility;
- window identity, input release, reattach and codec fallback.

Gate: show one remote application behaving as a first-class window, or reject the path and keep remote work terminal-only.

### R6 — Integrated walking skeleton and architecture decision (3–4 weeks)

Build a research-only skeleton that demonstrates:

- two devices;
- one workspace identity;
- one remote execution placement;
- one reconnect or handoff;
- one revoked capability;
- one remote presentation path or a documented rejection;
- measured results from S1–S8.

Decision output:

- **Adopt:** update the ADR set and product roadmap, then begin implementation.
- **Hybrid:** keep the local workspace and adopt only proven fabric pieces.
- **Stop:** document why the 100x fabric is not viable and return to the product wedge with the evidence.

No production rewrite begins before this decision.

## 7. Measurement protocol

A result is valid only when it records:

- commit, branch and build configuration;
- device model, OS, browser/WebView and runtime versions;
- network topology, latency and loss assumptions;
- cold versus warm start;
- sample count and p50/p95/p99 where applicable;
- error and recovery behavior, not only happy-path timing;
- binary size, memory, energy and dependency/license impact where relevant;
- the exact scenario and steps to reproduce.

Use the existing `AirDesk/Diagnostics/PerformanceMetrics.swift` where it fits. Do not invent a new metrics abstraction until the existing one proves inadequate.

Do not compare results across devices, simulators and physical networks as if they were equivalent.

## 8. Dependency and security rules

- Every candidate dependency starts as `Spike` under ADR-003.
- No research spike may add executable runtime code to the shipping bundle.
- Record SPDX license, source pin, build recipe and distribution boundary before Trial.
- GPL components that cannot be linked into the client remain server-side only.
- Remote execution and remote windowing require explicit capability leases and input release on disconnect.
- No plaintext transport outside loopback.
- Pairing, host handoff, relay and remote-window credentials require a threat-model update before Trial.
- Browser endpoints remain loopback-only unless a later authorization decision changes the topology.

## 9. Work breakdown

| ID | Task | Output |
| --- | --- | --- |
| RF-00 | Write the research plan and scenario corpus | This document |
| RF-01 | Define the measurement protocol and baseline matrix | `docs/planning/fabric-research-baseline.md` |
| RF-02 | Pre-screen transport candidates | Transport decision matrix |
| RF-03 | Pre-screen state candidates and build conflict corpus | State decision matrix |
| RF-04 | Build remote placement prototype | R3 demonstration and report |
| RF-05 | Run checkpoint/cross-ISA feasibility | R4 report with license and App Store notes |
| RF-06 | Run remote-presentation feasibility | R5 report |
| RF-07 | Build the integrated walking skeleton | R6 demonstration and architecture decision |

## 10. Exit criteria for the research track

The research track is complete only when:

- every Q1–Q8 question has a written answer with evidence or a documented rejection;
- the scenario corpus has pass/fail results on the supported matrix;
- candidate dependencies have license, size, platform and exit-strategy records;
- the R6 decision names the architecture to adopt, the pieces to defer and the pieces to stop;
- the result is recorded in the ADR set and roadmap before product implementation resumes.
