# ADR-017: Workspace orchestration and runtime providers

- **Status:** Proposed — orchestration contracts and provider qualification required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — peer review: provider health checks, circuit breaker and failover state machine
- **Updated:** 2026-11-03 — peer review round 3: orchestrator placed on `WorkspaceHost`; host-degraded behavior defined
- **Amended by:** ADR-020 (workspace host role and authority handoff)
- **Deciders:** Engineering lead, product owner
- **Scope:** WorkspaceOrchestrator, SessionCoordinator boundary, RuntimeRegistry, RuntimeProvider, placement and reconciliation
- **Supersedes:** None
- **Amends:** ADR-001, ADR-004, ADR-009, ADR-014, ADR-015
- **Related:** ADR-010, ADR-012, ADR-016, ADR-018, ADR-019

## Context

`SessionCoordinator` currently owns connection setup, display profile selection and runtime attachment. That was adequate when a session and a runtime were nearly the same thing.

The revised blueprint separates:

- the persistent workspace;
- the orchestration of devices, capabilities and execution placement;
- display sessions and controller attachment;
- runtime execution.

Without that separation, display connectivity becomes execution authority, and runtime choice becomes workspace identity.

## Decision

### 1. WorkspaceOrchestrator sits above SessionCoordinator

`WorkspaceOrchestrator` is responsible for:

- creating, opening, loading and saving workspaces;
- resolving participating devices and required capabilities;
- selecting runtime providers;
- deciding execution placement;
- coordinating application lifecycle;
- reconciliation after device or runtime failure;
- workspace-level policy, recovery and restoration.

`SessionCoordinator` is responsible for:

- creating and closing display sessions;
- attaching and detaching controllers;
- tracking session connectivity and heartbeats;
- coordinating input focus and presentation-session state;
- session-level recovery.

The orchestrator calls the session coordinator. The session coordinator is not authoritative for workspace state.

`WorkspaceOrchestrator` runs on the `WorkspaceHost` (ADR-020), alongside store commits and structural sequencing. When the host is unreachable, orchestration is unavailable: running runtimes and leased input continue on the display side, but structural placement and lifecycle mutations fail with a typed error rather than being queued.

### 2. The logical contracts are explicit

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

These are logical contracts, not a requirement for a microservice deployment. Components may initially run in one process.

### 3. Runtime providers are interchangeable

Every runtime implements a provider-neutral contract:

```text
RuntimeProvider
  id()
  capabilities()
  create(request)
  start(instanceId)
  suspend(instanceId)
  stop(instanceId)
  status(instanceId)
  execute(instanceId, request)
  destroy(instanceId)
```

Initial providers:

- native platform execution;
- Wanix;
- browser execution.

Future providers:

- remote Wanix, including a namespace imported over 9P/WebSocket;
- SSH-backed applications;
- RDP RAIL or Xpra-backed applications;
- hosted execution.

A remote Wanix provider may expose a namespace as execution, resources or both. The orchestrator records which role the provider fulfils; a mounted namespace does not become workspace authority or bypass capability leases.

Remote application protocols are advertised through AD-CAP and selected by the orchestrator. Do not hard-code an RDP or Xpra branch in the workspace model.

Runtime providers do not own workspace identity, discovery, pairing, workspace persistence, synchronization, capability authorization, controller arbitration or transport selection.

### 4. RuntimeRegistry resolves providers

- `RuntimeRegistry` tracks provider availability, versions and supported capabilities.
- `CapabilityResolver` resolves provider facts; `ProfileResolver` resolves display/runtime profile axes.
- Provider selection is deterministic and explained in diagnostics.
- Unsupported required providers or versions fail closed with a typed error.

### 5. Placement is explicit

Initial placement policy supports:

| Mode | Meaning |
| --- | --- |
| `local-preferred` | Use a local provider unless a requirement forces another |
| `device` | Place on an explicitly selected device |
| `runtime` | Place on an explicitly selected provider |
| `automatic` | Future constrained placement; not MVP |

Release 1 supports local-preferred and explicit placement. Distributed scheduling is not part of the MVP.

### 6. Reconciliation is deterministic and local first

The orchestrator loop:

1. Load desired state.
2. Discover devices and runtime providers.
3. Read observed application, capability and runtime state.
4. Compare desired and observed state.
5. Determine required actions.
6. Apply only authorized actions.
7. Record resulting state.
8. Retry transient failures with bounded backoff.
9. Preserve unresolved state for later recovery.

The first implementation is local and deterministic. A distributed scheduler is out of scope.

### 6.1 Provider health, circuit breaking and failover

Mid-session loss of an SSH or LAN provider must be handled by an explicit state machine, not by retry storms or silent reruns.

| State | Enter when | Behavior |
| --- | --- | --- |
| `HEALTHY` | Health check succeeds | Serve requests; record latency |
| `DEGRADED` | One failed check or heartbeat late | Continue serving, increase check frequency, surface a warning |
| `OPEN` | Failure threshold reached (for example 3 consecutive failures) | Stop routing new work; fail fast with a typed error; do not restart the workload automatically |
| `HALF_OPEN` | Cooldown elapsed | Allow a single probe request; success returns to `HEALTHY`, failure returns to `OPEN` |

- Health checks are bounded, timed out and never block input or control traffic.
- Retries are bounded with exponential backoff and jitter; there is no unbounded retry loop.
- A workload whose provider is `OPEN` is marked `unavailable` or `failed`; the desired state is preserved.
- Warm-standby providers may be promoted only when placement policy allows it and the application can resume without data loss.
- Recovery is a reconciliation outcome and must not rewrite the workspace manifest.
- Circuit-breaker transitions and provider loss are recorded in diagnostics and audit.

### 7. Session lifecycle cannot implicitly start execution

- Creating a display session does not place or start an application.
- Connecting a controller does not grant capability access.
- A runtime starting does not change workspace identity.
- Closing a display session does not stop unrelated workloads.
- Stopping a runtime does not delete the application definition.

## Consequences

### Positive

- Runtime replacement becomes possible.
- Orchestration is not coupled to Wanix or a display session.
- Workspace lifecycle is independent of display lifecycle.
- Distributed execution can be introduced incrementally.
- Placement and failure behavior become testable.

### Negative

- Adds a coordination abstraction above the existing session code.
- Requires explicit runtime, application and reconciliation contracts.
- Provider compatibility and capability negotiation add complexity.
- Initial local reconciliation must not be mistaken for a distributed scheduler.

## Acceptance gates

- A workspace can open, reconcile and close without a display session.
- `SessionCoordinator` can create and close a session without creating a workspace.
- The orchestrator selects a provider through `RuntimeRegistry`, not a Wanix-specific branch.
- Native execution works without Wanix.
- A runtime failure leaves desired application state intact and reports observed failure.
- Orchestration runs on the `WorkspaceHost`; when it is unreachable, structural placement and lifecycle mutations fail with a typed error instead of queueing.
- Provider loss follows the `HEALTHY → DEGRADED → OPEN → HALF_OPEN` circuit-breaker table with bounded backoff; no unbounded retry or silent rerun occurs.
- Display reconnect does not restart unrelated runtimes.
- Placement is deterministic for the supported modes and explained in diagnostics.
- Provider version or capability mismatch fails closed.
- A remote namespace import is scoped to its provider role and cannot mutate workspace authority.
- Remote application providers are selected through AD-CAP descriptors, not protocol-specific branches.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Shell owns orchestration | Makes the shell the authority and couples reconciliation to one UI |
| Coordinator owns runtimes | Turns the control-plane coordinator into a data-plane authority |
| Per-provider ad hoc placement | Duplicates policy and produces inconsistent failure reporting |
| Host-local orchestrator with provider adapters | Chosen: one policy, typed provider differences and observed state that cannot rewrite desired state |
| Cloud scheduler | Adds a dependency and an availability requirement the local-first product rejects |

## Out of scope

- A general-purpose distributed scheduler.
- Automatic cross-device workload migration.
- Cloud execution providers.
- Multi-user placement policy.
- Microservice decomposition.
