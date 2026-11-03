# Architecture decision index

This index is the authoritative map of which decision is in force. An ADR's original text is historical; amendments and supersessions are recorded here and in the ADR header.

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
| [009](009-workspace-persistence-and-recovery.md) | Workspace persistence and recovery | Proposed | Not started | Major amendment: desired/observed state, resource references, independent recovery domains and `lww`/`append-log`/`manual` merge metadata |
| [010](010-airdesk-fabric-protocol.md) | ADFP semantic scope | Proposed | Not started | Major amendment: AD-RUNTIME and AD-RESOURCE active; transport bindings are versioned separately from ADFP semantics |
| [011](011-device-identity-discovery-pairing.md) | Identity, discovery and pairing | Proposed | Not started | Device trust is separate from workspace ownership; future user identity uses WebAuthn/FIDO2 |
| [012](012-capability-advertisement-and-authorization.md) | Capability advertisement and authorization | Proposed | Not started | Capability leases, application context, scope and revocation |
| [013](013-multi-transport-and-connectivity.md) | Multi-transport and connectivity | Proposed | Not started | Control, data, media and presentation are separate; WebTransport is a Baseline 2026 optional candidate |
| [014](014-browser-endpoint-topology.md) | Browser endpoint topology | Proposed | Not started | Major amendment: browser is a presentation endpoint; local agent is a host service, not workspace authority |
| [015](015-session-ownership-and-multi-controller.md) | Session ownership and multi-controller | Proposed | Not started | Major amendment: workspace ownership, session ownership and controller attachment are distinct |
| [016](016-workspace-domain-model-and-authority.md) | Workspace domain model and authority | Proposed | Not started | Workspace identity is independent of devices, runtimes and display sessions |
| [017](017-workspace-orchestration-and-runtime-providers.md) | Workspace orchestration and runtime providers | Proposed | Not started | WorkspaceOrchestrator above SessionCoordinator; provider-neutral contract; remote Wanix may be imported over 9P |
| [018](018-native-device-agents-and-capability-host-abi.md) | Native device agents and capability host ABI | Proposed | Not started | Devices expose capabilities through native agents; Wanix is optional; host ABI maps to its file-service/exported-device boundary |
| [019](019-application-model-and-lifecycle.md) | Application model and lifecycle | Proposed | Not started | Applications are provider-neutral; manifests pin WASI worlds; remote apps select protocols via AD-CAP |

## Effective decisions

- **Primary domain object:** the workspace, independent of devices, runtimes and display sessions.
- **MVP sequencing:** stabilize the native personal workspace first, then add the device fabric, then universal display endpoints.
- **Orchestration:** `WorkspaceOrchestrator` owns workspace lifecycle, placement and reconciliation above `SessionCoordinator`.
- **Runtime:** Wanix is the preferred portable provider; WASI 0.2 worlds are baseline, WASI 0.3 is an evaluation and WASIX is a vendor extension.
- **Devices:** native agents expose capabilities; a device is useful without Wanix; remote namespaces may be imported over 9P.
- **Transport:** WebSocket is the baseline; WebTransport is a Baseline 2026 optional candidate with WebSocket fallback.
- **Persistence:** device-local first; fields declare `lww`, `append-log` or `manual`; encrypted cross-device synchronization is later; CRDTs are shared-document only.
- **Display:** a display session, including a browser endpoint, presents a workspace but is not its authority; browser starts single-threaded.
- **Identity:** Ed25519 default with P-256 fallback; device trust is not workspace ownership or collaboration; future user identity uses WebAuthn/FIDO2.
- **Capabilities:** scoped, time-bounded, revocable leases; advertisement is not permission.
- **Input:** multiple controllers may attach; one keyboard focus owner at a time; this is not multi-user collaboration.

## Lifecycle tags and lineage

Every record carries one lifecycle tag, separate from its decision and implementation status:

| Tag | Meaning | Records |
| --- | --- | --- |
| `Accepted & Implemented (Phase 1 Baseline)` | Decision is in force and the local/Cast/SSH baseline implements it | ADR-001–ADR-009 |
| `Accepted — Phase 2/3 Architecture Target` | Decision is in force for the device fabric; implementation and qualification gates are open | ADR-010–ADR-019 |

Lineage is recorded explicitly so a fabric ADR cannot silently redefine a baseline decision:

- ADR-010 (ADFP) extends ADR-008 (input/control wire protocol).
- ADR-013 and ADR-014 extend ADR-005 (display and transport) and build on ADR-011/012.
- ADR-015 and ADR-016 extend ADR-009 (workspace persistence and recovery).
- ADR-017 and ADR-018 extend ADR-001 and ADR-004 (runtime and execution).
- ADR-019 extends ADR-006 and ADR-007 (remote windowing and shell/terminal).

CI verification gates referenced by the records:

- `.github/workflows/ios.yml` — iOS build and unit tests.
- `.github/workflows/desktop-shell.yml` — TypeScript build, artifact-diff gate, dependency/SBOM check, `flatc --conform` and generated-binding drift.
- `AirDeskTests/`, `AirDeskUITests/`, `web/test/` — behavior suites cited by each Phase 1 record.
- Phase 2/3 records remain `Proposed` until their protocol fixtures and qualification gates exist; the tag does not promote them to `Accepted & Implemented`.

## Status rules

- **Decision status** records whether the architecture choice is accepted.
- **Implementation status** records whether the code and qualification gates are complete.
- An ADR is not promoted to Accepted solely because code exists or because the blueprint references it.
- Amendments do not rewrite history; they add a note here and in the ADR header.
- A proposed ADR may be implemented behind a flag while its gates remain open.
