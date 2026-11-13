# Architecture decision index

This index is the authoritative map of which decision is in force. An ADR's original text is historical; amendments and supersessions are recorded here and in the ADR header.

> **Execution note (2026-11-04):** Decision status is unchanged. The active implementation track is the universal compute fabric research program in `docs/planning/universal-compute-fabric-research.md`; product release sequencing is paused until its R6 decision. Research spikes may implement proposed ADRs behind flags but do not promote them.
>
> **Execution note (2026-11-06):** User direction adopts Iroh for the native peer data plane under ADR-021. The browser endpoint remains WebSocket. Product release sequencing is still paused until R6; the Iroh adapter may be implemented and tested in parallel.
>
> **Execution note (2026-11-06):** User direction also authorized foundational implementation of Android, identity, ADFP, browser-endpoint, sync/collaboration and remote-placement work. Those changes remain behind the proposed ADRs and do not promote decisions, complete qualification gates or move work into Release 1 scope. The browser AD-PAIR-1 transcript/signature/key schedule, an interactive RFC 9383 SPAKE2+ P-256 session validated against the RFC vector, a loopback browser endpoint host service with app lifecycle wiring, workspace host handoff/degraded mode and an iOS capability catalog are now implemented and tested; browser QR/PIN challenge envelopes, attempt limiting, canonical DNS-SD advertisement records and browser-side COSE_Sign1 capability grants with bounded delegation/leases, `cnf` proof-of-possession, signed revocation snapshots and provider-side request authorization exist, while the QR/PIN UI/native flow, runtime discovery adapter, revocation distribution, native invocation enforcement, a production browser page, real network transports and remote execution are still pending.
>
> **Execution note (2026-11-07):** Native AD-PAIR-1 now uses the audited OpenSSL 3.6.5 P-256 group operations under ADR-022 and its scrypt implementation under ADR-023, reproduces the RFC 9383 SPAKE2+ vector, matches the browser password-registration profile, reproduces the browser AD-PAIR-1 transcript/signature/session-key fixture and derives workspace sync keys from the pairing transport key. The QR/PIN UI, live channel-binding acquisition and automatic sync activation remain pending under ADR-011/SYNC-01.
>
>
> **Execution note (2026-11-08):** Native PIN/QR pairing now runs end to end over a dedicated Iroh `.pairing` channel, uses an authenticated `iroh-endpoint` binding for native-native sessions, records peers as pending until SAS confirmation before releasing workspace-sync keys and exposes a Settings pairing flow. `iroh-endpoint` is an extension; browser TLS exporter and DTLS certificate binding helpers exist, and both native and browser peers now derive the workspace sync key automatically from the pairing transport key after SAS, while the browser now has a concrete WebSocket signaling transport and still needs a deployed signaling service under ADR-011/SYNC-01.
> **Execution note (2026-11-09):** Android now runs native-native AD-PAIR-1 over a direct Iroh endpoint using `computer.iroh:iroh-android:1.2.0`, `relayMode = RelayMode.disabled()`, an `iroh-endpoint` channel binding, SAS confirmation and the Connect-tab host/controller flow. The binary WebSocket transport remains a fallback; no relay deployment is required for Android-iOS direct pairing. iOS already defaults to `.directOnly` with `presetMinimal`.
>
> **Execution note (2026-11-09):** ADR-024 is proposed for an additive shared Rust core behind UniFFI/WASM. No existing codec, crypto or platform implementation has moved; native paths remain until fixture equality, platform tests and rollback are demonstrated.
>
> **Execution note (2026-11-10):** ADR-025 accepts in-app ReplayKit capture of AirDesk-owned surfaces as the initial iOS host-capture path. Whole-device Broadcast Upload Extensions, macOS ScreenCaptureKit hosts and external host processes remain separately gated; no media pipeline or capture capability is implemented by this decision.
>
> **Execution note (2026-11-11):** ADR-026 records the standalone `core/airdeskd` persistent PTY daemon as a carve-out from ADR-024 while leaving SSH, local PTY and process spawning out of the shared core. Terminal ADFP payloads, bounded replay, multi-client attach and local lease enforcement are implemented and covered by Rust and Swift codec tests; a deployed transport, live-network survival and physical-device qualification remain pending.
>
> **Execution note (2026-11-12):** ADR-027 standardizes the terminal on WTerm plus the `@wterm/ghostty` WASM core after the P4-07 benchmark. `libghostty-vt` 0.6.3 is retained as a research reference only because it is a Bun/native FFI binding with no browser/WASM, DOM selection, accessibility or iOS target; the current engine remains the production path and no replacement is scheduled.
>
> **Execution note (2026-11-13):** ADR-028 accepts an operation log with `(lamport, actor, id)` ordering for workspace sync. `core/airdesk-sync` implements log merge, idempotent replay, conflict reporting, the shared operation-log fixture and a snapshot facade; UniFFI/WASM exports and the iOS/web sync cutover are in place with native fallback, while Android has no workspace sync runtime and native implementations remain.
>
> **Execution note (2026-11-13):** P3-08 adds the staged shared-core cutover. iOS, web and Android persist independent movement/envelope/pairing/sync flags with native rollback and telemetry. The iOS one-euro pointer filter and iOS/web workspace snapshot merges now run on the shared core with native fallback; envelope reports a binding fallback and pairing remains native behind independent cryptographic review. Android has no workspace sync runtime, and web/Android movement availability defaults stay off until their product loaders are wired. No duplicate implementation has been deleted; P3-09 remains gated on equivalence and a release rollback.
>
> **Execution note (2026-11-12):** User direction approved ADR-024 for the full shared-core boundary. The `core/` Cargo workspace and CI gate now exist with `airdesk-core`, `airdesk-protocol`, `airdesk-ffi` and `airdesk-wasm`; `core/airdeskd` remains a separate ADR-026 carve-out. P3-02/P3-03 moved packed/movement, one-euro, ADFP envelope and resource code into `core/airdesk-protocol` with legacy re-exports, P3-04 added the AD-PAIR-1 transcript/SAS/HKDF/scrypt schedule in `core/airdesk-pairing`; P3-05 added research-only RFC 9383 SPAKE2+ over P-256 with RFC-vector, `confirmV`-first, cofactor/subgroup and zeroization tests plus a non-authoritative UniFFI preview; P3-06 added generated UniFFI Swift/Kotlin bindings behind debug-only ABI smoke calls; and P3-07 added deterministic WASM smoke exports behind a browser adapter flag. P3-08 later added the staged cutover control plane and the iOS movement core path. The product owner accepted the SPAKE2+ review gate for the MVP on 2026-11-13; external independent audit remains recommended before general cutover, and every fixture-equality, platform, rollback and cutover gate remains in force.

| ADR | Decision | Decision status | Implementation status | Effective note |
| --- | --- | --- | --- | --- |
| [001](001-multi-runtime-architecture.md) | Multi-runtime architecture | Accepted | Phases 1–2 implemented | Amended by ADR-005, ADR-007, ADR-013, ADR-014, ADR-016, ADR-017, ADR-018 and ADR-019 |
| [002](002-gesture-libraries-and-typescript.md) | Gesture libraries and TypeScript | Accepted | In progress | Reviewed against workspace independence; window-manager portion superseded by ADR-007 |
| [003](003-dependency-admission-and-licensing.md) | Dependency admission and licensing | Proposed | Active policy | Applies to native agents, runtime providers, transports, storage and SDKs |
| [004](004-runtime-and-execution-baseline.md) | Runtime and execution baseline | Proposed | Wanix baseline active | Wanix is the preferred portable provider; WASI 0.2 worlds are baseline, WASI 0.3 is an evaluation target and WASIX is a vendor extension |
| [005](005-display-and-transport.md) | Display profiles and transport | Proposed | Partial | Display sessions present a workspace but do not own it; sequencing amended by ADR-013/014 |
| [006](006-remote-windowing.md) | Remote windowing | Proposed | Not started | Remote windows are presentation/execution adapters; post-MVP; Xpra reattach preferred over stateless RDP |
| [007](007-winbox-and-wterm.md) | WinBox and WTerm | Proposed | Production defaults | Shell and terminal must depend on application/runtime interfaces, not Wanix internals; terminal engine standardized by ADR-027 |
| [008](008-input-and-control-protocol.md) | Input and control protocol | Proposed | Implemented, gates pending | Input source, focus owner and multi-controller arbitration added by ADR-015 |
| [009](009-workspace-persistence-and-recovery.md) | Workspace persistence and recovery | Proposed | Partial | Major amendment: desired/observed state, resource references, independent recovery domains and `lww`/`append-log`/`manual` merge metadata; single-device manifest/store/recovery and a deterministic merge-conflict corpus are implemented, cross-device sync is not |
| [010](010-airdesk-fabric-protocol.md) | ADFP semantic scope | Proposed | In progress | Major amendment: AD-RUNTIME and AD-RESOURCE active; transport bindings are versioned separately from ADFP semantics; typed header/fabric payloads and Android codec exist, module/transport coverage is pending |
| [011](011-device-identity-discovery-pairing.md) | Identity, discovery and pairing | Proposed | In progress | Device trust is separate from workspace ownership; future user identity uses WebAuthn/FIDO2; Ed25519/P-256 identity, local registry/revocation, offer validation, the browser AD-PAIR-1 transcript/signature/key schedule and an interactive RFC 9383 P-256 SPAKE2+ session, scrypt password PBKDF, QR/PIN challenge envelopes with attempt limiting and canonical DNS-SD advertisement records exist; native PIN/QR pairing, SAS confirmation, pending-until-SAS device-registry trust and known-device revoke/remove now run over Iroh with an `iroh-endpoint` binding on iOS and Android, while the runtime discovery adapter and deployed browser signaling service are pending |
| [012](012-capability-advertisement-and-authorization.md) | Capability advertisement and authorization | Proposed | In progress | Capability leases, application context, scope and revocation; descriptors, the iOS/Android local capability catalogs, lease schema and browser `COSE_Sign1` issuance/verification with ≤3-hop attenuation, `cnf` proof-of-possession, signed revocation snapshots and provider-side request authorization exist; revocation distribution and native invocation enforcement are pending |
| [013](013-multi-transport-and-connectivity.md) | Multi-transport and connectivity | Proposed | In progress | Control, data, media and presentation are separate; WebTransport is a Baseline 2026 optional candidate; Iroh/WebSocket baselines exist, WebTransport remains gated |
| [014](014-browser-endpoint-topology.md) | Browser endpoint topology | Proposed | In progress | Major amendment: browser is a presentation endpoint; local agent is a host service, not workspace authority; loopback client/policy, Swift host service and app settings/diagnostics wiring exist, production page is pending |
| [015](015-session-ownership-and-multi-controller.md) | Session ownership and multi-controller | Proposed | Not started | Major amendment: workspace ownership, session ownership and controller attachment are distinct |
| [016](016-workspace-domain-model-and-authority.md) | Workspace domain model and authority | Proposed | Not started | Workspace identity is independent of devices, runtimes and display sessions |
| [017](017-workspace-orchestration-and-runtime-providers.md) | Workspace orchestration and runtime providers | Proposed | Partial | WorkspaceOrchestrator above SessionCoordinator; provider-neutral contract; remote Wanix may be imported over 9P; local orchestration/providers exist, remote import is pending |
| [018](018-native-device-agents-and-capability-host-abi.md) | Native device agents and capability host ABI | Proposed | In progress | Devices expose capabilities through native agents; Wanix is optional; host ABI maps to its file-service/exported-device boundary; Android agent/controller and iOS identity/capability-catalog baselines exist; WIT `airdesk:host-abi@0.2.0`, fixture and check gate landed, while runtime conformance, full capability-host integration and remote invocation remain pending |
| [019](019-application-model-and-lifecycle.md) | Application model and lifecycle | Proposed | Not started | Applications are provider-neutral; manifests pin WASI worlds; remote apps select protocols via AD-CAP |
| [020](020-workspace-host-role-and-authority-handoff.md) | Workspace host role and authority handoff | Proposed | Partial | `WorkspaceHost` owns store commits, structural sequencing and orchestration; input leases stay at the display sink; handoff is explicit and `host_epoch`-fenced; quiesce/stage/activate/retire, force takeover and degraded mode are implemented and tested, while distributed transfer/lease gates remain pending |
| [021](021-iroh-native-transport.md) | Iroh native transport adoption | Accepted | In progress | Official `IrohLib` 1.2.0, iOS 17.5, explicit self-hosted relay policy, browser remains WebSocket |
| [022](022-openssl-p256-group-arithmetic.md) | OpenSSL P-256 group arithmetic for native AD-PAIR-1 | Accepted | Implemented | OpenSSL 3.6.5 via `OpenSSL-Package` 3.6.5000, isolated to P-256 group operations; CryptoKit remains the general crypto provider |
| [023](023-openssl-scrypt-password-registration.md) | OpenSSL scrypt for native SPAKE2+ password registration | Accepted | Implemented | Same pinned OpenSSL distribution; fixed scrypt profile `N=32768, r=8, p=1, dkLen=80`, browser-compatible material and P-256 reduction |
| [024](024-shared-core-and-ffi-boundary.md) | Shared core and FFI boundary | Accepted | In progress | Additive `core/` workspace and CI scaffold exist; no implementation moved, and native paths remain until fixture equality, platform tests and rollback are proven |
| [025](025-host-capture-platform.md) | Host capture and media pipeline platform | Accepted | Not started | Initial iOS path is in-app ReplayKit capture of AirDesk-owned surfaces; whole-device broadcast extension and macOS ScreenCaptureKit host remain separately gated; no zero-copy or glass-to-glass claim |
| [026](026-persistent-pty-daemon.md) | Persistent PTY daemon boundary | Proposed | In progress | `core/airdeskd` is an isolated daemon, not shared-core/FFI; additive ADFP `TerminalMessage`, bounded sequence replay, multi-client attach and local lease checks exist; deployed transport and physical/live-network gates remain pending |
| [027](027-terminal-engine-standardization.md) | Terminal engine standardization | Accepted | WTerm + Ghostty WASM production | WTerm remains the renderer and `@wterm/ghostty` 0.5.7 the production core; `libghostty-vt` is a research reference only because it is a Bun/native FFI binding without browser, selection, accessibility or iOS support |
| [028](028-operation-based-workspace-sync.md) | Operation-based workspace sync | Accepted | Core implemented | `core/airdesk-sync` merges globally identified operations in `(lamport, actor, id)` order, projects them through existing metadata and exposes a snapshot facade; UniFFI/WASM exports and the iOS/web cutover use the P3-08 flags with native fallback, while Android has no sync runtime and native removal remains gated |

## Effective decisions

- **Primary domain object:** the workspace, independent of devices, runtimes and display sessions.
- **MVP sequencing:** stabilize the native personal workspace first, then add the device fabric, then universal display endpoints.
- **Orchestration:** `WorkspaceOrchestrator` owns workspace lifecycle, placement and reconciliation above `SessionCoordinator`.
- **Runtime:** Wanix is the preferred portable provider; WASI 0.2 worlds are baseline, WASI 0.3 is an evaluation and WASIX is a vendor extension.
- **Devices:** native agents expose capabilities; a device is useful without Wanix; remote namespaces may be imported over 9P.
- **Transport:** WebSocket is the browser baseline; Iroh is the native peer data plane under ADR-021 with direct-first, explicit self-hosted relay policy; WebTransport remains an optional Baseline 2026 candidate.
- **Persistence:** device-local first; fields declare `lww`, `append-log` or `manual`; ADR-028 adds a shared-core operation log ordered by `(lamport, actor, id)` for future convergence; encrypted cross-device synchronization is later; CRDTs are shared-document only.
- **Display:** a display session, including a browser endpoint, presents a workspace but is not its authority; browser starts single-threaded. Initial iOS host capture is in-app ReplayKit capture of AirDesk-owned surfaces; whole-device broadcast and macOS ScreenCaptureKit hosts are separate gated paths.
- **Identity:** Ed25519 default with P-256 fallback; device trust is not workspace ownership or collaboration; future user identity uses WebAuthn/FIDO2; native AD-PAIR-1 uses isolated OpenSSL P-256 group operations under ADR-022, with browser-compatible QR/PIN challenge envelopes, PIN attempt limiting and a headless initiator/responder coordinator in `PairingCode.swift` and `PairingCoordinator.swift`.
- **Capabilities:** scoped, time-bounded, revocable leases; advertisement is not permission.
- **Input:** multiple controllers may attach; one keyboard focus owner at a time; this is not multi-user collaboration.
- **Persistent terminal:** `core/airdeskd` is a standalone, locally protected daemon outside the shared core/FFI boundary; terminal attachment uses additive ADFP `TerminalMessage` frames, bounded sequence replay, explicit client lifecycle and local lease checks. It does not own workspace authority, identity or transport authentication.
- **Shared core:** ADR-024 is accepted for an additive Rust workspace under `core/`; platform I/O and authority stay native, and no component may cut over until fixture equality, platform tests and rollback are proven.

## Delivery phase and lineage

Phase is a planning label. It does not change decision or implementation status.

| Phase | Meaning | Records |
| --- | --- | --- |
| Phase 1 baseline | Describes behavior the shipped app is built around; implementation status is per ADR | ADR-001 – ADR-009 |
| Phase 2/3 target | Describes the device-fabric architecture; foundations are in progress behind proposed ADRs | ADR-010 – ADR-020 |

Lineage is recorded explicitly so a fabric ADR cannot silently redefine a baseline decision:

- ADR-010 (ADFP) extends ADR-008 (input/control wire protocol).
- ADR-013 and ADR-014 extend ADR-005 (display and transport) and build on ADR-011/012.
- ADR-015 and ADR-016 extend ADR-009 (workspace persistence and recovery).
- ADR-017 and ADR-018 extend ADR-001 and ADR-004 (runtime and execution).
- ADR-019 extends ADR-006 and ADR-007 (remote windowing and shell/terminal).
- ADR-020 extends ADR-009, ADR-012, ADR-015, ADR-016 and ADR-017 (host role and authority handoff).

CI verification gates referenced by the records:

- `.github/workflows/ios.yml` — iOS build and unit tests.
- `.github/workflows/desktop-shell.yml` — TypeScript build, artifact-diff gate, dependency/SBOM check, `flatc --conform` and generated-binding drift.
- `AirDeskTests/`, `AirDeskUITests/`, `web/test/` — behavior suites cited by each Phase 1 record.
- Phase 2/3 records remain `Proposed` until their protocol fixtures and qualification gates exist; the phase label does not promote them to `Accepted`.

## Status rules

- **Decision status** records whether the architecture choice is accepted.
- **Implementation status** records whether the code and qualification gates are complete.
- An ADR is not promoted to Accepted solely because code exists or because the blueprint references it.
- Amendments do not rewrite history; they add a note here and in the ADR header.
- A proposed ADR may be implemented behind a flag while its gates remain open.
