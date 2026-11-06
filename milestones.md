# AirDesk implementation milestones

Status: active
Last updated: 2026-11-06

This file is the implementation tracker. `docs/adr/README.md` remains authoritative for decision status. This file tracks execution order, acceptance criteria and current progress. Update it whenever a work item changes state.

## Status legend

| Status | Meaning |
| --- | --- |
| `Done` | Code, tests and the relevant doc/status update are merged |
| `In progress` | Actively being implemented in the current change |
| `Pending` | Not started, dependencies satisfied or tracked |
| `Blocked` | Waiting on a decision, dependency or hardware |

## Current focus

- Milestone: `M8` — universal compute fabric research
- Track: `100x research first`; product release sequencing is paused until the R6 architecture decision gate
- Work item: `RF-00`, `RF-01` and `RF-02` are active; R0 has the research plan, dependency pre-screen, threat-model delta, harness and qualified Mac runner; R1 has loopback WebSocket, WebTransport and WebRTC baselines at 64 B, 1 KiB and 16 KiB; T3 also passes in the iOS 18.6 simulator; T4 relay-free Iroh/QUIC passes on loopback and across two hosts on a tailnet, but the tailnet underlay was DERP-relayed; the forced Iroh relay-only run passes 90/90 through the public n0 relay at p50 108.8/106.1/183.9 ms; ADR-021 adopts Iroh for the native peer data plane and `XPORT-05` wires the official Swift SDK adapter into the app with ticket pairing, path diagnostics, explicit remote-lease input and WebSocket fallback; the SSH/tmux pre-screen is complete; S2 simulator background reattach and app-termination recovery both pass 3/3, and second-device handoff passes 1/1, with process survival and truthful transcripts on a DERP-relayed tailnet
- Next: repeat T3 and S2 on the physical iPhone when signing is available, add a labeled Wi-Fi/tailnet path with and without TURN, establish a direct Tailscale/LAN underlay and repeat T4, exercise automatic direct-to-relay fallback and a self-hosted relay, and exercise the XPORT-05 pairing flow on two physical devices before the R1 decision; WebTransport is held on iOS 18.6 because WKWebView support starts at iOS 26.4; do not promote research spikes or dependencies
- Retained implementation state: `M0-03`, `RT-02`, `RT-03`, `RT-05`, `RT-06`, `APP-02`, `APP-05`, `IN-01`, `IN-04`, `IN-06`, `IN-07` and `INPUT-01` are complete; `RT-04` is blocked on a native execution engine/package decision; `IN-02` channel routing and validation are in place, with the production transport binding still open

## Verification status

Real iPad testing is parked by request. On 2026-11-06, `scripts/check-core.sh` runs 121 workspace-core and input tests successfully on macOS via SwiftPM; the full `AirDeskTests` target runs 256 tests with 1 skip and 0 failures on an iPhone 16 Pro simulator (iOS 18.6), including the Iroh transport, codec, peer loopback and session-integration tests; `xcodebuild build-for-testing` for the generic iOS Simulator destination succeeds with `CODE_SIGNING_ALLOWED=NO`; `protocol/check.sh` passes; and the Rust protocol crate passes 10 tests. The full web Vitest suite passes 56 tests when invoked through Deno against the installed Node modules, while a native Node executable remains unavailable locally. Device signing still fails with `Certificate installation failed ... Code=-61 "Write permissions error."` even after the login keychain exposes valid Apple Development identities, because Xcode cannot use the private-key ACL over SSH. Device verification will resume from a GUI Xcode session with a one-time "Always Allow" keychain prompt.

## Release 1 scope freeze

Release 1 is a single-device workspace with one authoritative host, persisted desired state, truthful recovery, local runtime providers, and the input protocol compatibility path. It includes no fabric membership, no multi-device synchronization, no capability grants between devices, no browser endpoint and no distributed placement. Those remain Release 2–5 work and must not be pulled into Release 1 acceptance.

## M0 — Plan reset and guardrails

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| M0-01 | Write `milestones.md` and make it the execution tracker | Done | — | Plan is committed and linked from this file |
| M0-02 | Update `docs/planning/workspace-fabric-plan.md` for ADR-020 and round-3 decisions | Done | M0-01 | Plan references `WorkspaceHost`, split WASI targets, movement-only input and browser loopback-only |
| M0-03 | Add protocol guardrails: `flatc --conform`, generated drift, cross-language fixtures | Done | — | CI fails on schema drift; Swift/TS/Rust fixtures round-trip |
| M0-04 | Decide protocol compatibility: negotiated v1 legacy + v12, or hard cutover | Done | — | Decision recorded in ADR-008/010 and milestones |
| M0-05 | Freeze Release 1 scope | Done | — | Single-device workspace only; fabric deferred to Release 2 |

## M1 — Workspace core (Release 1)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| WS-01 | `WorkspaceManifest` v1 schema | Done | M0-05 | Identity, revision, `workspaceSeq`, `hostEpoch`, desired state, resources, layout and merge metadata encode/decode |
| WS-02 | Native `WorkspaceStore` | Done | WS-01 | Atomic revision commit, `expectedRevision`, journal append/replay, `fsync`/`F_FULLFSYNC`, typed errors |
| WS-03 | Desired/observed separation | Done | WS-02 | Observed runtime/application state never mutates the manifest |
| WS-04 | Layout persistence | Done | WS-01 | Window identity, bounds, display and focus order restore without DOM state |
| WS-05 | Recovery test suite | Done | WS-02, WS-03, WS-04 | Relaunch, corruption, future schema, disk-full and interrupted-write tests |
| WS-06 | Merge metadata enforcement | Done | WS-01 | Every syncable field is `lww`, `append-log` or `manual`; unknown defaults to `manual` |
| HOST-01 | Single-device `WorkspaceHost` | Done | WS-02 | Only host commits; `workspaceSeq` contiguous; `hostEpoch` present; host-degraded typed error |
| ORCH-01 | Minimal `WorkspaceOrchestrator` | Done | HOST-01 | Open, attach, place, reconcile above `SessionCoordinator`; no workspace mutation from sessions |
| UX-01 | Truthful restore report | Done | WS-03 | UI states restored, restarted, reconnected or lost |

Exit: the app boots from a manifest instead of `Workspace.default`, survives relaunch, and reports recovery truthfully.

## M2 — Runtime and application model (Release 1)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| RT-02 | Runtime provider registry | Done | M1 | Providers advertise worlds/capabilities; selection and unavailable states are typed |
| RT-03 | Wanix provider adapter extraction | Done | RT-02 | Wanix lifecycle is provider-managed; workspace does not read Wanix internals |
| RT-04 | Native provider path | Blocked | RT-02 | Native execution works without Wanix; blocked on an embedded native/WASI 0.2 execution engine and native package format |
| RT-05 | Per-provider WASI worlds | Done | RT-02 | Wanix runs `wasip1`; native runs all split `@0.2` worlds; unsupported pairs fail closed |
| RT-06 | Single-threaded profile | Done | RT-03 | Starts without `SharedArrayBuffer`; sync WASI fails with `SynchronizationUnavailable` |
| APP-02 | Application manifest and lifecycle | Done | RT-02, WS-01 | Install, start, suspend, stop and observed status work |
| APP-03 | World/version pinning | Done | APP-02, RT-05 | Manifest pins the qualified `(provider, world)` pair |
| APP-04 | Quota enforcement matrix | Done | APP-02 | Unenforceable required quota fails placement with `QuotaUnenforceable` |
| APP-05 | Cooperative checkpoint lifecycle | Done | APP-02 | `SUSPENDED_CHECKPOINTED` only after app checkpoint; no process snapshot |
| UX-02 | Restore and degraded-mode UI copy | Done | UX-01, HOST-01 | Host-degraded and recovery outcomes are visible and truthful |

Exit: provider-neutral placement, explicit world support, no production just-bash path.

## M3 — Input protocol v2 (parallel with M1/M2)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| IN-01 | 16-byte movement frame (`0xA5`) | Done | M0-04 | Movement only; no edges; negotiated version; fuzz-tested |
| IN-02 | Channel 1/1R split | In progress | IN-01 | Edges on reliable ordered channel; movement on datagram/ordered WebSocket with `seq` discard |
| IN-03 | Connection-derived context | Done | IN-02 | Session/generation/controller never trusted from the packed frame |
| IN-04 | Lease epoch at display sink | Done | IN-02 | `SessionCoordinator` owns `leaseEpoch`; stale edge returns `EpochRejected`; resets with generation |
| IN-05 | Shared cursor and pinned roles | Done | IN-04 | Pinned driver cannot move shared cursor or emit keyboard/text/focus |
| IN-06 | Latency probe | Done | IN-02 | Channel 0 probe measures latency; no fake per-frame timestamps |
| IN-07 | Conformance and fuzz gates | Done | IN-01, IN-02 | Swift/TS/Rust round-trip/fuzz gates and valid-envelope FlatBuffers `0xA5` collision corpus pass |

Exit: old and new paths negotiate cleanly; no input edge is ever sent on Channel 1.

## M4 — Identity and capabilities (Release 2)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| ID-01 | Device identity and QR/PIN pairing | Pending | M3, M1 | Ed25519 default, P-256 fallback; SPAKE2+; nonce/expiry; replay rejected |
| ID-02 | Native/browser channel binding | Pending | ID-01 | Native TLS exporter; browser host-cert hash from pairing payload or signed advertisement |
| ID-03 | Device registry and revocation | Pending | ID-01 | Revocation invalidates trust and leases without deleting workspaces |
| ID-04 | Canonical discovery | Pending | ID-01 | `_airdesk._tcp`/`_airdesk._udp`, canonical TXT keys, no `dev_id`/`role_mask` |
| CAP-01 | Capability registry | Pending | ID-03 | `cap_uri`, four-value availability, advertisement distinct from authorization |
| CAP-02 | Grants and leases | Pending | CAP-01 | `COSE_Sign1`, `jti`, `cnf`, `epoch_id = generation`; provider/owner root grant; coordinator cannot mint |
| HOST-02 | Host handoff | Pending | ID-03, HOST-01 | Quiesce/stage/activate/retire; force takeover; stale `host_epoch` demotes |
| HOST-03 | Host-degraded mode | Pending | HOST-02 | Structural writes fail typed; running runtimes and leased input continue |

Exit: pairing grants no ownership; grants are provider-issued; handoff and force takeover are tested.

## M5 — Fabric and agents (Release 2)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| PROTO-01 | ADFP baseline | Pending | M3 | Envelope, AD-WS/DEV/CAP/RUNTIME/RESOURCE/INPUT/DISPLAY |
| PROTO-02 | Resource RPC surface | Pending | PROTO-01 | ADFP op codes, not 9P2000 tags; `Qid` layout only |
| AGENT-01 | Native agent contract | Pending | ID-01 | Identity, capabilities, permissions, health and lifecycle |
| AGENT-02 | iOS device agent | Pending | AGENT-01 | Camera, files, input and health under iOS permissions |
| ABI-01 | WIT capability host ABI | Pending | AGENT-01 | Per-runtime conformance; WASI 0.2 baseline; 0.3 uses `stream<T>` |
| INPUT-01 | Multi-controller arbitration | Done | IN-05 | Distinct cursors; single keyboard focus; guarded `force_preempt`; no stuck input |
| XPORT-01 | Direct transport benchmark | In progress | AGENT-02 | WebRTC/QUIC vs WebSocket p50/p95, CPU, reconnect |
| XPORT-02 | Direct transport qualification | Pending | XPORT-01 | ADR-013 updated with evidence; relay remains absent |
| XPORT-04 | Iroh native transport adapter | Done | ADR-021 | `IrohLib` 1.2.0, direct-only default, explicit self-hosted relay policy, channel framing, movement datagrams, diagnostics and loopback tests |
| XPORT-05 | Iroh session integration | Done | XPORT-04 | Adapter wired through `IrohFabricPeer`, `AppEnvironment`, settings, input routing and diagnostics; ticket pairing, explicit remote-lease input, movement datagrams, path/relay status and WebSocket fallback covered by loopback tests |

Exit: a paired device provides an authorized capability; disconnect preserves workspace; no relay is required.

## M6 — Display endpoints (Release 3)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| END-01 | Browser endpoint feasibility spike | Pending | M5 | Loopback, COOP/COEP, secure context, asset isolation proven |
| END-02 | Local host agent | Pending | END-01 | Loopback WebSocket, strict origin/token, capability boundary |
| END-03 | Browser presentation endpoint | Pending | END-02 | Presents and recovers; never becomes host |
| END-04 | Single-threaded browser profile | Pending | END-03 | Works without `SharedArrayBuffer`; threaded opt-in |
| DISP-01 | External display and Cast qualification | Pending | M5 | Supported matrix documented; Cast development-only until hardware passes |
| DISP-02 | Display reconnect | Pending | END-03 | Reconnect does not recreate the workspace |
| XPORT-03 | WebTransport qualification | Pending | END-03 | Native controller path; WKWebView gate; WebSocket fallback |

Exit: endpoints present without authority; browser stays loopback-only in v1.

## M7 — Distributed execution and collaboration (Releases 4–5)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| REM-01 | Remote Wanix provider | Pending | M5 | Remote lifecycle and observed status |
| REM-02 | Placement policies | Pending | M1, REM-01 | Explainable local/device/runtime placement |
| REM-03 | Remote terminal and applications | Pending | REM-01 | Capability-scoped remote execution; Xpra-style reattach preferred |
| REM-04 | Scoped namespace import | Pending | REM-01, PROTO-02 | 9P-inspired import cannot bypass leases |
| SYNC-01 | Encrypted workspace synchronization | Pending | WS-06, ID-03 | Explicit conflict model; no silent multi-writer corruption |
| SYNC-02 | Merge-class tests | Pending | SYNC-01 | `lww`, `append-log`, `manual` behave as declared |
| GROUP-01 | Membership and user identity | Pending | SYNC-01 | WebAuthn/FIDO2 separate from device identity |
| GROUP-02 | Collaboration permissions | Pending | GROUP-01 | Auditable and revocable |
| GROUP-03 | Shared documents | Pending | GROUP-02 | CRDTs confined to shared documents |

## M8 — Universal compute fabric research (research-first track)

The active execution track is `docs/planning/universal-compute-fabric-research.md`. These tasks are research spikes, not product commitments; dependencies remain `Spike` under ADR-003 until the R6 decision.

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| RF-00 | Write research plan and scenario corpus | In progress | User direction | Research questions, scenarios, kill criteria and R6 decision gate documented |
| RF-01 | Define measurement protocol and baseline matrix | In progress | RF-00 | Device, network, build, cold/warm and p50/p95/p99 recording rules defined |
| RF-02 | Pre-screen transport candidates | In progress | RF-01 | WebSocket, WebTransport, WebRTC, Iroh/QUIC and SSH/tmux compared with license and platform notes |
| RF-03 | Pre-screen state candidates and conflict corpus | Pending | RF-01 | Manifest/host, operation log, Loro and hybrid models testable against offline/handoff corpus |
| RF-04 | Build remote placement prototype | Pending | RF-01 | Remote Wanix/SSH placement shows explicit observed state and capability-scoped failure |
| RF-05 | Run checkpoint and cross-ISA feasibility | Pending | RF-01 | Cooperative checkpoint, v86, elfconv and CheerpX results include fidelity, license and size |
| RF-06 | Run remote-presentation feasibility | Pending | RF-01 | Xpra, IronRDP RAIL and macOS host results include latency, reattach and input-release behavior |
| RF-07 | Build integrated walking skeleton | Pending | RF-02..RF-06 | Two devices, one workspace, one remote placement, one handoff/reconnect and one revoked capability demonstrated |
| RF-08 | Record R6 architecture decision | Pending | RF-07 | Adopt, hybrid or stop decision updates ADRs and roadmap before product implementation resumes |

Exit: Q1–Q8 answered with evidence; scenario corpus has pass/fail results; R6 decision is recorded.

## Session log

| Date | Milestone | Change | Commit |
| --- | --- | --- | --- |
| 2026-11-03 | M0-01 | Created `milestones.md` as the execution tracker | b122d3c |
| 2026-11-03 | WS-01 | Added versioned `WorkspaceManifest` schema, validation and merge metadata | 76206c3 |
| 2026-11-03 | WS-02 | Added atomic native store, journal recovery, integrity hashes and revision fencing | 306c7d0 |
| 2026-11-03 | HOST-01 | Added single-device `WorkspaceHost` sequencer with epoch and degraded-mode fencing | 4e07274 |
| 2026-11-03 | ORCH-01 / WS-03 | Added orchestrator and observed-only instance state outside the manifest | f1da00a |
| 2026-11-03 | WS-04 | Added persisted display/window/focus layout controller without DOM state | 49f3faa |
| 2026-11-03 | WS-05 | Hardened future-schema and torn-journal recovery; added relaunch/disk-failure tests | c9150ad |
| 2026-11-03 | WS-06 | Covered all syncable fields with explicit merge classes; unknown paths remain manual | df6d43f |
| 2026-11-03 | UX-01 | Bootstrapped app state from the manifest and added truthful restore reports | ff63293 |
| 2026-11-03 | M0-02 | Refreshed the fabric plan for `WorkspaceHost`, split WASI targets, movement-only input and loopback-only browser hosting | 676617c |
| 2026-11-03 | M0-04 / M0-05 | Recorded negotiated v1+v12 compatibility and froze Release 1 scope | c484d18 |
| 2026-11-03 | M0-03 | Added protocol conformance/drift workflow, baseline schema and movement fixture; cross-language round-trip remains open | c484d18 |
| 2026-11-03 | RT-02 / APP-03 / APP-04 / UX-02 | Added provider registry, world pinning, quota enforcement and restore/degraded status copy with core tests | c484d18 |
| 2026-11-03 | IN-01..06 | Added packed movement frames, protocol negotiation, connection context, latency probe and lease arbitration with core tests | c484d18 |
| 2026-11-04 | IN-01 / IN-04 / IN-06 | Wired lease ownership into `SessionCoordinator`, reset epochs per generation, added stale-epoch tests and outgoing validation | 15cff36 |
| 2026-11-04 | M0-03 / IN-07 | Added Rust/TS movement fixture round-trips, Swift fuzz/bit-flip coverage and Rust/web CI jobs | 15cff36 |
| 2026-11-04 | INPUT-01 | Covered distinct primary/pinned cursors and single-keyboard-focus arbitration | 44f1945 |
| 2026-11-04 | RT-03 | Routed sessions through async desktop runtime providers, removed direct `RuntimeFactory` use and added provider/lifecycle tests | f184bdf |
| 2026-11-04 | RT-05 | Added split WASI 0.2 worlds, qualified the native provider and rejected unknown worlds/pinned worlds with typed errors | 5d76caf |
| 2026-11-04 | RT-06 | Added fail-closed threading detection, single-threaded shell startup without `SharedArrayBuffer` and typed `SynchronizationUnavailable` enforcement at provider create | d2cdc23 |
| 2026-11-04 | APP-05 | Required explicit app-cooperative checkpoint capability before providers or the controller can report `SUSPENDED_CHECKPOINTED`; added rejection coverage | 9e11655 |
| 2026-11-04 | APP-02 | Added workspace lifecycle store and Settings actions for start, suspend, checkpoint, resume and stop with observed/desired state reporting | 6c13336 |
| 2026-11-04 | IN-02 / IN-07 | Added channel-aware input dispatch/transport validation, envelope-first classification and FlatBuffers `0xA5` collision corpora across Swift, Rust and web | a50476f |
| 2026-11-04 | IN-02 / IN-07 | Corrected channel fixtures and Rust magic import; verified core 121, app 243, web 56, Rust 10 and `protocol/check.sh` | 8950960 |
| 2026-11-04 | M8 / RF-00 | Added research plan, dependency pre-screen, threat model, harness and first transport smoke runner | 8b8f02c |
| 2026-11-04 | M8 / RF-00 / RF-01 | Added loopback transport baseline scenario and recorded the qualified Mac runner | c639550 |
| 2026-11-04 | M8 / RF-01 | Recorded clean loopback WebSocket baseline at 64 B, 1 KiB and 16 KiB; fixed untracked-artifact provenance | 86e4839 |
| 2026-11-04 | M8 / RF-02 | Added WebTransport scenario and runner support with ephemeral certificate generation | cb959d8 |
| 2026-11-04 | M8 / RF-02 | Fixed length-framed stream echo and recorded T2 WebTransport loopback baseline; flagged the iOS 18.6 WKWebView support gap | 1ea8d85 |
| 2026-11-04 | M8 / RF-02 | Pre-screened WebRTC, Iroh/QUIC and SSH/tmux; corrected the WKWebView RTCDataChannel baseline | 0165d5e |
| 2026-11-04 | M8 / RF-02 | Added the T3 WebRTC data-channel harness and recorded a clean macOS WKWebView loopback baseline | 3759513 |
| 2026-11-04 | M8 / RF-02 | Added an opt-in iOS WKWebView WebRTC probe and recorded iOS 18.6 simulator loopback results at 64 B, 1 KiB and 16 KiB | 8c179e9 |
| 2026-11-05 | M8 / RF-02 | Added the relay-free Iroh/QUIC loopback probe and recorded two clean T4 baselines | 46e9341, 1200ad0 |
| 2026-11-05 | M8 / RF-02 | Added the two-host Iroh tailnet runner and recorded the Tailscale DERP underlay path | b1bca77, 2beb77a |
| 2026-11-05 | M8 / RF-02 | Recorded the two-host Iroh tailnet baseline, DERP caveat and report | e260fcd |
| 2026-11-05 | M8 / RF-02 | Completed the SSH/tmux pre-screen; kept it as the remote-execution reference with S2 reattach unmeasured | 38bb76d |
| 2026-11-05 | M8 / RF-02 | Added and stabilized the S2 SSH/tmux reattach runner; recorded 3/3 simulator reattaches with process survival and truthful transcripts on a DERP-relayed tailnet | 2ab39cd, 72e0429, 0bacc6c |
| 2026-11-05 | M8 / RF-02 | Added the forced Iroh relay-only probe and runner; recorded 90/90 relay-path deliveries through the public n0 relay, with automatic-fallback and self-hosting caveats | b0cf1c8, e4f9eee |
| 2026-11-05 | M8 / RF-02 | Added an S2 app-termination mode and auto-preview UI setup; recorded 3/3 cold recoveries at p50 57.6 s and reran background reattach at p50 6.9 s, with process survival and truthful transcripts on a DERP-relayed tailnet | 0ba83da, 5e17b45, 6947445, 472537a |
| 2026-11-06 | M8 / RF-02 | Added the S2 second-device handoff harness and sequential simulator runner; recorded 1/1 handoff with 40.4 s cold recovery, process survival and a truthful transcript on a DERP-relayed tailnet | 796387f, 5c962e5, 3fcac85 |
| 2026-11-06 | M5 / XPORT-04 | Adopted the official Iroh Swift SDK under ADR-021; added direct-only/self-hosted relay policy, reliable channel framing, movement datagrams, endpoint tickets, diagnostics and loopback tests; build and 3/3 adapter tests pass on the iOS 18.6 simulator | 91b3f86 |
