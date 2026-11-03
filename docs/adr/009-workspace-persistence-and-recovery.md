# ADR-009: Runtime-independent workspace persistence and recovery

- **Status:** Proposed — implementation and recovery gates required
- **Date:** 2026-11-03
- **Scope:** Workspace manifest, local storage, recovery checkpoints, migration, window layout persistence
- **Supersedes:** None
- **Related:** ADR-001, ADR-004, ADR-005, ADR-007, ADR-011, ADR-013

## Context

The current `Workspace` is a runtime label plus an identifier. `SessionCoordinator` resets to `.default` during session setup, and `SessionRecovery` is retry backoff rather than durable state restoration. Window state is owned by the desktop shell and WinBox adapter.

This is a product problem, not only an implementation gap. A workspace that loses its layout, preferences and application state on disconnect is a demonstration rather than a dependable workspace.

AirDesk also has several storage domains with different guarantees:

- Native application storage.
- Wanix and browser OPFS/IndexedDB storage.
- Cast receiver storage.
- Remote terminal sessions.
- Native SSH and Keychain credentials.

These must not be treated as one durability domain.

## Decision

### 1. Workspace state is independent of the runtime

Introduce a versioned `WorkspaceManifest` owned by AirDesk, not by Wanix, WinBox, WebKit or a Cast receiver. A runtime binds to a workspace; it does not define the workspace.

The manifest contains:

| Field | Purpose |
| --- | --- |
| `id` | Stable workspace identity, not a device or runtime identity |
| `schemaVersion` | Manifest schema version |
| `revision` | Monotonic local revision |
| `metadata` | Name, timestamps, last active device |
| `layout` | Logical display preferences, window records and focus order |
| `applications` | Application instance identity, app type, execution plane and restore policy |
| `preferences` | Workspace-scoped user preferences |
| `runtimeBinding` | Last selected runtime and safe fallback |
| `recovery` | Last checkpoint ID, journal sequence and integrity hash |

The manifest must not contain credentials, private keys, raw terminal output, clipboard contents or arbitrary remote URIs.

### 2. Define a backend-neutral `WorkspaceStore`

The store contract supports:

- Load latest committed manifest.
- Commit an atomic revision.
- Append a recovery journal entry.
- Read a checkpoint.
- Validate schema and integrity.
- Migrate older schema versions.
- Report durability honestly.

The v1 native reference implementation uses an atomic file-backed manifest and append-only journal under Application Support. SQLite may replace the backend without changing the manifest contract if journal size, querying or transactional requirements justify it. A new database dependency requires ADR-003 admission.

Browser implementations use OPFS or IndexedDB as local, origin-scoped storage. Browser storage is not a backup and may be evicted.

### 3. Separate committed state from in-flight work

- **Committed state** is data acknowledged as saved by the store.
- **In-flight state** is data not yet committed.
- Forced termination may lose in-flight state.
- The UI must not claim that in-flight work was saved.
- Recovery tests measure loss of committed state, not arbitrary filesystem writes.

### 4. Recovery is explicit and truthful

Restore what can be restored and report the rest:

- Window layout, geometry and focus order.
- Open application instances where the runtime can recreate them.
- Preferences and selected runtime.
- Terminal transcript where available.
- Terminal process state: recreated or not restored.
- Remote SSH: reattached session or restarted shell.

`SessionRecovery` restores from the latest verified checkpoint. `.default` is used only for first launch or explicit workspace reset.

### 5. Window layout is logical, not DOM state

Persist:

- Window identity and application instance.
- Bounds, display identity and display state.
- Focus order and active window.
- Surface type and connection health.

Do not persist raw `zIndex`, DOM nodes, WinBox instances or transient pointer state. z-order is reconstructed from focus history. WinBox remains an adapter, not the source of truth.

### 6. Schema evolution is mandatory

- Unknown fields are preserved where practical.
- Missing optional fields receive documented defaults.
- A failed migration must preserve the last readable revision.
- A corrupt manifest falls back to the last valid checkpoint and shows a recovery warning.
- Integrity hashes detect corruption; they do not authenticate the manifest.

### 7. Browser and receiver durability are qualified, not assumed

A Cast receiver or browser may report persistent storage while still losing it. `persistentStorage: true` is a capability observation, not a durability guarantee. Cross-device resume requires a later synchronization service and is out of scope for this ADR.

## Consequences

### Positive

- Workspace identity survives runtime, display and receiver changes.
- Recovery behavior becomes testable and explainable.
- WinBox and Wanix can be replaced without losing workspace semantics.
- The product can stop making continuity claims it cannot prove.

### Negative

- Adds schema, migration and corruption-handling work.
- Requires coordinated changes in Swift and the desktop shell.
- Does not by itself provide synchronization or multi-device collaboration.
- Browser durability remains limited by the browser vendor's storage policy.

## Acceptance gates

- Workspace survives app termination, relaunch, display disconnect and receiver reload in controlled tests.
- Corrupt manifest and failed migration fall back to the last valid revision with a user-visible report.
- Committed window layout and focus order restore without DOM or WinBox state.
- Terminal transcript restore is labeled separately from process restoration.
- No credentials or raw terminal output are written to the manifest or journal.
- Browser OPFS eviction is documented as a limitation and does not corrupt native state.
- Committed-state loss is zero in the defined test matrix.

## Out of scope

- Cloud sync and encrypted multi-device replication.
- CRDTs or collaborative editing.
- Multi-user ownership and permissions.
- S3 or arbitrary remote snapshot URIs.
- Live shell process restoration across WebKit termination.
