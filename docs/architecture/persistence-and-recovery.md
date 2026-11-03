# Persistence and recovery

AirDesk is local-first. A workspace must be recoverable without cloud connectivity or cross-device synchronization.

## Persistence domains

| Domain | Scope | Examples |
| --- | --- | --- |
| Workspace | Persistent logical state | identity, manifest, layout, preferences, application definitions |
| Device | Node-local state | device keys, pairing records, capability state, local cache |
| Runtime | Provider state | runtime processes, volumes, terminal sessions |
| Session | Ephemeral presentation state | viewport, focus, controller attachment |
| Resource | External data | files, documents, databases, media |

Each domain has its own schema version and recovery behavior.

## Workspace store

The initial store should be embedded, transactional and available on supported native platforms. The logical model is:

- `WorkspaceManifest` for desired state;
- separate observed-state records;
- atomic writes with revision checks;
- schema migration with backup;
- corruption detection and explicit recovery.

Browser storage is not the canonical workspace store. Browser-local state may cache presentation and recent workspace references.

Durable flushes carry a monotonic `checkpointSeq`. Native metadata and the WebContent (OPFS/IndexedDB) store commit in two phases: prepare, then acknowledge. A WebContent relaunch replays only the journal delta after the last acknowledged `checkpointSeq`, and replay is idempotent.

## Versioning

Workspace documents carry:

- `schemaVersion`;
- `revision`;
- migration history;
- creation and update metadata.

Unknown future schema versions must be rejected rather than opened with lossy behavior.

## Recovery

Recovery reports what happened:

- restored;
- reconnected;
- restarted;
- suspended;
- unavailable;
- failed;
- lost.

Rules:

- Display reconnect must not recreate the workspace.
- Runtime crash must not erase application definitions.
- Device disconnect must not revoke workspace ownership.
- Corrupt workspace records must not be silently replaced by empty defaults.
- Recovery must not claim more than was restored.

## Merge metadata

Synchronizable fields carry `lww`, `append-log` or `manual` metadata now, even though v1 rejects concurrent writers.

- `lww`: scalar preferences and metadata.
- `append-log`: history, audit and event records.
- `manual`: identity, ownership, security, placement and structural state.

Unknown fields default to `manual`. A field without merge metadata must not be synchronized automatically. CRDTs are not the workspace merge strategy.

## Sync

Encrypted, conflict-aware synchronization is Release 4. Until then:

- the canonical workspace is device-local;
- export/import is the supported transfer path;
- no CRDT or multi-writer protocol is required;
- resource references must not be assumed reachable from another device.

Future sync must preserve workspace identity, schema versioning, merge metadata and authority boundaries. CRDTs are confined to Release 5 shared documents, not workspace desired state.
