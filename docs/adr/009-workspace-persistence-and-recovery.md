# ADR-009: Workspace persistence, desired state and recovery

- **Status:** Proposed — implementation and recovery gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — major amendment for workspace desired/observed state and independent recovery domains
- **Updated:** 2026-11-03 — research update: per-field merge metadata recorded now; CRDTs confined to Release 5 shared documents
- **Deciders:** Product owner, engineering lead
- **Scope:** Workspace manifest, desired/observed state, merge metadata, local storage, resource references, recovery checkpoints, migration, layout persistence
- **Supersedes:** None
- **Amends:** ADR-001, ADR-005, ADR-016
- **Related:** ADR-004, ADR-011, ADR-013, ADR-014, ADR-015, ADR-016, ADR-017, ADR-019

## Context

The current `Workspace` is a runtime label plus an identifier. `SessionCoordinator` resets to `.default` during session setup, and `SessionRecovery` is retry backoff rather than durable state restoration. Window state is owned by the desktop shell and WinBox adapter.

That is a product problem, not only an implementation gap. A workspace that loses its layout, preferences and application state on disconnect is a demonstration rather than a dependable workspace.

The revised blueprint makes the workspace the persistent logical environment and separates desired state from observed state. This ADR defines persistence and recovery for that model.

Storage domains have different guarantees and must not be treated as one:

- native workspace and application storage;
- Wanix and browser OPFS/IndexedDB storage;
- Cast receiver storage;
- remote terminal sessions;
- native SSH and Keychain credentials.

## Decision

### 1. Workspace persists independently of runtime and display

Introduce a versioned `WorkspaceManifest` owned by AirDesk, not by Wanix, WinBox, WebKit, a Cast receiver or a browser endpoint. A runtime binds to a workspace; it does not define it.

The manifest contains:

| Field | Purpose |
| --- | --- |
| `id` | Stable workspace identity, independent of device, runtime and session |
| `schemaVersion` | Manifest schema version |
| `revision` | Monotonic local revision |
| `owner` | Local personal identity reference; not a device identity |
| `metadata` | Name, timestamps, last active device |
| `layout` | Logical display preferences, window records and focus order |
| `applications` | Application definitions |
| `instances` | Desired instance state, placement and configuration |
| `executionBindings` | Preferred provider, placement and fallback policy |
| `resources` | Resource references and access policy |
| `preferences` | Workspace-scoped user preferences |
| `mergeMetadata` | Per-field `lww`, `append-log` or `manual` classification for future sync |
| `recovery` | Last checkpoint ID, journal sequence and integrity hash |

The manifest must not contain credentials, private keys, raw terminal output, clipboard contents or arbitrary remote URIs.

### 2. Desired state and observed state are separate

The manifest is desired state. Observed state is produced by orchestration and runtime providers and is never merged into the manifest.

```text
ApplicationInstanceDefinition
  id, applicationId
  desiredState: running | stopped | suspended
  placement
  configuration
```

```text
ApplicationInstanceStatus
  instanceId
  observedState: starting | running | suspended | stopped | failed | unavailable
  runtimeProviderId, runtimeInstanceId, deviceId
  lastHeartbeat, lastError
```

- A disconnected device makes observed state `unavailable`; it does not remove the definition.
- A runtime failure reports `failed`; it does not rewrite desired state.
- Reconciling desired state is an orchestrator action, not a persistence mutation.

### 3. Resources are references

The manifest references resources rather than assuming one storage location:

```text
ResourceReference
  id
  kind: file | document | database | application-data | runtime-volume
  providerId
  resourceId
  accessPolicy
  persistence
```

- Resource identity is stable across devices and providers.
- Resource access policy is separate from runtime placement.
- Local, remote and later synchronized storage use the same reference model.
- A missing provider makes a resource unavailable; it does not silently rewrite the reference.

### 3.1 Merge class metadata is recorded now

Every synchronizable field carries metadata that states how a future sync layer may combine it:

| Merge class | Use |
| --- | --- |
| `lww` | Scalar preference or metadata where the latest accepted revision wins |
| `append-log` | Activity, history or event records that append rather than replace |
| `manual` | Identity, ownership, security, placement or structure that requires explicit user or orchestrator resolution |

```text
FieldMetadata
  path
  merge: lww | append-log | manual
  sinceSchemaVersion
```

Rules:

- V1 still rejects concurrent local writers; merge metadata does not enable merging.
- The workspace manifest, application definitions, resource ownership and security fields default to `manual`.
- Layout bounds and focus can be `lww`; history and audit records can be `append-log`.
- Unknown fields are treated as `manual` until classified.
- A field without merge metadata must not be synchronized automatically.
- CRDTs remain confined to Release 5 shared documents; they are not the workspace merge strategy.

### 4. Define a backend-neutral `WorkspaceStore`

The store contract supports:

- load latest committed manifest;
- commit an atomic revision;
- append a recovery journal entry;
- read a checkpoint;
- validate schema and integrity;
- migrate older schema versions;
- report durability honestly.

The v1 native reference uses an atomic file-backed manifest and append-only journal under Application Support. SQLite may replace the backend without changing the manifest contract if journal size, querying or transactional requirements justify it. A new database dependency requires ADR-003 admission.

### 5. Durability has a concrete definition

For the native store, a commit is durable only after:

1. the complete new revision is written;
2. the file is synchronized with `fsync` or `F_FULLFSYNC` where available;
3. an atomic rename publishes the revision;
4. the store records the commit result.

The implementation records the iOS file-protection class. Writes may fail when the device is locked; the UI must report that state rather than claiming success. Browser OPFS/IndexedDB durability is explicitly weaker and is not included in the native zero-loss gate.

### 6. Multiple writers are rejected, not merged

- The native store accepts one writer per workspace revision.
- A commit carries the expected revision.
- A mismatched revision is rejected and the caller must reload.
- Do not use last-writer-wins for workspace desired state, application definitions or resource ownership.
- Merge metadata is declarative for future sync; it does not relax the single-writer rule in v1.
- Multi-device synchronization later introduces explicit conflict policy; it is not simulated by concurrent local writes.
- CRDTs are not used for workspace desired state.
- A display session or runtime provider is never a second workspace writer.

### 7. Recovery domains are independent

Recovery must distinguish:

1. **Workspace recovery** — desired state, layout, preferences and metadata.
2. **Runtime recovery** — a provider restarting or reconnecting an instance.
3. **Display session recovery** — reconnecting or replacing presentation.
4. **Device attachment recovery** — a device or capability becoming available again.

Rules:

- A display reconnect must not recreate or overwrite the workspace.
- A runtime crash must not erase application definitions.
- A device disconnect must not revoke workspace ownership.
- Recovery reports what was restored, restarted, reattached, made unavailable or lost.
- Unresolved state is preserved for later reconciliation.

### 8. Terminal transcripts are a separate, sensitive store

- Terminal transcripts are not stored in the workspace manifest.
- Transcript persistence is opt-in or clearly disclosed.
- Transcripts are encrypted at rest and bounded by retention and size limits.
- Remote SSH output may contain secrets and is treated as sensitive.
- The `no raw terminal output in manifest` rule does not permit plaintext transcript storage elsewhere.
- Transcript replay never implies live process restoration.

### 9. Window layout is logical, not DOM state

Persist:

- Window identity and application instance.
- Bounds, display identity and display state.
- Focus order and active window.
- Surface type and connection health.

Do not persist raw `zIndex`, DOM nodes, WinBox instances or transient pointer state. z-order is reconstructed from focus history. WinBox remains an adapter, not the source of truth.

### 10. Schema evolution is mandatory

- Unknown optional fields are preserved where practical.
- Missing optional fields receive documented defaults.
- A failed migration must preserve the last readable revision.
- A corrupt manifest falls back to the last valid checkpoint and shows a recovery warning.
- Integrity hashes detect corruption; they do not authenticate the manifest.
- Schema versions are independent for workspace, application, capability and resource records.

### 11. Browser and receiver durability are qualified, not assumed

A Cast receiver or browser may report persistent storage while still losing it. `persistentStorage: true` is a capability observation, not a durability guarantee. Cross-device resume requires the later synchronization service and is out of scope for this ADR.

## Consequences

### Positive

- Workspace desired state survives device, runtime and display failure.
- Recovery behavior can be reasoned about per domain.
- Resource references allow local, remote and future synchronized storage.
- Runtime and display components cannot silently become persistence authorities.
- Browser and Cast storage limits are stated honestly.

### Negative

- Requires versioned schemas, migration and a journal.
- Requires reconciliation between desired and observed state.
- Recovery reports and UI states become more detailed.
- Cross-device synchronization remains deferred.

## Acceptance gates

- Workspace survives app termination, relaunch, display disconnect and receiver reload in controlled tests.
- A workspace can be restored without a display session.
- Desired application state is not rewritten by observed runtime failure.
- Corrupt manifest and failed migration fall back to the last valid revision with a user-visible report.
- Committed window layout and focus order restore without DOM or WinBox state.
- Terminal transcript restore is labeled separately from process restoration.
- No credentials or raw terminal output are written to the manifest or journal.
- Transcript persistence, if enabled, is encrypted at rest, bounded and disclosed.
- Browser OPFS eviction is documented as a limitation and does not corrupt native state.
- Committed-state loss is zero for the native store under the defined test matrix; browser and in-flight state are excluded and reported truthfully.
- Concurrent writers with a stale revision are rejected and cannot overwrite a newer revision.
- Every synchronizable field has `lww`, `append-log` or `manual` metadata; unclassified fields default to `manual` and are not auto-merged.
- Recovery distinguishes workspace, runtime, display and device-attachment outcomes.

## Out of scope

- Cloud sync and encrypted multi-device replication before Release 4.
- CRDTs or collaborative editing outside Release 5 shared documents.
- Multi-user ownership and permissions before Release 5.
- S3 or arbitrary remote snapshot URIs.
- Live shell process restoration across WebKit termination.
