# AirDesk implementation milestones

Status: active
Last updated: 2026-11-03

This file is the implementation tracker. `docs/adr/README.md` remains authoritative for decision status. This file tracks execution order, acceptance criteria and current progress. Update it whenever a work item changes state.

## Status legend

| Status | Meaning |
| --- | --- |
| `Done` | Code, tests and the relevant doc/status update are merged |
| `In progress` | Actively being implemented in the current change |
| `Pending` | Not started, dependencies satisfied or tracked |
| `Blocked` | Waiting on a decision, dependency or hardware |

## Current focus

- Milestone: `M1`
- Work item: `WS-04` layout persistence
- Next: `WS-05` recovery test suite, `WS-06` merge metadata enforcement

## Verification blocker

Real iPad tests are currently blocked over SSH: the Mac login keychain is locked (`User interaction is not allowed`), so Xcode free provisioning cannot install the iOS Development certificate for team `4PL99B52DB`. The iOS simulator build compiles the app and test target, and the workspace core's 44 unit tests pass on macOS via SwiftPM (`swift test`). To run tests on `Hari's iPad`, unlock the login keychain in a GUI session or run the test from Xcode.

## M0 — Plan reset and guardrails

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| M0-01 | Write `milestones.md` and make it the execution tracker | Done | — | Plan is committed and linked from this file |
| M0-02 | Update `docs/planning/workspace-fabric-plan.md` for ADR-020 and round-3 decisions | Pending | M0-01 | Plan references `WorkspaceHost`, split WASI targets, movement-only input and browser loopback-only |
| M0-03 | Add protocol guardrails: `flatc --conform`, generated drift, cross-language fixtures | Pending | — | CI fails on schema drift; Swift/TS/Rust fixtures round-trip |
| M0-04 | Decide protocol compatibility: negotiated v1 legacy + v12, or hard cutover | Pending | — | Decision recorded in ADR-008/010 and milestones |
| M0-05 | Freeze Release 1 scope | Pending | — | Single-device workspace only; fabric deferred to Release 2 |

## M1 — Workspace core (Release 1)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| WS-01 | `WorkspaceManifest` v1 schema | Done | M0-05 | Identity, revision, `workspaceSeq`, `hostEpoch`, desired state, resources, layout and merge metadata encode/decode |
| WS-02 | Native `WorkspaceStore` | Done | WS-01 | Atomic revision commit, `expectedRevision`, journal append/replay, `fsync`/`F_FULLFSYNC`, typed errors |
| WS-03 | Desired/observed separation | Done | WS-02 | Observed runtime/application state never mutates the manifest |
| WS-04 | Layout persistence | Pending | WS-01 | Window identity, bounds, display and focus order restore without DOM state |
| WS-05 | Recovery test suite | Pending | WS-02, WS-03, WS-04 | Relaunch, corruption, future schema, disk-full and interrupted-write tests |
| WS-06 | Merge metadata enforcement | Pending | WS-01 | Every syncable field is `lww`, `append-log` or `manual`; unknown defaults to `manual` |
| HOST-01 | Single-device `WorkspaceHost` | Done | WS-02 | Only host commits; `workspaceSeq` contiguous; `hostEpoch` present; host-degraded typed error |
| ORCH-01 | Minimal `WorkspaceOrchestrator` | Done | HOST-01 | Open, attach, place, reconcile above `SessionCoordinator`; no workspace mutation from sessions |
| UX-01 | Truthful restore report | Pending | WS-03 | UI states restored, restarted, reconnected or lost |

Exit: the app boots from a manifest instead of `Workspace.default`, survives relaunch, and reports recovery truthfully.

## M2 — Runtime and application model (Release 1)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| RT-02 | Runtime provider registry | Pending | M1 | Providers advertise worlds/capabilities; selection and unavailable states are typed |
| RT-03 | Wanix provider adapter extraction | Pending | RT-02 | Wanix lifecycle is provider-managed; workspace does not read Wanix internals |
| RT-04 | Native provider path | Pending | RT-02 | Native execution works without Wanix |
| RT-05 | Per-provider WASI worlds | Pending | RT-02 | Wanix runs `wasip1`; native runs `wasi-cli@0.2`; unsupported pairs fail closed |
| RT-06 | Single-threaded profile | Pending | RT-03 | Starts without `SharedArrayBuffer`; sync WASI fails with `SynchronizationUnavailable` |
| APP-02 | Application manifest and lifecycle | Pending | RT-02, WS-01 | Install, start, suspend, stop and observed status work |
| APP-03 | World/version pinning | Pending | APP-02, RT-05 | Manifest pins the qualified `(provider, world)` pair |
| APP-04 | Quota enforcement matrix | Pending | APP-02 | Unenforceable required quota fails placement with `QuotaUnenforceable` |
| APP-05 | Cooperative checkpoint lifecycle | Pending | APP-02 | `SUSPENDED_CHECKPOINTED` only after app checkpoint; no process snapshot |
| UX-02 | Restore and degraded-mode UI copy | Pending | UX-01, HOST-01 | Host-degraded and recovery outcomes are visible and truthful |

Exit: provider-neutral placement, explicit world support, no production just-bash path.

## M3 — Input protocol v2 (parallel with M1/M2)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| IN-01 | 16-byte movement frame (`0xA5`) | Pending | M0-04 | Movement only; no edges; negotiated version; fuzz-tested |
| IN-02 | Channel 1/1R split | Pending | IN-01 | Edges on reliable ordered channel; movement on datagram/ordered WebSocket with `seq` discard |
| IN-03 | Connection-derived context | Pending | IN-02 | Session/generation/controller never trusted from the packed frame |
| IN-04 | Lease epoch at display sink | Pending | IN-02 | `SessionCoordinator` owns `leaseEpoch`; stale edge returns `EpochRejected`; resets with generation |
| IN-05 | Shared cursor and pinned roles | Pending | IN-04 | Pinned driver cannot move shared cursor or emit keyboard/text/focus |
| IN-06 | Latency probe | Pending | IN-02 | Channel 0 probe measures latency; no fake per-frame timestamps |
| IN-07 | Conformance and fuzz gates | Pending | IN-01, IN-02 | Swift/TS/Rust round-trip; `0xA5` collision test; malformed/stale rejection |

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
| INPUT-01 | Multi-controller arbitration | Pending | IN-05 | Distinct cursors; single keyboard focus; guarded `force_preempt`; no stuck input |
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
