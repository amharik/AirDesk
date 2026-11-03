# Architecture decision index

This index is the authoritative map of which decision is in force. An ADR's original text is historical; amendments and supersessions are recorded here and in the ADR header.

| ADR | Decision | Decision status | Implementation status | Effective note |
| --- | --- | --- | --- | --- |
| [001](001-multi-runtime-architecture.md) | Multi-runtime architecture | Accepted | Phases 1–2 implemented | Amended by ADR-005, ADR-007, ADR-013, ADR-014, ADR-016, ADR-017, ADR-018 and ADR-019 |
| [002](002-gesture-libraries-and-typescript.md) | Gesture libraries and TypeScript | Accepted | In progress | Reviewed against workspace independence; window-manager portion superseded by ADR-007 |
| [003](003-dependency-admission-and-licensing.md) | Dependency admission and licensing | Proposed | Active policy | Applies to native agents, runtime providers, transports, storage and SDKs |
| [004](004-runtime-and-execution-baseline.md) | Runtime and execution baseline | Proposed | Wanix baseline active | Wanix is the preferred portable provider, not the only runtime; native and browser providers are first-class |
| [005](005-display-and-transport.md) | Display profiles and transport | Proposed | Partial | Display sessions present a workspace but do not own it; sequencing amended by ADR-013/014 |
| [006](006-remote-windowing.md) | Remote windowing | Proposed | Not started | Remote windows are presentation/execution adapters; post-MVP |
| [007](007-winbox-and-wterm.md) | WinBox and WTerm | Proposed | Production defaults | Shell and terminal must depend on application/runtime interfaces, not Wanix internals |
| [008](008-input-and-control-protocol.md) | Input and control protocol | Proposed | Implemented, gates pending | Input source, focus owner and multi-controller arbitration added by ADR-015 |
| [009](009-workspace-persistence-and-recovery.md) | Workspace persistence and recovery | Proposed | Not started | Major amendment: desired state, observed state, resource references and independent recovery domains |
| [010](010-airdesk-fabric-protocol.md) | ADFP semantic scope | Proposed | Not started | Major amendment: AD-RUNTIME and AD-RESOURCE active; orchestration and lifecycle messages |
| [011](011-device-identity-discovery-pairing.md) | Identity, discovery and pairing | Proposed | Not started | Device trust is separate from workspace ownership and future user identity |
| [012](012-capability-advertisement-and-authorization.md) | Capability advertisement and authorization | Proposed | Not started | Capability leases, application context, scope and revocation |
| [013](013-multi-transport-and-connectivity.md) | Multi-transport and connectivity | Proposed | Not started | Control, data, media and presentation transport are separate concerns |
| [014](014-browser-endpoint-topology.md) | Browser endpoint topology | Proposed | Not started | Major amendment: browser is a presentation endpoint; local agent is a host service, not workspace authority |
| [015](015-session-ownership-and-multi-controller.md) | Session ownership and multi-controller | Proposed | Not started | Major amendment: workspace ownership, session ownership and controller attachment are distinct |
| [016](016-workspace-domain-model-and-authority.md) | Workspace domain model and authority | Proposed | Not started | Workspace identity is independent of devices, runtimes and display sessions |
| [017](017-workspace-orchestration-and-runtime-providers.md) | Workspace orchestration and runtime providers | Proposed | Not started | WorkspaceOrchestrator above SessionCoordinator; provider-neutral runtime contract |
| [018](018-native-device-agents-and-capability-host-abi.md) | Native device agents and capability host ABI | Proposed | Not started | Devices expose capabilities through native agents; Wanix is optional |
| [019](019-application-model-and-lifecycle.md) | Application model and lifecycle | Proposed | Not started | Applications are first-class provider-neutral workspace entities |

## Effective decisions

- **Primary domain object:** the workspace, independent of devices, runtimes and display sessions.
- **MVP sequencing:** stabilize the native personal workspace first, then add the device fabric, then universal display endpoints.
- **Orchestration:** `WorkspaceOrchestrator` owns workspace lifecycle, placement and reconciliation above `SessionCoordinator`.
- **Runtime:** Wanix is the preferred portable provider; native and browser execution are first-class alternatives, not fallbacks.
- **Devices:** native agents expose capabilities; a device is useful without Wanix.
- **Persistence:** device-local first; encrypted cross-device synchronization is later.
- **Display:** a display session, including a browser endpoint, presents a workspace but is not its authority.
- **Identity:** Ed25519 default with P-256 fallback; device trust is not workspace ownership or collaboration.
- **Capabilities:** scoped, time-bounded, revocable leases; advertisement is not permission.
- **Input:** multiple controllers may attach; one keyboard focus owner at a time; this is not multi-user collaboration.

## Status rules

- **Decision status** records whether the architecture choice is accepted.
- **Implementation status** records whether the code and qualification gates are complete.
- An ADR is not promoted to Accepted solely because code exists or because the blueprint references it.
- Amendments do not rewrite history; they add a note here and in the ADR header.
- A proposed ADR may be implemented behind a flag while its gates remain open.
