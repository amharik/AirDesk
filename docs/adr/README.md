# Architecture decision index

This index is the authoritative map of which decision is in force. An ADR's original text is historical; amendments and supersessions are recorded here and in the ADR header.

> **Execution note (2026-11-04):** Decision status is unchanged. The active implementation track is the universal compute fabric research program in `docs/planning/universal-compute-fabric-research.md`; product release sequencing is paused until its R6 decision. Research spikes may implement proposed ADRs behind flags but do not promote them.
>
> **Execution note (2026-11-06):** User direction adopts Iroh for the native peer data plane under ADR-021. The browser endpoint remains WebSocket. Product release sequencing is still paused until R6; the Iroh adapter may be implemented and tested in parallel.
>
> **Execution note (2026-11-06):** User direction also authorized foundational implementation of Android, identity, ADFP, browser-endpoint, sync/collaboration and remote-placement work. Those changes remain behind the proposed ADRs and do not promote decisions, complete qualification gates or move work into Release 1 scope. The browser AD-PAIR-1 transcript/signature/key schedule, an interactive RFC 9383 SPAKE2+ P-256 session validated against the RFC vector, a loopback browser endpoint host service with app lifecycle wiring, workspace host handoff/degraded mode and an iOS capability catalog are now implemented and tested; browser QR/PIN challenge envelopes, attempt limiting, canonical DNS-SD advertisement records and browser-side COSE_Sign1 capability grants with bounded delegation/leases, `cnf` proof-of-possession and signed revocation snapshots exist, while the QR/PIN UI/native flow, runtime discovery adapter, revocation distribution, native invocation enforcement, a production browser page, real network transports and remote execution are still pending.

| ADR | Decision | Decision status | Implementation status | Effective note |
| --- | --- | --- | --- | --- |
| [001](001-multi-runtime-architecture.md) | Multi-runtime architecture | Accepted | Phases 1–2 implemented | Amended by ADR-005, ADR-007, ADR-013, ADR-014, ADR-016, ADR-017, ADR-018 and ADR-019 |
| [002](002-gesture-libraries-and-typescript.md) | Gesture libraries and TypeScript | Accepted | In progress | Reviewed against workspace independence; window-manager portion superseded by ADR-007 |
| [003](003-dependency-admission-and-licensing.md) | Dependency admission and licensing | Proposed | Active policy | Applies to native agents, runtime providers, transports, storage and SDKs |
| [004](004-runtime-and-execution-baseline.md) | Runtime and execution baseline | Proposed | Wanix baseline active | Wanix is the preferred portable provider; WASI 0.2 worlds are baseline, WASI 0.3 is an evaluation target and WASIX is a vendor extension |
| [005](005-display-and-transport.md) | Display profiles and transport | Proposed | Partial | Display sessions present a workspace but do not own it; sequencing amended by ADR-013/014 |
| [006](006-remote-windowing.md) | Remote windowing | Proposed | Not started | Remote windows are presentation/execution adapters; post-MVP; Xpra reattach preferred over stateless RDP |
| [007](007-winbox-and-wterm.md) | WinBox and WTerm | Proposed | Production defaults | Shell and terminal must depend on application/runtime interfaces, not Wanix internals |
| [008](008-input-and-control-protocol.md) | Input and control protocol | Proposed | Implemented, gates pending | Input source, focus owner and multi-controller arbitration added by ADR-015 |
| [009](009-workspace-persistence-and-recovery.md) | Workspace persistence and recovery | Proposed | Partial | Major amendment: desired/observed state, resource references, independent recovery domains and `lww`/`append-log`/`manual` merge metadata; single-device manifest/store/recovery and a deterministic merge-conflict corpus are implemented, cross-device sync is not |
| [010](010-airdesk-fabric-protocol.md) | ADFP semantic scope | Proposed | In progress | Major amendment: AD-RUNTIME and AD-RESOURCE active; transport bindings are versioned separately from ADFP semantics; typed header/fabric payloads and Android codec exist, module/transport coverage is pending |
| [011](011-device-identity-discovery-pairing.md) | Identity, discovery and pairing | Proposed | In progress | Device trust is separate from workspace ownership; future user identity uses WebAuthn/FIDO2; Ed25519/P-256 identity, local registry/revocation, offer validation, the browser AD-PAIR-1 transcript/signature/key schedule and an interactive RFC 9383 P-256 SPAKE2+ session, scrypt password PBKDF, QR/PIN challenge envelopes with attempt limiting and canonical DNS-SD advertisement records exist; the QR/PIN UI/native flow, runtime discovery adapter and real binding acquisition are pending |
| [012](012-capability-advertisement-and-authorization.md) | Capability advertisement and authorization | Proposed | In progress | Capability leases, application context, scope and revocation; descriptors, the iOS/Android local capability catalogs, lease schema and browser `COSE_Sign1` issuance/verification with ≤3-hop attenuation, `cnf` proof-of-possession and signed revocation snapshots exist; revocation distribution and native invocation enforcement are pending |
| [013](013-multi-transport-and-connectivity.md) | Multi-transport and connectivity | Proposed | In progress | Control, data, media and presentation are separate; WebTransport is a Baseline 2026 optional candidate; Iroh/WebSocket baselines exist, WebTransport remains gated |
| [014](014-browser-endpoint-topology.md) | Browser endpoint topology | Proposed | In progress | Major amendment: browser is a presentation endpoint; local agent is a host service, not workspace authority; loopback client/policy, Swift host service and app settings/diagnostics wiring exist, production page is pending |
| [015](015-session-ownership-and-multi-controller.md) | Session ownership and multi-controller | Proposed | Not started | Major amendment: workspace ownership, session ownership and controller attachment are distinct |
| [016](016-workspace-domain-model-and-authority.md) | Workspace domain model and authority | Proposed | Not started | Workspace identity is independent of devices, runtimes and display sessions |
| [017](017-workspace-orchestration-and-runtime-providers.md) | Workspace orchestration and runtime providers | Proposed | Partial | WorkspaceOrchestrator above SessionCoordinator; provider-neutral contract; remote Wanix may be imported over 9P; local orchestration/providers exist, remote import is pending |
| [018](018-native-device-agents-and-capability-host-abi.md) | Native device agents and capability host ABI | Proposed | In progress | Devices expose capabilities through native agents; Wanix is optional; host ABI maps to its file-service/exported-device boundary; Android agent/controller and iOS identity/capability-catalog baselines exist, full capability host and remote invocation are pending |
| [019](019-application-model-and-lifecycle.md) | Application model and lifecycle | Proposed | Not started | Applications are provider-neutral; manifests pin WASI worlds; remote apps select protocols via AD-CAP |
| [020](020-workspace-host-role-and-authority-handoff.md) | Workspace host role and authority handoff | Proposed | Partial | `WorkspaceHost` owns store commits, structural sequencing and orchestration; input leases stay at the display sink; handoff is explicit and `host_epoch`-fenced; quiesce/stage/activate/retire, force takeover and degraded mode are implemented and tested, while distributed transfer/lease gates remain pending |
| [021](021-iroh-native-transport.md) | Iroh native transport adoption | Accepted | In progress | Official `IrohLib` 1.2.0, iOS 17.5, explicit self-hosted relay policy, browser remains WebSocket |

## Effective decisions

- **Primary domain object:** the workspace, independent of devices, runtimes and display sessions.
- **MVP sequencing:** stabilize the native personal workspace first, then add the device fabric, then universal display endpoints.
- **Orchestration:** `WorkspaceOrchestrator` owns workspace lifecycle, placement and reconciliation above `SessionCoordinator`.
- **Runtime:** Wanix is the preferred portable provider; WASI 0.2 worlds are baseline, WASI 0.3 is an evaluation and WASIX is a vendor extension.
- **Devices:** native agents expose capabilities; a device is useful without Wanix; remote namespaces may be imported over 9P.
- **Transport:** WebSocket is the browser baseline; Iroh is the native peer data plane under ADR-021 with direct-first, explicit self-hosted relay policy; WebTransport remains an optional Baseline 2026 candidate.
- **Persistence:** device-local first; fields declare `lww`, `append-log` or `manual`; encrypted cross-device synchronization is later; CRDTs are shared-document only.
- **Display:** a display session, including a browser endpoint, presents a workspace but is not its authority; browser starts single-threaded.
- **Identity:** Ed25519 default with P-256 fallback; device trust is not workspace ownership or collaboration; future user identity uses WebAuthn/FIDO2.
- **Capabilities:** scoped, time-bounded, revocable leases; advertisement is not permission.
- **Input:** multiple controllers may attach; one keyboard focus owner at a time; this is not multi-user collaboration.

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
