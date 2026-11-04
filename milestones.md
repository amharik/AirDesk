# AirDesk implementation milestones

Status: active
Last updated: 2026-11-04

This file is the implementation tracker. `docs/adr/README.md` remains authoritative for decision status. This file tracks execution order, acceptance criteria and current progress. Update it whenever a work item changes state.

## Status legend

| Status | Meaning |
| --- | --- |
| `Done` | Code, tests and the relevant doc/status update are merged |
| `In progress` | Actively being implemented in the current change |
| `Pending` | Not started, dependencies satisfied or tracked |
| `Blocked` | Waiting on a decision, dependency or hardware |

## Current focus

- Milestone: `M2` and `M3`
- Work item: `M0-03`, `RT-02`, `RT-03`, `RT-05`, `IN-01`, `IN-04`, `IN-06` and `INPUT-01` are complete; `RT-04` is blocked on a native execution engine/package decision; finish `RT-06`, app lifecycle in `APP-02`/`APP-05`, and the remaining transport/conformance work in `IN-02`/`IN-07`
- Next: qualify the single-threaded profile, connect lifecycle actions to session/workspace UI, and close the remaining channel-split/fuzz-corpus gates

## Verification status

Real iPad testing is parked by request. On 2026-11-04, `scripts/check-core.sh` runs 116 workspace-core and input tests successfully on macOS via SwiftPM; the full `AirDeskTests` target runs 233 tests with 0 failures on an iPhone 16 Pro simulator (iOS 18.6); `xcodebuild build-for-testing` for the generic iOS Simulator destination succeeds with `CODE_SIGNING_ALLOWED=NO`; `protocol/check.sh` passes; and the Rust protocol crate passes 9 tests. The web movement fixture was verified with Deno, while the full web Vitest suite remains CI-covered because Node is unavailable locally. Device signing still fails with `Certificate installation failed ... Code=-61 "Write permissions error."` even after the login keychain exposes valid Apple Development identities, because Xcode cannot use the private-key ACL over SSH. Device verification will resume from a GUI Xcode session with a one-time "Always Allow" keychain prompt.

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
| RT-06 | Single-threaded profile | Pending | RT-03 | Starts without `SharedArrayBuffer`; sync WASI fails with `SynchronizationUnavailable` |
| APP-02 | Application manifest and lifecycle | In progress | RT-02, WS-01 | Install, start, suspend, stop and observed status work |
| APP-03 | World/version pinning | Done | APP-02, RT-05 | Manifest pins the qualified `(provider, world)` pair |
| APP-04 | Quota enforcement matrix | Done | APP-02 | Unenforceable required quota fails placement with `QuotaUnenforceable` |
| APP-05 | Cooperative checkpoint lifecycle | In progress | APP-02 | `SUSPENDED_CHECKPOINTED` only after app checkpoint; no process snapshot |
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
| IN-07 | Conformance and fuzz gates | In progress | IN-01, IN-02 | Swift/TS/Rust round-trip and fuzz gates added; FlatBuffers `0xA5` collision corpus remains |

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
| XPORT-01 | Direct transport benchmark | Pending | AGENT-02 | WebRTC/QUIC vs WebSocket p50/p95, CPU, reconnect |
| XPORT-02 | Direct transport qualification | Pending | XPORT-01 | ADR-013 updated with evidence; relay remains absent |

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
| 2026-11-04 | RT-05 | Added split WASI 0.2 worlds, qualified the native provider and rejected unknown worlds/pinned worlds with typed errors | pending |
