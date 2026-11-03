# Workspace domain model

The workspace is the persistent logical environment. ADR-016 is the decision record; this document describes the model in implementation terms.

## Identity and ownership

A workspace has a stable `WorkspaceId` that is independent of:

- the device where it was created;
- the runtime executing its applications;
- the display session presenting it;
- the coordinator or browser endpoint.

The initial owner is a local personal identity. It is not a device identity. Future user identity and multi-user membership require a separate model.

## Manifest

```text
WorkspaceManifest
  id
  schemaVersion
  revision
  owner
  metadata
  applications[]
  instances[]
  layout
  preferences
  executionBindings[]
  resources[]
  mergeMetadata[]
  recovery
```

The manifest is desired state. It must not contain credentials, private keys, raw terminal output, clipboard contents or arbitrary remote URIs.

## Desired and observed state

Desired:

```text
ApplicationInstanceDefinition
  id, applicationId
  desiredState: running | stopped | suspended
  placement
  configuration
```

Observed:

```text
ApplicationInstanceStatus
  instanceId
  observedState: starting | running | suspended | stopped | failed | unavailable
  runtimeProviderId, runtimeInstanceId, deviceId
  lastHeartbeat, lastError
```

Observed state is produced by orchestration and runtime providers. It is never merged into the manifest.

## Sequencing and concurrency

The workspace host is the single-writer sequencer for structural mutations. Each accepted transition gets a contiguous `workspaceSeq`.

- A structural update carries the expected `workspaceSeq`; a stale value is rejected and the caller reloads.
- Display sessions, runtimes, browser endpoints and devices never assign `workspaceSeq`.
- Window drag/resize geometry is optimistic and reconciled with LWW tagged by `(leaseEpoch, clientSeq)`.
- LWW applies only to geometry; identity, ownership, placement, resources and application definitions stay single-writer.
- Reconciled geometry does not advance `workspaceSeq`.

## Resources

```text
ResourceReference
  id
  kind: file | document | database | application-data | runtime-volume
  providerId
  resourceId
  accessPolicy
  persistence
```

Resources may live on a device, a remote provider or future synchronized storage. The workspace references them; it does not assume a single storage location.

## Merge metadata

Every field that may later be synchronized carries a merge class:

```text
FieldMetadata
  path
  merge: lww | append-log | manual
  sinceSchemaVersion
```

- `lww` is limited to scalar preferences or metadata where the latest accepted revision wins.
- `append-log` is for history and audit records.
- `manual` is the default for identity, ownership, security, placement and structural changes.
- V1 still rejects concurrent writers. Merge metadata prepares Release 4 sync; it does not enable multi-writer behavior.
- CRDTs are confined to Release 5 shared documents.

## Lifecycle

The workspace is long-lived. Application instances, runtime instances and display sessions are not.

- A workspace may exist with zero display sessions.
- A workspace may exist with zero available devices.
- A workspace may contain application definitions whose instances are unavailable.
- A device failure does not delete the workspace.
- A runtime failure does not delete application definitions.

## Recovery domains

| Domain | Recovers | Does not recover |
| --- | --- | --- |
| Workspace | identity, desired state, layout, preferences, metadata | runtime processes |
| Runtime | provider instance and execution state | workspace identity |
| Display session | presentation, viewport and controller attachment | canonical workspace |
| Device attachment | capability availability and leases | workspace ownership |

## Boundary rules

- The workspace store is not the shell.
- The workspace store is not Wanix.
- The workspace store is not a browser endpoint.
- The workspace store is not the coordinator.
- A display session may cache presentation state but may not write canonical workspace state.
- The orchestrator reconciles desired and observed state; it does not rewrite desired state to match failure.
