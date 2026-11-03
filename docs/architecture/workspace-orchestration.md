# Workspace orchestration

`WorkspaceOrchestrator` is the component that turns persistent workspace desired state into an active realization using devices, capabilities and runtime providers.

## Responsibilities

- Open, close, load and save workspaces.
- Resolve participating devices and required capabilities.
- Select runtime providers and execution placement.
- Coordinate application lifecycle.
- Reconcile desired and observed state.
- Recover after device, runtime or display failure.
- Enforce workspace-level policy.

## Non-responsibilities

- OS functionality.
- Arbitrary workload execution.
- Transport implementation.
- Display composition.
- Workspace persistence storage itself.
- Multi-user membership and roles.

## Relationship to SessionCoordinator

`SessionCoordinator` manages:

- display session creation and closing;
- controller attachment and detachment;
- session connectivity and heartbeats;
- presentation-session state and input focus;
- session-level recovery.

The orchestrator calls the session coordinator. The session coordinator is not authoritative for workspace state.

## Interfaces

```text
WorkspaceOrchestrator
  openWorkspace(workspaceId)
  closeWorkspace(workspaceId)
  attachDevice(workspaceId, deviceId)
  detachDevice(workspaceId, deviceId)
  resolveCapabilities(workspaceId, requirements)
  placeApplication(workspaceId, instanceId)
  reconcileWorkspace(workspaceId)
```

```text
SessionCoordinator
  createSession(workspaceId, endpointId)
  attachController(sessionId, controllerId)
  detachController(sessionId, controllerId)
  closeSession(sessionId)
```

These are logical contracts, not a microservice requirement.

## Reconciliation

1. Load desired state.
2. Discover devices and runtime providers.
3. Read observed application, capability and runtime state.
4. Compare desired and observed state.
5. Determine required actions.
6. Apply authorized actions.
7. Record resulting state.
8. Retry transient failures with bounded backoff.
9. Preserve unresolved state for later recovery.

The first implementation is local and deterministic. A distributed scheduler is not required.

## Placement

Initial modes:

- `local-preferred`;
- explicit `device`;
- explicit `runtime`.

Automatic constrained placement is a later release. Placement must be explainable in diagnostics and must fail closed when no compatible provider exists.

## Failure behavior

- Device disconnect: mark affected observed state unavailable; keep desired state.
- Runtime failure: mark instance failed; keep definition.
- Display close: end the session; do not stop unrelated runtimes.
- Orchestrator restart: reload desired state and reconcile.
- Coordinator outage: local workspace operation continues where possible.
