export type MergeClass = 'lww' | 'append-log' | 'manual';

export interface FieldMetadata {
  path: string;
  merge: MergeClass;
  sinceSchemaVersion?: number;
}

export interface FieldMetadataLookup {
  mergeClass(path: string): MergeClass;
  has(path: string): boolean;
}

export class MergeMetadataRegistry implements FieldMetadataLookup {
  private readonly classes = new Map<string, MergeClass>();
  private readonly metadata: FieldMetadata[];

  constructor(metadata: readonly FieldMetadata[] = []) {
    this.metadata = metadata.map((entry) => ({ ...entry }));
    for (const entry of metadata) {
      this.classes.set(entry.path, entry.merge);
    }
  }

  mergeClass(path: string): MergeClass {
    return this.classes.get(path) ?? 'manual';
  }

  has(path: string): boolean {
    return this.classes.has(path);
  }

  get entries(): readonly FieldMetadata[] {
    return this.metadata;
  }
}

export interface LwwValue<T = unknown> {
  value: T;
  revision: number;
  deviceId: string;
}

export interface AppendLogEntry<T = unknown> {
  id: string;
  value: T;
  revision?: number;
}

export type FieldConflictReason =
  | 'manual-merge'
  | 'unclassified-field'
  | 'ambiguous-lww'
  | 'append-log-duplicate-conflict';

export interface FieldConflict {
  path: string;
  merge: MergeClass;
  reason: FieldConflictReason;
  local: unknown;
  remote: unknown;
}

export type MergeStatus = 'merged' | 'unchanged' | 'conflict';

export interface FieldMergeResult<T = unknown> {
  path: string;
  merge: MergeClass;
  status: MergeStatus;
  changed: boolean;
  value?: T;
  winner?: 'local' | 'remote';
  conflicts: FieldConflict[];
}

export type LwwWinner = 'local' | 'remote' | 'equal' | 'conflict';

export interface LwwMergeResult<T = unknown> {
  winner: LwwWinner;
  value?: LwwValue<T>;
  conflict?: FieldConflict;
}

export interface AppendLogMergeResult<T = unknown> {
  entries: AppendLogEntry<T>[];
  added: number;
  duplicates: string[];
  conflicts: FieldConflict[];
}

function normalizeValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((entry) => normalizeValue(entry));
  }
  if (value !== null && typeof value === 'object') {
    const source = value as Record<string, unknown>;
    const normalized: Record<string, unknown> = {};
    for (const key of Object.keys(source).sort()) {
      normalized[key] = normalizeValue(source[key]);
    }
    return normalized;
  }
  return value;
}

export function canonicalValue(value: unknown): string {
  return JSON.stringify(normalizeValue(value));
}

export function valuesEqual(left: unknown, right: unknown): boolean {
  return canonicalValue(left) === canonicalValue(right);
}

function compareDeviceIds(left: string, right: string): number {
  if (left === right) return 0;
  return left > right ? 1 : -1;
}

export function compareLww<T>(local: LwwValue<T>, remote: LwwValue<T>): number {
  if (local.revision !== remote.revision) {
    return local.revision - remote.revision;
  }
  return compareDeviceIds(local.deviceId, remote.deviceId);
}

export function mergeLww<T>(
  local: LwwValue<T>,
  remote: LwwValue<T>,
  path = ''
): LwwMergeResult<T> {
  const ordering = compareLww(local, remote);
  if (ordering > 0) {
    return { winner: 'local', value: local };
  }
  if (ordering < 0) {
    return { winner: 'remote', value: remote };
  }
  if (valuesEqual(local.value, remote.value)) {
    return { winner: 'equal', value: local };
  }
  return {
    winner: 'conflict',
    conflict: {
      path,
      merge: 'lww',
      reason: 'ambiguous-lww',
      local,
      remote
    }
  };
}

export function mergeAppendLog<T>(
  local: readonly AppendLogEntry<T>[],
  remote: readonly AppendLogEntry<T>[],
  path = ''
): AppendLogMergeResult<T> {
  const localIds = new Set(local.map((entry) => entry.id));
  const byId = new Map<string, AppendLogEntry<T>>();
  const duplicates: string[] = [];
  const conflicts: FieldConflict[] = [];

  const record = (entry: AppendLogEntry<T>, source: 'local' | 'remote'): void => {
    const existing = byId.get(entry.id);
    if (!existing) {
      byId.set(entry.id, { ...entry });
      return;
    }
    if (!duplicates.includes(entry.id)) {
      duplicates.push(entry.id);
    }
    if (!valuesEqual(existing.value, entry.value)) {
      if (!conflicts.some((conflict) => conflict.path === path && conflict.reason === 'append-log-duplicate-conflict' && String((conflict.local as AppendLogEntry).id) === entry.id)) {
        conflicts.push({
          path,
          merge: 'append-log',
          reason: 'append-log-duplicate-conflict',
          local: existing,
          remote: entry
        });
      }
      if (canonicalValue(entry.value) > canonicalValue(existing.value)) {
        byId.set(entry.id, { ...entry, id: entry.id });
      }
    } else if (source === 'remote') {
      return;
    }
  };

  for (const entry of local) record(entry, 'local');
  for (const entry of remote) record(entry, 'remote');

  const entries = [...byId.values()].sort((left, right) => {
    const leftRevision = left.revision ?? 0;
    const rightRevision = right.revision ?? 0;
    if (leftRevision !== rightRevision) return leftRevision - rightRevision;
    return compareDeviceIds(left.id, right.id);
  });

  let added = 0;
  for (const id of byId.keys()) {
    if (!localIds.has(id)) added += 1;
  }

  return { entries, added, duplicates, conflicts };
}

export function mergeManual<T>(
  local: T,
  remote: T,
  path: string,
  classified: boolean
): FieldMergeResult<T> {
  if (valuesEqual(local, remote)) {
    return {
      path,
      merge: 'manual',
      status: 'unchanged',
      changed: false,
      value: local,
      conflicts: []
    };
  }
  const conflict: FieldConflict = {
    path,
    merge: 'manual',
    reason: classified ? 'manual-merge' : 'unclassified-field',
    local,
    remote
  };
  return {
    path,
    merge: 'manual',
    status: 'conflict',
    changed: false,
    value: local,
    conflicts: [conflict]
  };
}

export function mergeField<T>(
  metadata: FieldMetadataLookup,
  path: string,
  local: T,
  remote: T
): FieldMergeResult<T> {
  const merge = metadata.mergeClass(path);

  if (merge === 'manual') {
    return mergeManual(local, remote, path, metadata.has(path));
  }

  if (merge === 'append-log') {
    const localEntries = (Array.isArray(local) ? local : []) as AppendLogEntry[];
    const remoteEntries = (Array.isArray(remote) ? remote : []) as AppendLogEntry[];
    const result = mergeAppendLog(localEntries, remoteEntries, path);
    return {
      path,
      merge,
      status: result.conflicts.length > 0 ? 'conflict' : result.added > 0 ? 'merged' : 'unchanged',
      changed: result.added > 0,
      value: result.entries as T,
      conflicts: result.conflicts
    };
  }

  const localLww = local as unknown as LwwValue;
  const remoteLww = remote as unknown as LwwValue;
  const result = mergeLww(localLww, remoteLww, path);

  if (result.winner === 'conflict') {
    return {
      path,
      merge,
      status: 'conflict',
      changed: false,
      value: local,
      conflicts: result.conflict ? [result.conflict] : []
    };
  }

  return {
    path,
    merge,
    status: result.winner === 'equal' ? 'unchanged' : 'merged',
    changed: result.winner === 'remote',
    value: (result.value ?? local) as T,
    ...(result.winner === 'local' || result.winner === 'remote' ? { winner: result.winner } : {}),
    conflicts: []
  };
}
