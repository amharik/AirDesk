# ADR-016: Workspace domain model and authority

- **Status:** Proposed — domain schema and recovery gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — peer review: single-writer workspace sequencer and geometry LWW reconciliation
- **Deciders:** Product owner, engineering lead
- **Scope:** Workspace identity, desired state, observed state, resource references, ownership, recovery domains
- **Supersedes:** None
- **Amends:** ADR-001, ADR-005, ADR-009, ADR-014, ADR-015
- **Related:** ADR-004, ADR-010, ADR-011, ADR-012, ADR-017, ADR-018, ADR-019

## Context

AirDesk has decisions for runtimes, display profiles, input, persistence and device connectivity, but no single domain model that establishes what the persistent thing is.

Without that model, workspace state drifts toward whichever component is active: the native app, the Wanix namespace, the desktop shell, a Cast receiver, a browser endpoint or a display session. That makes portability, recovery and multi-device presentation impossible to reason about.

The revised blueprint establishes the workspace as the primary domain object. This ADR makes that authority explicit.

## Decision

### 1. Workspace is the persistent logical environment

A workspace is not a VM, framebuffer, runtime process, display session or device.

It has:

- stable workspace identity;
- an owner;
- schema version and revision;
- application definitions and desired instance state;
- layout and presentation preferences;
- execution bindings and placement preferences;
- resource references;
- recovery metadata;
- optional synchronized state in a later release.

The workspace remains meaningful when every device, runtime and display session is disconnected.

### 2. Workspace identity is independent of all realization details

- `WorkspaceId` is stable and is not derived from a device, runtime, session or display.
- A workspace may be opened on a different endpoint without changing identity.
- A device failure or runtime failure does not delete the workspace.
- A display session is a temporary presentation of a workspace.
- A runtime binds to a workspace; it does not define it.
- A browser endpoint is a presentation consumer, never the canonical owner.

### 3. Manifest represents desired state

The versioned manifest describes what the user wants:

```text
Workspace
  id, schemaVersion, revision, owner, metadata
  applications[]
  instances[]          -> desiredState, placement, configuration
  layout
  preferences
  executionBindings[]
  resources[]
  recovery
```

Observed state is stored separately and never written into the desired-state manifest:

```text
ApplicationInstanceStatus
  instanceId
  observedState
  runtimeProviderId, runtimeInstanceId, deviceId
  lastHeartbeat, lastError
```

A disconnected device makes an instance `unavailable`; it does not remove the instance definition or the workspace.

### 4. Ownership is layered

| Layer | Owns | Does not own |
| --- | --- | --- |
| Workspace owner | Workspace identity, desired state, membership in a later release | Runtime process or display session |
| Device | Local resources, platform permissions, device identity | Workspace identity or another device's state |
| Runtime provider | Execution environment and runtime lifecycle | Workspace identity, persistence or placement policy |
| Display session | Presentation state, focus and controller attachment | Canonical workspace state |
| Capability lease | Bounded authorization to use a capability | Workspace ownership |

A paired device is not a workspace collaborator. A controller is not a workspace owner.

### 5. Resources are references, not assumptions

```text
ResourceReference
  id
  kind: file | document | database | application-data | runtime-volume
  providerId
  resourceId
  accessPolicy
  persistence
```

A workspace does not assume that all resources live on the device that happens to be displaying it. Local, remote and later synchronized storage use the same reference model.

### 6. Recovery domains are independent

Recovery must distinguish:

1. Workspace recovery — desired state and metadata.
2. Runtime recovery — a provider restarting or reconnecting an instance.
3. Display session recovery — reconnecting or replacing presentation.
4. Device attachment recovery — a device or capability becoming available again.

A display reconnect must not recreate the workspace. A runtime crash must not erase application definitions. A device disconnect must not revoke workspace ownership.

### 7. Initial authority is local and explicit

- Release 1 stores the workspace locally and uses a single local authority.
- A future synchronization service introduces explicit membership and conflict policy.
- The coordinator is not the workspace authority.
- No runtime provider may claim authority over workspace identity or persistence.

### 7.1 Structural mutations use a single-writer sequencer

The workspace host is the **Single-Writer Sequencer** for structural mutations: creating or closing windows, attaching runtimes, changing `DisplayProfile`, and editing application definitions.

- Each accepted structural transition receives a contiguous `workspace_seq: uint64`.
- An update carries the expected `workspace_seq`; a stale sequence is rejected and the caller reloads.
- Only the workspace host assigns `workspace_seq`; display sessions, runtimes and browser endpoints never do.
- High-frequency window drag/resize geometry uses optimistic local rendering and Last-Writer-Wins reconciliation tagged with `(lease_epoch, client_seq)`.
- LWW applies only to geometry fields; application definitions, ownership and resource bindings remain single-writer and are never LWW-merged.
- A reconciled geometry update must not advance or reorder `workspace_seq`.
- The sequencer is local in Release 1; a future synchronization service preserves the same invariant per workspace.

### 8. Schema and evolution are mandatory

- Workspace, application, capability and resource schemas are versioned independently.
- Migrations preserve the last readable revision.
- Unknown optional fields are preserved where practical.
- A schema version mismatch fails closed with a typed error.

## Consequences

### Positive

- Workspace state becomes portable across endpoints and providers.
- Multiple display sessions can present one workspace.
- Device and runtime failure no longer implies workspace loss.
- Runtime replacement and distributed execution become possible incrementally.
- Device pairing cannot be mistaken for collaboration.

### Negative

- Requires a versioned domain schema and migrations.
- Requires reconciliation between desired and observed state.
- Requires explicit resource ownership and recovery semantics.
- Adds a coordination layer above the existing session lifecycle.
- Cross-device synchronization remains deferred.

## Acceptance gates

- A workspace can be created and restored without a display session.
- A workspace can be presented on a different endpoint without changing its identity.
- Structural mutations receive contiguous `workspace_seq` values, and a stale sequence is rejected; geometry LWW never advances the sequencer.
- A device disconnect marks observed state unavailable but leaves the desired state intact.
- A runtime failure does not delete application definitions or workspace metadata.
- A display session cannot write canonical workspace state.
- A browser endpoint cannot become the workspace authority.
- Resource references survive provider or device changes for local resources.
- A schema mismatch produces a typed error and preserves the last readable revision.
- Pairing and controller attachment do not grant workspace ownership.

## Out of scope

- Cross-device synchronization and conflict resolution.
- Multi-user workspace membership and roles.
- CRDTs across workspace state.
- Automatic live process migration.
- Cloud workspace hosting.
