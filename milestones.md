# AirDesk implementation milestones

Status: active
Last updated: 2026-11-07

This file is the implementation tracker. `docs/adr/README.md` remains authoritative for decision status. This file tracks execution order, acceptance criteria and current progress. Update it whenever a work item changes state.

## Status legend

| Status | Meaning |
| --- | --- |
| `Done` | Code, tests and the relevant doc/status update are merged |
| `In progress` | Actively being implemented in the current change |
| `Pending` | Not started, dependencies satisfied or tracked |
| `Blocked` | Waiting on a decision, dependency or hardware |

## Current focus

- Milestone: `M4–M7` foundational implementation resumed under user direction on 2026-11-06, with `M8` research still active as the architecture gate
- Track: `100x research first` remains authoritative; product release sequencing is still paused until the R6 decision gate, but the user explicitly directed implementation of Android, identity, protocol, browser-endpoint, sync/collaboration and remote-placement foundations
- Work item: the Android controller/display baseline builds and passes its unit/lint gates; ADFP now has a typed control header, additive fabric payload union, and the typed resource RPC surface (`ResourceOpCode` 100–115, attach/stat/walk/read/write/mknod/remove/rename/chmod/truncate/wstat) with generated Swift, TypeScript, Rust and Kotlin bindings; iOS and browser use Ed25519 with P-256 fallback while Android uses P-256, and all three have local registries, revocation propagation and pairing-offer validation; the browser has the AD-PAIR-1 canonical transcript, signature/binding checks, SAS and HKDF key schedule, plus an interactive RFC 9383 P-256 SPAKE2+ session validated against the RFC vector; iOS has a local device-capability catalog; the loopback browser endpoint host service, bundled display page with a single-threaded profile, generation-safe reconnect takeover and one-second view-only JPEG surface streaming, workspace host handoff/degraded mode, sync/merge/envelope and conflict corpus, matching browser/iOS AES-GCM sync envelopes with an Iroh `.sync` reliable channel, collaboration roles/audit and remote-placement selection have tested foundations. The browser also has COSE_Sign1 capability grant issuance/verification, bounded delegation attenuation, scoped leases, `cnf` proof-of-possession, signed monotonic revocation snapshots, provider-side request authorization, and grant/lease invalidation from distributed revocation snapshots. QR/PIN camera/UI and native parity, production revocation transport and native invocation enforcement, real network transports and remote execution remain unimplemented
- Next: repeat T3/S2 and install the Android APK when physical signing/hardware is available; add the QR/PIN camera/UI flow, native parity and native/browser channel-binding acquisition before claiming pairing; wire sync session/offline flushing and workspace-store integration; wire native root-issuer policy, revocation distribution and remote execution; do not promote research spikes or proposed ADRs
- Retained implementation state: `M0-03`, `RT-02`, `RT-03`, `RT-05`, `RT-06`, `APP-02`, `APP-05`, `IN-01`, `IN-04`, `IN-06`, `IN-07`, `INPUT-01`, `CAP-01`, `ID-03`, `PROTO-02`, `END-01`, `END-02`, `END-03`, `END-04`, `DISP-02` and `IN-02` are complete; `RT-04` is blocked on a native execution engine/package decision

## Verification status

Real iPad testing is parked by request. On 2026-11-07, after adding capability-revocation propagation, workspace host handoff/degraded mode and interactive SPAKE2+ pairing, `scripts/check-core.sh` passes 128 workspace-core and input tests; the full `AirDeskTests` target passes 356 tests with 1 skip and 0 failures on an iPhone 16 Pro simulator (iOS 18.6), including native capability registry validation, revocation-reference propagation, canonical discovery records, runtime Bonjour browser/publisher coverage, generation-safe display reconnect, browser surface broadcasting, Iroh sync-channel routing, browser-compatible AES-GCM sync envelopes, loopback asset isolation headers and bundled display-link generation; the web suite passes 206 tests across 27 files, including the ADFP resource RPC surface and `Qid` tuples, the RFC 9383 SPAKE2+ P-256 vector, interactive session, scrypt password registration, QR/PIN envelopes with attempt limiting, COSE_Sign1 grants with attenuated delegation/leases, `cnf` proof-of-possession, signed revocation snapshots with grant and lease invalidation, a validated capability registry with deterministic provider resolution, revocation propagation and provider-side request authorization, the real loopback WebSocket transport, production display page/reconnect UX, single-threaded page startup and surface-frame rendering/validation, plus TypeScript, ESLint, the Committed DesktopShell bundle check and dependency policy; and `protocol/check.sh` passes. The Rust protocol crate passes 10 tests on `sillyoci`. The Android app passes 54 unit tests with `lintDebug` reporting 0 errors and 6 dependency-update warnings. The Android debug APK is built at `android/build-artifacts/AirDesk-debug.apk` (SHA-256 `fef8be8b188b0013386ad4d1ef8401f2252c32dcc2e581a25453408d260f7aba`) but has not been installed on a physical device. Device signing still fails with `Certificate installation failed ... Code=-61 "Write permissions error."` even after the login keychain exposes valid Apple Development identities, because Xcode cannot use the private-key ACL over SSH. Device verification will resume from a GUI Xcode session with a one-time "Always Allow" keychain prompt.

## Release 1 scope freeze

Release 1 is a single-device workspace with one authoritative host, persisted desired state, truthful recovery, local runtime providers, and the input protocol compatibility path. It includes no fabric membership, no multi-device synchronization, no capability grants between devices, no browser endpoint and no distributed placement. Those remain Release 2–5 work and must not be pulled into Release 1 acceptance. The Android and fabric foundations added on 2026-11-06 are not Release 1 features and remain behind their proposed ADR gates.

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
| IN-02 | Channel 1/1R split | Done | IN-01 | Edges use the reliable ordered Iroh channel; movement uses Iroh datagrams with per-controller `seq` discard; local/Cast endpoint routing preserves the same channel validation |
| IN-03 | Connection-derived context | Done | IN-02 | Session/generation/controller never trusted from the packed frame |
| IN-04 | Lease epoch at display sink | Done | IN-02 | `SessionCoordinator` owns `leaseEpoch`; stale edge returns `EpochRejected`; resets with generation |
| IN-05 | Shared cursor and pinned roles | Done | IN-04 | Pinned driver cannot move shared cursor or emit keyboard/text/focus |
| IN-06 | Latency probe | Done | IN-02 | Channel 0 probe measures latency; no fake per-frame timestamps |
| IN-07 | Conformance and fuzz gates | Done | IN-01, IN-02 | Swift/TS/Rust round-trip/fuzz gates and valid-envelope FlatBuffers `0xA5` collision corpus pass |

Exit: old and new paths negotiate cleanly; no input edge is ever sent on Channel 1.

## M4 — Identity and capabilities (Release 2)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| ID-01 | Device identity and QR/PIN pairing | In progress | M3, M1 | iOS and browser implement Ed25519 default with P-256 fallback; Android uses P-256; all three validate nonce/expiry/replay in local pairing offers; browser has a canonical AD-PAIR-1 transcript, signature checks, SAS and HKDF key schedule, plus an interactive RFC 9383 P-256 SPAKE2+ session, scrypt password PBKDF and QR/PIN challenge envelopes with attempt limiting validated against the RFC vector; camera/UI flow, native parity and user-verification integration remain pending |
| ID-02 | Native/browser channel binding | In progress | ID-01 | Binding kinds, offer validation and same-binding transcript enforcement exist; native TLS exporter and browser host-cert acquisition remain pending |
| ID-03 | Device registry and revocation | Done | ID-01 | Local device registry/revocation implemented on iOS, Android and browser; revocation invalidates local session credentials and browser session leases; signed revocation snapshots invalidate capability grants and leases in provider authorization; production snapshot transport remains under CAP-02/PROTO-01 |
| ID-04 | Canonical discovery | Done | ID-01 | `_airdesk._tcp`/`_airdesk._udp`, canonical TXT keys, no `dev_id`/`role_mask`; canonical record codec implemented, runtime Bonjour adapter remains DISC-01 |
| DISC-01 | Runtime discovery adapter | Done | ID-04 | `NWBrowser`/`NWListener` adapter for `_airdesk._tcp`/`_airdesk._udp`; filters malformed/forbidden advertisements, publishes canonical TXT only, clears stale results on failure/stop; simulator/unit coverage complete, device-to-device discovery remains integration verification |
| CAP-01 | Capability registry | Done | ID-03 | `cap_uri`, four-value availability and explicit authorization exist in ADFP and all three clients; browser, iOS and Android registries validate descriptors, preserve availability/authorization independence and apply revoked grant references; the browser resolver is deterministic with diagnostics; production snapshot transport remains integration work under CAP-02/PROTO-01 |
| CAP-02 | Grants and leases | Done | CAP-01 | `COSE_Sign1`, `jti`, `cnf`, `epoch_id = generation`; provider/owner root grant; coordinator cannot mint; browser issuance/verification, ≤3-hop attenuation, bounded leases, `cnf` proof-of-possession, signed monotonic revocation snapshots, grant/lease invalidation and provider-side request authorization implemented; native invocation enforcement and production revocation distribution remain integration work |
| HOST-02 | Host handoff | Done | ID-03, HOST-01 | Quiesce/stage/activate/retire; force takeover; stale `host_epoch` demotes |
| HOST-03 | Host-degraded mode | Done | HOST-02 | Structural writes fail typed; running runtimes and leased input continue |

Exit: pairing grants no ownership; grants are provider-issued; handoff and force takeover are tested.

## M5 — Fabric and agents (Release 2)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| PROTO-01 | ADFP baseline | In progress | M3 | Typed `ControlHeader`, additive `FabricPayload`, baseline conformance and Swift/TS/Rust/Kotlin bindings exist; module coverage and production transport remain pending |
| PROTO-02 | Resource RPC surface | Done | PROTO-01 | ADFP-local op codes 100–115 for `Attach` through `Wstat`, not 9P2000 tags; typed `Qid` struct, bind modes, statuses, bounded stats and generated Swift/TS/Rust/Kotlin bindings; no 9P2000 tunneling |
| AGENT-01 | Native agent contract | In progress | ID-01 | Android and iOS identity, capabilities, permissions and local health baselines exist; formal cross-platform contract remains pending |
| AGENT-02 | iOS device agent | In progress | AGENT-01 | Local capability catalog covers display, pointer, keyboard, camera permission state, app-scoped/user-selected documents and diagnostics; capture streaming, file transfer and remote invocation remain pending |
| AND-01 | Android device agent and controller baseline | In progress | AGENT-01 | Kotlin/Compose controller, identity, capability advertisement, WebView presentation and canonical ADFP integration build; physical-device and production-transport qualification remain pending |
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
| END-01 | Browser endpoint feasibility spike | Done | M5 | Loopback URL/token/origin policy and fail-closed state are tested; production COOP/COEP, asset-isolation headers and WKWebView cross-origin isolation/OPFS/Worker proof pass |
| END-02 | Local host agent | Done | END-01 | Loopback WebSocket client, token/origin validation and reconnect state exist; the Swift loopback host service implements handshake, registration, viewport/focus, heartbeat and rejection tests; app lifecycle, settings and diagnostics wiring are implemented |
| END-03 | Browser presentation endpoint | Done | END-02 | Presentation registration/reconnect state, policy, host service, app wiring, bundled browser page, real loopback WebSocket transport, explicit reconnect UX and one-second view-only JPEG surface streaming are implemented; non-loopback transport remains pending |
| END-04 | Single-threaded browser profile | Done | END-03 | Browser page starts without `SharedArrayBuffer`/`Atomics`; explicit shared-memory opt-in fails closed unless cross-origin isolated |
| DISP-01 | External display and Cast qualification | Blocked | M5 | Supported matrix documented; Cast remains development-only until physical Chromecast/Google TV hardware qualification is available |
| DISP-02 | Display reconnect | Done | END-03 | A newer-generation registration replaces the active display connection while preserving workspace/display identity and creating no workspace state |
| XPORT-03 | WebTransport qualification | Blocked | END-03 | Requires a target runtime exposing `WebTransport` plus `serverCertificateHashes`; iOS 18.6 WKWebView fails the gate, so the shell keeps loopback WebSocket and reports `webtransport_unqualified` |

Exit: endpoints present without authority; browser stays loopback-only in v1.

## M7 — Distributed execution and collaboration (Releases 4–5)

| ID | Task | Status | Depends | Acceptance |
| --- | --- | --- | --- | --- |
| REM-01 | Remote Wanix provider | Pending | M5 | Remote lifecycle and observed status |
| REM-02 | Placement policies | In progress | M1, REM-01 | Deterministic local/device/runtime placement selection and typed failures are tested; remote execution integration remains pending |
| REM-03 | Remote terminal and applications | Pending | REM-01 | Capability-scoped remote execution; Xpra-style reattach preferred |
| REM-04 | Scoped namespace import | Pending | REM-01, PROTO-02 | 9P-inspired import cannot bypass leases |
| SYNC-01 | Encrypted workspace synchronization | In progress | WS-06, ID-03 | Merge model, offline queue and AES-GCM envelope/replay foundations are tested in the browser; iOS now has a matching AES-GCM/HKDF envelope implementation and native sync reuses the existing Iroh reliable connection through a `.sync` channel; session/offline flushing and workspace-store integration remain pending |
| SYNC-02 | Merge-class tests | Done | SYNC-01 | Deterministic conflict corpus covers `lww`, `append-log`, `manual`, offline replay/rebase, stale/future epoch-seq, invalid patches and hooks; cross-device transport remains under SYNC-01 |
| GROUP-01 | Membership and user identity | Pending | SYNC-01 | WebAuthn/FIDO2 separate from device identity |
| GROUP-02 | Collaboration permissions | In progress | GROUP-01 | Device-level roles, permissions, audit and revocation are tested; user identity and shared-document scopes remain pending |
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
| 2026-11-06 | M5 / XPORT-05 | Integrated Iroh into `AppEnvironment`, settings and sessions; added ticket pairing, path diagnostics, input codec, live peer loopback, explicit remote-lease grant and WebSocket fallback; full suite passes 256 tests with 1 skip and 0 failures on the iOS 18.6 simulator | f7c2b3d |
| 2026-11-06 | M4 / M5 / M6 | Added typed ADFP control header and additive fabric payload union, regenerated Swift/TS/Rust/Kotlin bindings and preserved baseline conformance; added Android identity, pairing validation, capability advertisement, WebView presentation and canonical ADFP integration; Android passes 49 tests with 0 lint errors | 6603531 |
| 2026-11-06 | M4 / M7 | Added browser identity, pairing-offer validation, replay guard, registry/revocation, loopback endpoint policy, merge/sync envelope, collaboration roles/audit and remote-placement foundations; web passes 125 tests plus TypeScript, ESLint and bundle checks | 6603531 |
| 2026-11-06 | M4 / M6 | Added native iOS Ed25519/P-256 device identity, Keychain persistence, local registry/revocation, pairing-offer validation and diagnostics/settings surfaces; combined suite passes 287 tests with 1 skip, core passes 121, Rust passes 10 and `protocol/check.sh` passes | 6603531 |
| 2026-11-06 | M4 / ID-01 | Added the AD-PAIR-1 canonical transcript, Ed25519/P-256 transcript signatures, required channel binding, SAS, HKDF session keys and deterministic fixture; branch passes 135 web tests, and merged web passes 140 | 6663b85 |
| 2026-11-06 | M6 / END-02 | Added the loopback Swift browser endpoint host service with token/origin handshake, registration, viewport/focus, heartbeat, typed rejection and reconnect tests; merged into `dev` | fba631c, 99c58cb, 1907e9c |
| 2026-11-06 | M7 / SYNC-02 | Added a deterministic 25-fixture sync conflict corpus and runner covering merge classes, offline replay, epochs/sequences, invalid patches and hooks; merged into `dev` | 87d827f, d4c8b37 |
| 2026-11-06 | M5 / AGENT-02 | Added the iOS device capability catalog for display, pointer, keyboard, camera, app-scoped documents and local diagnostics; targeted 13 tests and full 300-test branch suite pass; merged into `dev` | da8b2ea, a6de570, 7ef1c1a |
| 2026-11-06 | M4–M7 | Combined post-merge verification passes 324 iOS tests with 1 skip, 140 web tests across 19 files, 121 core tests and `protocol/check.sh` | 7ef1c1a |
| 2026-11-06 | M4 / ID-01 | Added an RFC 9383 SPAKE2+ P-256 primitive with exact transcript, HKDF/HMAC key schedule, subgroup/scalar/confirmation checks and the RFC P-256 vector; full web check passes 150 tests across 20 files; merged into `dev` | afbb970, 62825b0, 56503e0 |
| 2026-11-06 | M6 / END-02 | Wired the loopback browser endpoint host into `AppEnvironment` with persisted enablement, local asset-origin startup, lifecycle stop, a scoped endpoint URL, settings controls and diagnostics; iOS passes 328 tests with 1 skip and 0 failures | 1e49398 |
| 2026-11-06 | M4 / ID-01 | Added the interactive SPAKE2+ prover/verifier session and optional `AdPairSession` exchange evidence; web check passes 154 tests | 8eb381c |
| 2026-11-06 | M4 / HOST-02, HOST-03 | Added workspace host quiesce/stage/activate/retire handoff, force takeover, stale-epoch demotion, handoff status copy and degraded-mode runtime/input coverage; full iOS suite passes 335 tests with 1 skip | c958384 |
| 2026-11-06 | M4 / ID-01 | Added the RFC 9383 password-to-scalar scrypt PBKDF, salted registration records and password-derived interactive SPAKE2+ coverage; web check passes 159 tests across 20 files | 514fd87 |
| 2026-11-06 | M4 / ID-01 | Added the `ADPAIR1:` QR envelope, six-digit PIN and QR-secret challenges, PIN-derived registration and in-memory PIN attempt limiting; web check passes 167 tests across 21 files | 58c9436 |
| 2026-11-06 | M4 / ID-04 | Added canonical `_airdesk._tcp`/`_airdesk._udp` DNS-SD advertisement records with strict TXT parsing, certificate-hash validation and rejection of `dev_id`, `role_mask`, capabilities and tokens; full iOS suite passes 340 tests with 1 skip | 81d6e54 |
| 2026-11-06 | M4 / CAP-02 | Added strict CBOR and tagged `COSE_Sign1` capability grants with Ed25519/P-256 verification, claim/epoch checks, ≤3-hop parent-hash attenuation and scoped leases; web check passes 179 tests across 22 files | 366930f |
| 2026-11-06 | M4 / CAP-02 | Added `cnf` proof-of-possession and signed, sequence-numbered revocation snapshots with trusted-issuer, monotonic-sequence and bounded-staleness enforcement; web check passes 185 tests across 23 files | 480a32c |
| 2026-11-06 | M4 / CAP-02 | Added provider-side request authorization tying approved root issuers, chain/epoch checks, revocation freshness, workspace/application/requester lease scope, operation scope and `cnf` proof together; web check passes 189 tests across 24 files | d7c6d14 |
| 2026-11-06 | M4 / DISC-01 | Added runtime Bonjour/DNS-SD browser and publisher adapters with filtered advertisements, canonical TXT publishing, stale-result clearing and simulator tests; full iOS suite passes 343 tests with 1 skip | db2ffb2 |
| 2026-11-06 | M4 / CAP-01 | Added a validated browser capability registry with descriptor limits, immutable registrations, availability/authorization updates and deterministic provider resolution diagnostics; web check passes 194 tests across 25 files | 85555e4 |
| 2026-11-06 | M4 / CAP-01 | Added a native capability registry with descriptor limits, strict flat-JSON constraints, replacement/removal, availability/authorization updates and deterministic ordering; full iOS suite passes 347 tests with 1 skip | fd84b12 |
| 2026-11-06 | M4 / CAP-01 | Added Android capability-registry parity and mapped version, execution, transport and structured constraints into ADFP; Android passes 53 tests and `lintDebug` with 0 errors | c416efb |
| 2026-11-07 | M4 / CAP-01 | Added authorization references and revoked-grant propagation to the browser, iOS and Android registries, plus a code-owned descriptor lookup for browser diagnostics; full iOS suite passes 348 tests with 1 skip, web check passes 195 tests across 25 files, and Android passes 54 tests with `lintDebug` reporting 0 errors | 1f4c9b8 |
| 2026-11-07 | M4 / ID-03 | Added signed snapshot lease invalidation to provider authorization, so a revoked lease is rejected even when its grant, scope and freshness are otherwise valid; web check passes 196 tests across 25 files | 16cb919 |
| 2026-11-07 | M5 / PROTO-02 | Added ADFP-local resource RPC op codes 100–115, typed `Qid`, bind modes, statuses, bounded stat metadata and generated Swift/TS/Rust/Kotlin bindings without 9P2000 tunneling; protocol conformance passes, web check passes 197 tests, full iOS suite passes 348 tests with 1 skip, Rust passes 10 tests and Android passes 54 tests with `lintDebug` reporting 0 errors | fdccd41 |
| 2026-11-07 | M5 / END-01 | Added a loopback asset-server test that fetches an actual HTTP response and asserts production COOP/COEP/CORP, no-store and nosniff headers alongside the existing WKWebView cross-origin isolation, OPFS and Worker proof; END-01 and END-02 are complete; full iOS suite passes 349 tests with 1 skip | 44713a6 |
| 2026-11-07 | M6 / END-03 | Added the production browser display page with a scoped loopback presentation link, real WebSocket transport, status/error UI, viewport/focus reporting, auto/manual reconnect and same-session restoration; wired the bundled page link through settings and diagnostics; web check passes 204 tests across 27 files and the full iOS suite passes 350 tests with 1 skip | f2b0607 |
| 2026-11-07 | M6 / END-04, DISP-02 | Added generation-safe display reconnect takeover so a newer registration closes the stale connection without changing workspace/display identity or creating workspace state; proved single-threaded page startup without `SharedArrayBuffer`/`Atomics`; web check passes 205 tests across 27 files and the full iOS suite passes 351 tests with 1 skip | 8474659 |
| 2026-11-07 | M6 / END-03 | Added one-second view-only JPEG surface streaming from the desktop WKWebView through the loopback endpoint host to the bundled display page, with surface-frame validation, revision filtering and disconnect clearing; web check passes 206 tests across 27 files and the full iOS suite passes 352 tests with 1 skip | b6fd078 |
| 2026-11-07 | M7 / SYNC-01 | Reused the existing Iroh reliable connection through a dedicated `.sync` channel and ported the browser AES-GCM/HKDF workspace envelope to iOS, verified against a shared ciphertext vector; full iOS suite passes 356 tests with 1 skip | 1becbe8 |
