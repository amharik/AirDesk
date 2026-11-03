# Architecture decision index

This index is the authoritative map of which decision is in force. An ADR's original text is historical; amendments and supersessions are recorded here and in the ADR header.

| ADR | Decision | Decision status | Implementation status | Effective note |
| --- | --- | --- | --- | --- |
| [001](001-multi-runtime-architecture.md) | Multi-runtime architecture | Accepted | Phases 1–2 implemented | Amended by ADR-005, ADR-007, ADR-013 and ADR-014 |
| [002](002-gesture-libraries-and-typescript.md) | Gesture libraries and TypeScript | Accepted | In progress | Window-manager portion superseded by ADR-007 |
| [003](003-dependency-admission-and-licensing.md) | Dependency admission and licensing | Proposed | Active policy | Required for new transport, database and SDK dependencies |
| [004](004-runtime-and-execution-baseline.md) | Runtime and execution baseline | Proposed | Wanix baseline active | Puter removed; wazero executes WASI modules inside Wanix |
| [005](005-display-and-transport.md) | Display profiles and transport | Proposed | Partial | Transport sequencing amended by ADR-013; browser topology by ADR-014 |
| [006](006-remote-windowing.md) | Remote windowing | Proposed | Not started | Post-MVP, per ADR-006 |
| [007](007-winbox-and-wterm.md) | WinBox and WTerm | Proposed | Production defaults | Split into decision, spike report and native SSH ADR pending |
| [008](008-input-and-control-protocol.md) | Input and control protocol | Proposed | Implemented, gates pending | Canonical input vocabulary remains in force |
| [009](009-workspace-persistence-and-recovery.md) | Workspace persistence and recovery | Proposed | Not started | Device-local state; browser aggregate is not a replica |
| [010](010-airdesk-fabric-protocol.md) | ADFP semantic scope | Proposed | Not started | Extends ADR-005 and ADR-008; does not replace them |
| [011](011-device-identity-discovery-pairing.md) | Identity, discovery and pairing | Proposed | Not started | Ed25519 default, P-256 fallback |
| [012](012-capability-advertisement-and-authorization.md) | Capability advertisement and authorization | Proposed | Not started | Full model retained; browser apps are consumers |
| [013](013-multi-transport-and-connectivity.md) | Multi-transport and connectivity | Proposed | Not started | Sequenced after browser endpoint; no WebRTC requirement |
| [014](014-browser-endpoint-topology.md) | Browser endpoint topology | Proposed | Not started | Local agent + coordinator + direct data, relay later |
| [015](015-session-ownership-and-multi-controller.md) | Session ownership and multi-controller | Proposed | Not started | Device-local ownership; multi-pointer default, single keyboard focus |

## Effective decisions

- **MVP endpoint:** browser surface served by a local AirDesk agent; coordinator for registry and pairing; direct data path; relay later.
- **Workspace authority:** each device owns its local state; the browser keeps an aggregate session for display and input; coordinator-owned session metadata is future work.
- **Identity:** Ed25519 default with P-256 fallback; browser identity storage is re-paired if browser storage is evicted.
- **Capabilities:** full descriptor model retained; browser applications consume files, camera and other grants.
- **Multi-controller:** multiple device cursors are the default; keyboard focus is owned by one device at a time with explicit handoff.

## Status rules

- **Decision status** records whether the architecture choice is accepted.
- **Implementation status** records whether the code and qualification gates are complete.
- An ADR is not promoted to Accepted solely because code exists.
- Amendments do not rewrite history; they add a note here and in the ADR header.
- A proposed ADR may be implemented behind a flag while its gates remain open.
