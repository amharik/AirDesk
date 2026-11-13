import type { WorkspaceSyncCoreBridge } from './core';
import {
  MergeMetadataRegistry,
  mergeAppendLog,
  mergeField,
  type AppendLogEntry,
  type FieldConflict,
  type FieldMergeResult,
  type FieldMetadata,
  type MergeClass
} from './merge';
import { mergeWorkspaceSnapshotsWithCore } from './core';

export interface WorkspaceSnapshot {
  workspaceId: string;
  hostEpoch: number;
  workspaceSeq: number;
  revision: number;
  fields: Record<string, unknown>;
  metadata: FieldMetadata[];
}

export interface FieldPatch {
  path: string;
  value: unknown;
  revision: number;
  deviceId: string;
  appendId?: string;
}

export interface WorkspacePatch {
  workspaceId: string;
  senderDeviceId: string;
  hostEpoch: number;
  baseWorkspaceSeq: number;
  revision: number;
  fields: FieldPatch[];
}

export type WorkspaceRejectReason =
  | 'workspace-mismatch'
  | 'stale-epoch'
  | 'future-epoch'
  | 'stale-seq'
  | 'future-seq'
  | 'stale-revision'
  | 'invalid-patch'
  | 'interrupted';

export interface WorkspaceApplyHooks {
  afterField?: (path: string) => void;
}

export interface ApplyWorkspaceResult {
  status: 'applied' | 'unchanged' | 'conflict' | 'rejected';
  snapshot: WorkspaceSnapshot;
  fieldResults: FieldMergeResult[];
  conflicts: FieldConflict[];
  reason?: WorkspaceRejectReason;
}

export interface MergeWorkspaceResult {
  status: 'applied' | 'unchanged' | 'conflict' | 'rejected';
  snapshot: WorkspaceSnapshot;
  fieldResults: FieldMergeResult[];
  conflicts: FieldConflict[];
  reason?: 'workspace-mismatch' | 'stale-epoch' | 'future-epoch' | 'interrupted';
}

export class WorkspaceSyncError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'WorkspaceSyncError';
    this.code = code;
  }
}

function cloneSnapshot(snapshot: WorkspaceSnapshot): WorkspaceSnapshot {
  return {
    workspaceId: snapshot.workspaceId,
    hostEpoch: snapshot.hostEpoch,
    workspaceSeq: snapshot.workspaceSeq,
    revision: snapshot.revision,
    fields: { ...snapshot.fields },
    metadata: snapshot.metadata.map((entry) => ({ ...entry }))
  };
}

function combinedMetadata(
  local: readonly FieldMetadata[],
  remote: readonly FieldMetadata[]
): FieldMetadata[] {
  const entries = new Map<string, FieldMetadata>();
  for (const entry of remote) entries.set(entry.path, { ...entry });
  for (const entry of local) entries.set(entry.path, { ...entry });
  return [...entries.values()];
}

function valueForClass(
  merge: MergeClass,
  patch: FieldPatch,
  path: string
): unknown {
  if (merge === 'lww') {
    return { value: patch.value, revision: patch.revision, deviceId: patch.deviceId };
  }
  if (merge === 'append-log') {
    if (Array.isArray(patch.value)) {
      return patch.value;
    }
    return [
      {
        id: patch.appendId ?? `${patch.deviceId}:${patch.revision}:${path}`,
        value: patch.value,
        revision: patch.revision
      }
    ];
  }
  return patch.value;
}

function mergeNewField(
  registry: MergeMetadataRegistry,
  patch: FieldPatch
): FieldMergeResult {
  const merge = registry.mergeClass(patch.path);
  const value = valueForClass(merge, patch, patch.path);

  if (merge === 'manual' && !registry.has(patch.path)) {
    return {
      path: patch.path,
      merge,
      status: 'conflict',
      changed: false,
      value: undefined,
      conflicts: [
        {
          path: patch.path,
          merge,
          reason: 'unclassified-field',
          local: undefined,
          remote: value
        }
      ]
    };
  }

  if (merge === 'append-log') {
    const entries = (Array.isArray(value) ? value : []) as AppendLogEntry[];
    const result = mergeAppendLog([], entries, patch.path);
    return {
      path: patch.path,
      merge,
      status: result.conflicts.length > 0 ? 'conflict' : 'merged',
      changed: result.entries.length > 0,
      value: result.entries,
      conflicts: result.conflicts
    };
  }

  return {
    path: patch.path,
    merge,
    status: 'merged',
    changed: true,
    value,
    conflicts: []
  };
}

function mergeExistingField(
  registry: MergeMetadataRegistry,
  patch: FieldPatch,
  local: unknown
): FieldMergeResult {
  const merge = registry.mergeClass(patch.path);
  const remote = valueForClass(merge, patch, patch.path);
  return mergeField(registry, patch.path, local, remote);
}

function rejected(
  snapshot: WorkspaceSnapshot,
  reason: WorkspaceRejectReason,
  fieldResults: FieldMergeResult[] = []
): ApplyWorkspaceResult {
  return {
    status: 'rejected',
    snapshot,
    fieldResults,
    conflicts: fieldResults.flatMap((result) => result.conflicts),
    reason
  };
}

export function applyWorkspacePatch(
  snapshot: WorkspaceSnapshot,
  patch: WorkspacePatch,
  hooks: WorkspaceApplyHooks = {}
): ApplyWorkspaceResult {
  if (patch.workspaceId !== snapshot.workspaceId) {
    return rejected(snapshot, 'workspace-mismatch');
  }
  if (patch.hostEpoch < snapshot.hostEpoch) {
    return rejected(snapshot, 'stale-epoch');
  }
  if (patch.hostEpoch > snapshot.hostEpoch) {
    return rejected(snapshot, 'future-epoch');
  }
  if (patch.baseWorkspaceSeq < snapshot.workspaceSeq) {
    return rejected(snapshot, 'stale-seq');
  }
  if (patch.baseWorkspaceSeq > snapshot.workspaceSeq) {
    return rejected(snapshot, 'future-seq');
  }
  if (patch.revision < snapshot.revision) {
    return rejected(snapshot, 'stale-revision');
  }

  const registry = new MergeMetadataRegistry(snapshot.metadata);
  const nextFields = { ...snapshot.fields };
  const fieldResults: FieldMergeResult[] = [];

  try {
    for (const field of patch.fields) {
      if (!field.path || !Number.isFinite(field.revision) || field.revision < 0) {
        return rejected(snapshot, 'invalid-patch', fieldResults);
      }
      const hasLocal = Object.prototype.hasOwnProperty.call(nextFields, field.path);
      const result = hasLocal
        ? mergeExistingField(registry, field, nextFields[field.path])
        : mergeNewField(registry, field);
      fieldResults.push(result);
      if (result.value !== undefined || result.status === 'merged') {
        nextFields[field.path] = result.value;
      }
      hooks.afterField?.(field.path);
    }
  } catch {
    return rejected(snapshot, 'interrupted', fieldResults);
  }

  const conflicts = fieldResults.flatMap((result) => result.conflicts);
  if (conflicts.length > 0) {
    return {
      status: 'conflict',
      snapshot,
      fieldResults,
      conflicts
    };
  }

  const changed = fieldResults.some((result) => result.changed);
  if (!changed) {
    return {
      status: 'unchanged',
      snapshot,
      fieldResults,
      conflicts: []
    };
  }

  return {
    status: 'applied',
    snapshot: {
      ...snapshot,
      workspaceSeq: snapshot.workspaceSeq + 1,
      revision: Math.max(snapshot.revision + 1, patch.revision),
      fields: nextFields
    },
    fieldResults,
    conflicts: []
  };
}

export function mergeWorkspaceSnapshots(
  local: WorkspaceSnapshot,
  remote: WorkspaceSnapshot,
  hooks: WorkspaceApplyHooks = {},
  core: WorkspaceSyncCoreBridge | null = null
): MergeWorkspaceResult {
  if (core && !hooks.afterField) {
    try {
      return mergeWorkspaceSnapshotsWithCore(local, remote, core);
    } catch {
      // Fall back to the native merge when the binding rejects the payload.
    }
  }

  if (local.workspaceId !== remote.workspaceId) {
    return {
      status: 'rejected',
      snapshot: local,
      fieldResults: [],
      conflicts: [],
      reason: 'workspace-mismatch'
    };
  }
  if (remote.hostEpoch < local.hostEpoch) {
    return {
      status: 'rejected',
      snapshot: local,
      fieldResults: [],
      conflicts: [],
      reason: 'stale-epoch'
    };
  }
  if (remote.hostEpoch > local.hostEpoch) {
    return {
      status: 'rejected',
      snapshot: local,
      fieldResults: [],
      conflicts: [],
      reason: 'future-epoch'
    };
  }

  const metadata = combinedMetadata(local.metadata, remote.metadata);
  const registry = new MergeMetadataRegistry(metadata);
  const fields = { ...local.fields };
  const paths = new Set([...Object.keys(local.fields), ...Object.keys(remote.fields)]);
  const fieldResults: FieldMergeResult[] = [];

  try {
    for (const path of [...paths].sort()) {
      const hasLocal = Object.prototype.hasOwnProperty.call(local.fields, path);
      const hasRemote = Object.prototype.hasOwnProperty.call(remote.fields, path);
      const merge = registry.mergeClass(path);

      let result: FieldMergeResult;
      if (!hasLocal && hasRemote) {
        const remoteValue = remote.fields[path];
        if (merge === 'manual' && !registry.has(path)) {
          result = {
            path,
            merge,
            status: 'conflict',
            changed: false,
            value: undefined,
            conflicts: [
              {
                path,
                merge,
                reason: 'unclassified-field',
                local: undefined,
                remote: remoteValue
              }
            ]
          };
        } else if (merge === 'append-log') {
          const entries = (Array.isArray(remoteValue) ? remoteValue : []) as AppendLogEntry[];
          const merged = mergeAppendLog([], entries, path);
          result = {
            path,
            merge,
            status: merged.conflicts.length > 0 ? 'conflict' : 'merged',
            changed: merged.entries.length > 0,
            value: merged.entries,
            conflicts: merged.conflicts
          };
        } else {
          result = {
            path,
            merge,
            status: 'merged',
            changed: true,
            value: remoteValue,
            conflicts: []
          };
        }
      } else if (hasLocal && !hasRemote) {
        result = {
          path,
          merge,
          status: 'unchanged',
          changed: false,
          value: local.fields[path],
          conflicts: []
        };
      } else {
        result = mergeField(registry, path, local.fields[path], remote.fields[path]);
      }

      fieldResults.push(result);
      if (result.value !== undefined || result.status === 'merged') {
        fields[path] = result.value;
      }
      hooks.afterField?.(path);
    }
  } catch {
    return {
      status: 'rejected',
      snapshot: local,
      fieldResults,
      conflicts: [],
      reason: 'interrupted'
    };
  }

  const conflicts = fieldResults.flatMap((result) => result.conflicts);
  if (conflicts.length > 0) {
    return {
      status: 'conflict',
      snapshot: local,
      fieldResults,
      conflicts
    };
  }

  const changed = fieldResults.some((result) => result.changed);
  if (!changed) {
    return {
      status: 'unchanged',
      snapshot: local,
      fieldResults,
      conflicts: []
    };
  }

  return {
    status: 'applied',
    snapshot: {
      ...local,
      workspaceSeq: Math.max(local.workspaceSeq, remote.workspaceSeq) + 1,
      revision: Math.max(local.revision, remote.revision) + 1,
      fields,
      metadata
    },
    fieldResults,
    conflicts: []
  };
}

export interface OfflineDrainResult {
  applied: FieldPatch[];
  haltedBy?: ApplyWorkspaceResult;
  remaining: readonly FieldPatch[];
}

export class OfflineEditQueue {
  private edits: FieldPatch[] = [];

  enqueue(edit: FieldPatch): void {
    this.edits.push({ ...edit });
  }

  get size(): number {
    return this.edits.length;
  }

  entries(): readonly FieldPatch[] {
    return this.edits.map((edit) => ({ ...edit }));
  }

  clear(): void {
    this.edits = [];
  }

  drain(apply: (edit: FieldPatch) => ApplyWorkspaceResult): OfflineDrainResult {
    const applied: FieldPatch[] = [];
    for (let index = 0; index < this.edits.length; index += 1) {
      const edit = this.edits[index];
      if (!edit) break;
      const result = apply(edit);
      if (result.status === 'applied' || result.status === 'unchanged') {
        applied.push(edit);
        continue;
      }
      this.edits = this.edits.slice(index);
      return {
        applied,
        haltedBy: result,
        remaining: this.entries()
      };
    }
    this.edits = [];
    return { applied, remaining: [] };
  }
}

export class WorkspaceSyncEngine {
  private current: WorkspaceSnapshot;
  private committed: WorkspaceSnapshot;

  constructor(initial: WorkspaceSnapshot) {
    this.current = cloneSnapshot(initial);
    this.committed = cloneSnapshot(initial);
  }

  get snapshot(): WorkspaceSnapshot {
    return cloneSnapshot(this.current);
  }

  apply(patch: WorkspacePatch, hooks: WorkspaceApplyHooks = {}): ApplyWorkspaceResult {
    const result = applyWorkspacePatch(this.current, patch, hooks);
    if (result.status === 'applied' || result.status === 'unchanged') {
      this.current = cloneSnapshot(result.snapshot);
      this.committed = cloneSnapshot(result.snapshot);
    }
    return result;
  }

  recover(): WorkspaceSnapshot {
    return cloneSnapshot(this.committed);
  }
}
