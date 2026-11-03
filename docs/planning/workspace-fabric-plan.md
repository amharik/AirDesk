# AirDesk Workspace Fabric Plan

- **Status:** Proposed — implementation has not started
- **Date:** 2026-11-03
- **Scope:** Workspace-centric product sequence, device fabric, runtime providers, protocol and capability foundation, release gates
- **Related:** ADR-001 through ADR-019

## 1. Decision summary

| Area | Decision |
| --- | --- |
| Product | Distributed personal workspace, not a remote-desktop client or operating-system replacement |
| Workspace | Persistent logical environment independent of devices, runtimes and display sessions |
| Authority | Workspace model owns identity and desired state; coordinator, endpoints and providers are not workspace authority |
| Orchestration | `WorkspaceOrchestrator` above `SessionCoordinator`; deterministic local reconciliation first |
| Runtimes | Provider-neutral; native, Wanix and browser execution are first-class; Wanix is preferred, not mandatory |
| Devices | Native agents expose scoped capabilities; pairing grants trust, not workspace ownership |
| Protocol | ADFP with AD-RUNTIME and AD-RESOURCE active for the MVP; AD-WS/DEV/CAP/INPUT/DISPLAY baseline |
| Browser | Presentation endpoint in Release 3, not the first-release authority or MVP requirement |
| Multi-controller | Multi-pointer default; one keyboard focus owner with explicit handoff |
| Persistence | Device-local first; encrypted synchronization in Release 4 |
| Collaboration | Shared workspaces in Release 5; not inferred from pairing or controllers |
| License | Open business decision; required before SDK or ecosystem publication |

These decisions are recorded in ADR-001 through ADR-019. Implementation must not promote an ADR or release gate ahead of evidence.

## 2. Release sequence

### Release 1 — Stable personal workspace

**Goal:** A coherent, recoverable workspace on one device.

| ID | Task | Est. | Depends | Acceptance |
| --- | --- | ---: | --- | --- |
| GOV-01 | Approve workspace-centric architecture baseline | 2 | — | Product, architecture and release sequence approved |
| GOV-02 | Maintain ADR index and truthful status fields | 1 | GOV-01 | Decision status separated from implementation status |
| GOV-03 | Publish release-gate matrix and definitions | 2 | GOV-01 | Supported combinations and measurements documented |
| SEC-01 | Remove or redact sensitive input logging | 2 | — | No typed text, bridge payloads or JavaScript content in release logs |
| SEC-02 | Enforce strict origin matching | 1.5 | — | Exact scheme/host/port checks at all call sites and tests |
| SEC-03 | Harden local asset serving | 2.5 | — | Host/Origin validation, request bounds, symlink containment and per-session token |
| SEC-04 | Write the workspace/device threat model | 3 | GOV-03 | Covers workspace authority, local agent, browser, pairing, capabilities and SDK boundaries |
| CI-01 | Enforce protocol generation in CI | 2 | — | Generated bindings match schema; generator version pinned |
| CI-02 | Add protocol conformance tests | 2 | CI-01 | Swift and TypeScript fixtures round-trip; malformed frames rejected |
| CI-03 | Add protocol and third-party paths to workflows | 0.5 | CI-01 | Relevant changes trigger protocol and dependency checks |
| CI-04 | Add SBOM and dependency checks to release | 2 | — | SBOM generated and verified as a release artifact |
| WS-01 | Approve ADR-016 and workspace schema | 2 | GOV-03 | Identity, desired/observed state, resources and recovery domains approved |
| WS-02 | Implement workspace manifest and store | 5 | WS-01 | Versioned manifest, atomic writes, revision checks and backend-neutral interface |
| WS-03 | Separate desired and observed state | 4 | WS-02 | Observed runtime, application and capability state is never merged into manifest |
| WS-04 | Persist logical workspace layout | 3 | WS-02 | Window identity, bounds, display, state and focus order restored without DOM state |
| WS-05 | Add recovery test suite | 3 | WS-03, WS-04 | Relaunch, disconnect, corruption, migration, disk-full and atomic-write tests |
| RT-01 | Approve ADR-004/017 provider model | 2 | GOV-03 | Runtime provider contract and placement boundaries approved |
| RT-02 | Implement runtime provider registry | 4 | RT-01 | Provider advertisement, selection and typed unavailable states |
| RT-03 | Wrap Wanix in a provider adapter | 6 | RT-02 | Wanix lifecycle is provider-managed; workspace does not depend on Wanix internals |
| RT-04 | Preserve native execution path | 4 | RT-02 | Native applications remain first-class and do not require Wanix |
| APP-01 | Approve ADR-019 application model | 2 | GOV-03 | Manifest, instance state and lifecycle approved |
| APP-02 | Implement application manifest and lifecycle | 5 | APP-01, RT-02 | Install, start, suspend, stop and observed status work |
| UX-01 | Add truthful restore report | 2 | WS-03 | UI states what was restored, restarted, reconnected or lost |
| A11Y-01 | Accessibility baseline | 3 | GOV-01 | VoiceOver, keyboard focus, Dynamic Type, reduced motion and IME text commit |
| PUTER-01 | Remove Puter entirely | 3 | — | Adapter, enum, UI, labels, Pro copy and tests removed; build and tests pass |

**Exit gate:** Workspace survives shell close and runtime/application failure; future or corrupt schemas are rejected safely; Wanix failure is visible; Puter is gone; no workspace credential is stored in the manifest.

### Release 2 — Personal device fabric

**Goal:** A second device contributes an authorized capability to the workspace.

| ID | Task | Est. | Depends | Acceptance |
| --- | --- | ---: | --- | --- |
| ID-01 | Device identity and QR pairing v1 | 6 | ADR-011 | Ed25519 default, P-256 fallback, nonce/expiry, mutual authentication and replay rejection |
| ID-02 | Device registry and revocation | 4 | ID-01 | Trusted devices listed; revocation invalidates trust and leases without deleting workspaces |
| AGENT-01 | Native device agent contract | 7 | ID-01, ADR-018 | Identity, capabilities, permissions, health and lifecycle exposed |
| AGENT-02 | iOS device agent baseline | 8 | AGENT-01 | Camera, files, input and health capabilities work under iOS permission rules |
| COORD-01 | Coordinator MVP | 8 | ID-01, ADR-014 | Registration, presence, pairing and signed revocation distribution; no content, keys or grants |
| ORCH-01 | Implement WorkspaceOrchestrator | 8 | WS-03, RT-02, AGENT-01 | Open, attach, place, reconcile and recover workspace |
| ORCH-02 | Integrate SessionCoordinator | 5 | ORCH-01, ADR-015 | Display and controller sessions are created and closed without workspace mutation |
| CAP-01 | Capability registry | 4 | ADR-012 | Descriptor validation; availability and authorization are separate |
| CAP-02 | Capability leases and revocation | 6 | CAP-01, ID-02 | Expiry, audit, signed revocation and lost-device flow work; coordinator cannot mint grants |
| INPUT-01 | Multi-controller arbitration | 5 | ORCH-02 | Distinct cursors; one keyboard focus owner with explicit handoff; no stuck input |
| PROTO-01 | Implement ADFP baseline | 6 | ADR-010 | Envelope, versioning, AD-WS/DEV/CAP/RUNTIME/RESOURCE/INPUT/DISPLAY baseline |
| XPORT-01 | Direct transport benchmark | 4 | AGENT-02 | WebRTC/QUIC versus WebSocket p50/p95 latency, CPU, reconnect and compatibility measured |
| XPORT-02 | Qualify direct transport | 2 | XPORT-01 | ADR-013 updated with evidence; relay remains absent |
| DISC-01 | Native discovery adapter spike | 2 | ID-01 | Bonjour/DNS-SD tested without leaking secrets or capabilities |
| A11Y-02 | Full accessibility audit | 5 | A11Y-01 | VoiceOver, keyboard-only, switch control, RTL and localization checks |

**Exit gate:** A paired device provides an authorized capability; pairing does not grant workspace ownership; unauthorized or revoked leases fail closed; device disconnect preserves workspace state; direct transport works without relay.

### Release 3 — Universal display endpoints

**Goal:** Present the workspace on supported native and browser endpoints.

| ID | Task | Est. | Depends | Acceptance |
| --- | --- | ---: | --- | --- |
| END-01 | Browser endpoint feasibility spike | 5 | Release 2 | Loopback hosting, COOP/COEP, secure context, asset isolation and QR bootstrap proven or disproven |
| END-02 | Local host agent | 7 | END-01, ORCH-02 | Serves browser endpoint over loopback with strict origin and capability boundaries |
| END-03 | Browser presentation endpoint | 10 | END-02 | Opens, pairs, presents workspace and recovers committed state; endpoint is not authority |
| AND-01 | Android device agent | 8 | AGENT-01 | Capability and presentation baseline under Android permissions |
| DISP-01 | USB-C/HDMI qualification | 5 | Release 2 | Supported combinations documented with known limitations |
| DISP-02 | AirPlay/external-display qualification | 4 | DISP-01 | Fallback path tested with truthful recovery |
| DISP-03 | Cast feasibility or qualification | 5 | Hardware available | Development-only until physical hardware passes; otherwise deferred |
| DISP-04 | Display reconnect and recovery | 4 | END-03, DISP-01 | Reconnect does not recreate the workspace |

**Exit gate:** Supported display endpoints present the workspace without becoming authority; browser hosting threat model and CSP/SRI requirements pass or the endpoint stays local-only; reconnect preserves workspace identity.

### Release 4 — Distributed execution

**Goal:** Run workloads on the most appropriate participating device.

| ID | Task | Est. | Depends | Acceptance |
| --- | --- | ---: | --- | --- |
| REM-01 | Remote Wanix provider | 8 | Release 2, RT-03 | Remote runtime lifecycle and observed status work |
| REM-02 | Placement policies | 5 | ORCH-01, REM-01 | Explicit local/device/runtime placement with explainable diagnostics |
| REM-03 | Remote terminal execution | 5 | REM-01 | Terminal workloads execute remotely with capability-scoped access |
| REM-04 | RDP RAIL and Xpra experiments | 8 | REM-03 | Feasibility documented; remote applications use shared window model |
| RES-01 | Cross-device resource access | 5 | CAP-02, AD-RESOURCE | Scoped resource handles, streaming and conflict errors |
| SYNC-01 | Encrypted workspace synchronization | 10 | WS-02, ID-02 | Explicit conflict model; no silent multi-writer corruption |
| SYNC-02 | Sync recovery and migration tests | 5 | SYNC-01 | Interrupted sync, version skew and revocation are testable |

**Exit gate:** Remote placement is explicit and authorized; network loss produces typed failure; synchronization does not introduce silent corruption.

### Release 5 — Intent and collaboration

**Goal:** Operate and share workspaces at a higher level.

| ID | Task | Est. | Depends | Acceptance |
| --- | --- | ---: | --- | --- |
| AI-01 | Intent-driven task interface | 8 | Release 4 | Tasks produce reviewable plans |
| AI-02 | Approval-gated agent operations | 6 | AI-01 | Destructive operations require explicit approval |
| GROUP-01 | Shared workspace identity and membership | 8 | SYNC-01 | Ownership, membership and roles are explicit |
| GROUP-02 | Collaboration permissions and audit | 6 | GROUP-01 | Access and revocation are auditable and testable |
| GROUP-03 | Shared resource semantics | 5 | GROUP-02 | Shared files and application data have explicit policy |
| GROUP-04 | Optional group sessions | 5 | GROUP-02 | Collaboration is not inferred from pairing or controllers |

**Exit gate:** Multiple authenticated users can collaborate with explicit ownership, permissions, conflict handling and revocation.

## 3. Cross-cutting gates

| Gate | Exit criteria |
| --- | --- |
| G0: Privacy and CI | No sensitive release logging; strict origins; protocol generation and conformance pass; SBOM produced |
| G1: Workspace durability | Desired state survives relaunch, disconnect, corruption and migration; restore report is truthful |
| G2: Device trust | Pairing rejects replay, expiry, transcript mismatch and bad signatures; revocation works; discovery leaks no secrets |
| G3: Capabilities | Unauthorized, expired and revoked leases are denied; invocation is auditable |
| G4: Orchestration | Desired and observed state remain separate; placement is explicit; failure preserves definitions |
| G5: Display endpoints | Endpoints present state without becoming workspace authority; reconnect does not recreate the workspace |
| G6: Transport | Direct path meets budget; relay is absent or explicitly authorized; transport changes follow evidence |
| G7: Accessibility | VoiceOver, keyboard-only, Dynamic Type, reduced motion and IME pass the supported matrix |
| G8: Multi-controller | Distinct cursors, single keyboard focus, explicit handoff, no stuck input and revocation enforcement |

### Measurement definitions

- **Input acknowledgement latency:** controller dispatch to bridge acknowledgement.
- **Input-to-frame latency:** controller dispatch to display-side frame application time.
- **Warm restart:** process start to a usable restored workspace.
- **Committed-state loss:** loss of state acknowledged as saved by the workspace store. In-flight writes and browser cache eviction are excluded and must be reported.
- **Stuck input:** a pressed key or button that remains pressed after disconnect, focus loss, generation change or cancellation.
- **Direct path:** device-to-device path without a coordinator or relay carrying workspace data.
- **Pairing success:** completion with transcript verification and an issued session credential.

Targets are qualification hypotheses, not current measurements. Do not claim results without a recorded scenario, device matrix and method.

## 4. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Workspace model expands into sync and CRDTs too early | Release 1 keeps device-local state and truthful recovery; sync is Release 4 |
| Runtime provider work destabilizes native shell | Provider contract behind a neutral interface; native path remains first-class |
| Wanix is assumed mandatory | Provider registry accepts native and browser providers; Wanix remains preferred where it fits |
| Device pairing is confused with ownership | ADR-011/015/016 separate device trust, controller attachment and workspace ownership |
| Capability model becomes device-wide access | ADR-012 requires scoped leases and typed operations |
| Browser endpoint becomes authority | ADR-014/016 explicitly prohibit it; Release 3 follows Release 2 |
| Coordinator compromise exposes content or keys | Coordinator carries no workspace data, private keys or grant minting |
| Coordinator availability blocks local use | Local workspace operation is independent; pairing and presence need short-lived coordination only |
| Remote execution causes hidden data movement | Placement is explicit and diagnostics show provider and device |
| Sync silently corrupts shared state | Release 4 requires an explicit conflict model and recovery tests |
| Cast or hardware qualification blocks release | Cast remains development-only until hardware is available |
| Accessibility deferred until after beta | Baseline in Release 1; full audit in Release 2 |
| Puter removal breaks runtime routing | Remove as one isolated change with build and test coverage |

## 5. Definition of done

Every task must include:

- Code and automated tests.
- Relevant ADR or documentation update.
- CI enforcement where applicable.
- No release logging of user input or secrets.
- Migration, rollback or feature-flag behavior.
- Manual verification on the supported matrix.
- An explicit statement of what is not supported.

## 6. ADR map

| ADR | Decision | Status |
| --- | --- | --- |
| ADR-001 | Multi-runtime architecture | Accepted |
| ADR-002 | Gesture libraries and TypeScript | Accepted |
| ADR-003 | Dependency admission and licensing | Proposed |
| ADR-004 | Runtime and execution baseline | Proposed |
| ADR-005 | Display and transport | Proposed |
| ADR-006 | Remote windowing | Proposed — post-MVP |
| ADR-007 | WinBox and WTerm | Proposed |
| ADR-008 | Input and control protocol | Proposed |
| ADR-009 | Workspace persistence and recovery | Proposed |
| ADR-010 | ADFP semantic scope and module boundaries | Proposed |
| ADR-011 | Device identity, discovery and secure pairing | Proposed |
| ADR-012 | Capability advertisement and authorization | Proposed |
| ADR-013 | Multi-transport and connectivity negotiation | Proposed |
| ADR-014 | Browser endpoint topology | Proposed |
| ADR-015 | Session ownership and multi-controller | Proposed |
| ADR-016 | Workspace domain model and authority | Proposed |
| ADR-017 | Workspace orchestration and runtime providers | Proposed |
| ADR-018 | Native device agents and capability host ABI | Proposed |
| ADR-019 | Application model and lifecycle | Proposed |

The ADR index in `docs/adr/README.md` is authoritative for decision status, implementation status and amendments.

## 7. Open business decision

The repository license is not decided by this plan. No SDK, reference receiver or host-agent publication should occur until the license, contribution model and trademark policy are chosen.
