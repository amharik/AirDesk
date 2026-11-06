import {
  MergeMetadataRegistry,
  mergeAppendLog,
  mergeField,
  mergeLww,
  type AppendLogEntry,
  type FieldConflict,
  type FieldConflictReason,
  type FieldMetadata,
  type LwwValue,
  type LwwWinner,
  type MergeClass,
  type MergeStatus
} from '../../src/sync/merge';
import {
  OfflineEditQueue,
  WorkspaceSyncEngine,
  applyWorkspacePatch,
  mergeWorkspaceSnapshots,
  type ApplyWorkspaceResult,
  type FieldPatch,
  type MergeWorkspaceResult,
  type WorkspacePatch,
  type WorkspaceRejectReason,
  type WorkspaceSnapshot
} from '../../src/sync/workspace';

export interface MergeLwwOperation {
  kind: 'merge-lww';
  path?: string;
  local: LwwValue;
  remote: LwwValue;
}

export interface MergeAppendLogOperation {
  kind: 'merge-append-log';
  path?: string;
  local: AppendLogEntry[];
  remote: AppendLogEntry[];
}

export interface MergeFieldOperation {
  kind: 'merge-field';
  metadata: FieldMetadata[];
  path: string;
  local: unknown;
  remote: unknown;
}

export interface ApplyPatchOperation {
  kind: 'apply-patch';
  snapshot: WorkspaceSnapshot;
  patch: WorkspacePatch;
  interruptAfterField?: number;
}

export interface MergeSnapshotsOperation {
  kind: 'merge-snapshots';
  local: WorkspaceSnapshot;
  remote: WorkspaceSnapshot;
  interruptAfterField?: number;
}

export interface OfflineDrainOperation {
  kind: 'offline-drain';
  initial: WorkspaceSnapshot;
  edits: FieldPatch[];
  serverPatches?: WorkspacePatch[];
  rebase?: boolean;
  baseWorkspaceSeq?: number;
  patchRevision?: number;
}

export type CorpusOperation =
  | MergeLwwOperation
  | MergeAppendLogOperation
  | MergeFieldOperation
  | ApplyPatchOperation
  | MergeSnapshotsOperation
  | OfflineDrainOperation;

export interface CorpusConflictExpectation {
  path: string;
  merge: MergeClass;
  reason: FieldConflictReason;
}

export interface CorpusHaltExpectation {
  status?: string;
  reason?: WorkspaceRejectReason;
  conflicts?: CorpusConflictExpectation[];
}

export interface CorpusExpectation {
  status?: string;
  winner?: LwwWinner;
  merge?: MergeClass;
  changed?: boolean;
  value?: unknown;
  entries?: AppendLogEntry[];
  added?: number;
  duplicates?: string[];
  conflicts?: CorpusConflictExpectation[];
  reason?: WorkspaceRejectReason;
  snapshot?: Record<string, unknown>;
  fieldStatuses?: Record<string, MergeStatus>;
  applied?: FieldPatch[];
  remaining?: FieldPatch[];
  halt?: CorpusHaltExpectation;
}

export interface CorpusFixture {
  id: string;
  description: string;
  operation: CorpusOperation;
  expected: CorpusExpectation;
}

export interface CorpusDiagnostic {
  path: string;
  expected: unknown;
  actual: unknown;
  message: string;
}

export interface CorpusCaseResult {
  id: string;
  description: string;
  kind: CorpusOperation['kind'];
  passed: boolean;
  expected: CorpusExpectation;
  actual: Record<string, unknown>;
  diagnostics: CorpusDiagnostic[];
}

export interface CorpusRunResult {
  total: number;
  passed: number;
  failed: number;
  cases: CorpusCaseResult[];
}

function conflictExpectations(conflicts: readonly FieldConflict[]): CorpusConflictExpectation[] {
  return conflicts.map((conflict) => ({
    path: conflict.path,
    merge: conflict.merge,
    reason: conflict.reason
  }));
}

function applyHooks(interruptAfterField?: number): {
  afterField?: (path: string) => void;
} {
  if (interruptAfterField === undefined) return {};
  let seen = 0;
  return {
    afterField: () => {
      seen += 1;
      if (seen >= interruptAfterField) {
        throw new Error('corpus interruption');
      }
    }
  };
}

function summarizeApply(
  result: ApplyWorkspaceResult | MergeWorkspaceResult
): Record<string, unknown> {
  return {
    status: result.status,
    ...(result.reason ? { reason: result.reason } : {}),
    snapshot: result.snapshot,
    conflicts: conflictExpectations(result.conflicts),
    fieldStatuses: Object.fromEntries(
      result.fieldResults.map((field) => [field.path, field.status])
    ),
    fieldResults: result.fieldResults.map((field) => ({
      path: field.path,
      merge: field.merge,
      status: field.status,
      changed: field.changed,
      ...(field.winner ? { winner: field.winner } : {}),
      ...(field.value !== undefined ? { value: field.value } : {}),
      conflicts: conflictExpectations(field.conflicts)
    }))
  };
}

function executeOperation(operation: CorpusOperation): Record<string, unknown> {
  switch (operation.kind) {
    case 'merge-lww': {
      const result = mergeLww(operation.local, operation.remote, operation.path ?? '');
      return {
        status: result.winner,
        winner: result.winner,
        ...(result.value !== undefined ? { value: result.value } : {}),
        conflicts: result.conflict ? conflictExpectations([result.conflict]) : []
      };
    }

    case 'merge-append-log': {
      const result = mergeAppendLog(operation.local, operation.remote, operation.path ?? '');
      return {
        status:
          result.conflicts.length > 0 ? 'conflict' : result.added > 0 ? 'merged' : 'unchanged',
        entries: result.entries,
        added: result.added,
        duplicates: result.duplicates,
        conflicts: conflictExpectations(result.conflicts)
      };
    }

    case 'merge-field': {
      const registry = new MergeMetadataRegistry(operation.metadata);
      const result = mergeField(registry, operation.path, operation.local, operation.remote);
      return {
        status: result.status,
        merge: result.merge,
        changed: result.changed,
        ...(result.value !== undefined ? { value: result.value } : {}),
        ...(result.winner ? { winner: result.winner } : {}),
        conflicts: conflictExpectations(result.conflicts)
      };
    }

    case 'apply-patch': {
      const result = applyWorkspacePatch(
        operation.snapshot,
        operation.patch,
        applyHooks(operation.interruptAfterField)
      );
      return summarizeApply(result);
    }

    case 'merge-snapshots': {
      const result = mergeWorkspaceSnapshots(
        operation.local,
        operation.remote,
        applyHooks(operation.interruptAfterField)
      );
      return summarizeApply(result);
    }

    case 'offline-drain': {
      const engine = new WorkspaceSyncEngine(operation.initial);
      for (const serverPatch of operation.serverPatches ?? []) {
        const result = engine.apply(serverPatch);
        if (result.status === 'conflict' || result.status === 'rejected') {
          throw new Error(
            `fixture server patch failed: ${result.status}${
              result.reason ? ` (${result.reason})` : ''
            }`
          );
        }
      }

      const queue = new OfflineEditQueue();
      for (const edit of operation.edits) queue.enqueue(edit);

      const rebase = operation.rebase !== false;
      const apply = (edit: FieldPatch): ApplyWorkspaceResult => {
        const current = engine.snapshot;
        return engine.apply({
          workspaceId: current.workspaceId,
          senderDeviceId: edit.deviceId,
          hostEpoch: current.hostEpoch,
          baseWorkspaceSeq: rebase
            ? current.workspaceSeq
            : (operation.baseWorkspaceSeq ?? operation.initial.workspaceSeq),
          revision: rebase
            ? current.revision + 1
            : (operation.patchRevision ?? edit.revision),
          fields: [edit]
        });
      };

      const drained = queue.drain(apply);
      return {
        status: drained.haltedBy ? 'halted' : 'drained',
        applied: drained.applied,
        remaining: drained.remaining,
        ...(drained.haltedBy ? { halt: summarizeApply(drained.haltedBy) } : {}),
        snapshot: engine.snapshot,
        queueSize: queue.size
      };
    }

    default: {
      const exhaustive: never = operation;
      throw new Error(`unsupported corpus operation: ${JSON.stringify(exhaustive)}`);
    }
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function describe(value: unknown): string {
  if (value === undefined) return '<undefined>';
  const serialized = JSON.stringify(value);
  if (serialized === undefined) return String(value);
  return serialized.length > 160 ? `${serialized.slice(0, 157)}...` : serialized;
}

function diffSubset(
  expected: unknown,
  actual: unknown,
  path: string,
  diagnostics: CorpusDiagnostic[]
): void {
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual)) {
      diagnostics.push({
        path,
        expected,
        actual,
        message: `expected an array but received ${describe(actual)}`
      });
      return;
    }
    if (expected.length !== actual.length) {
      diagnostics.push({
        path: `${path}.length`,
        expected: expected.length,
        actual: actual.length,
        message: `expected ${expected.length} entries but received ${actual.length}`
      });
    }
    const length = Math.min(expected.length, actual.length);
    for (let index = 0; index < length; index += 1) {
      diffSubset(expected[index], actual[index], `${path}[${index}]`, diagnostics);
    }
    return;
  }

  if (isRecord(expected)) {
    if (!isRecord(actual)) {
      diagnostics.push({
        path,
        expected,
        actual,
        message: `expected an object but received ${describe(actual)}`
      });
      return;
    }
    for (const key of Object.keys(expected)) {
      if (!Object.prototype.hasOwnProperty.call(actual, key)) {
        diagnostics.push({
          path: `${path}.${key}`,
          expected: expected[key],
          actual: undefined,
          message: `missing expected property ${key}`
        });
        continue;
      }
      diffSubset(expected[key], actual[key], `${path}.${key}`, diagnostics);
    }
    return;
  }

  if (!Object.is(expected, actual)) {
    diagnostics.push({
      path,
      expected,
      actual,
      message: `expected ${describe(expected)} but received ${describe(actual)}`
    });
  }
}

export function runConflictCorpus(fixtures: readonly CorpusFixture[]): CorpusRunResult {
  const cases = fixtures.map((fixture): CorpusCaseResult => {
    let actual: Record<string, unknown>;
    try {
      actual = executeOperation(fixture.operation);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        id: fixture.id,
        description: fixture.description,
        kind: fixture.operation.kind,
        passed: false,
        expected: fixture.expected,
        actual: {},
        diagnostics: [
          {
            path: '$',
            expected: 'operation to complete',
            actual: message,
            message: `operation threw: ${message}`
          }
        ]
      };
    }

    const diagnostics: CorpusDiagnostic[] = [];
    diffSubset(fixture.expected, actual, '$', diagnostics);
    return {
      id: fixture.id,
      description: fixture.description,
      kind: fixture.operation.kind,
      passed: diagnostics.length === 0,
      expected: fixture.expected,
      actual,
      diagnostics
    };
  });

  const failed = cases.filter((entry) => !entry.passed).length;
  return {
    total: cases.length,
    passed: cases.length - failed,
    failed,
    cases
  };
}

export function formatCorpusResult(result: CorpusRunResult): string {
  const lines = [
    `sync conflict corpus: ${result.passed}/${result.total} passed, ${result.failed} failed`
  ];
  for (const entry of result.cases) {
    if (entry.passed) continue;
    lines.push(`FAIL ${entry.id}: ${entry.description}`);
    for (const diagnostic of entry.diagnostics) {
      lines.push(`  ${diagnostic.path}: ${diagnostic.message}`);
    }
  }
  return lines.join('\n');
}

export function fixtureIds(fixtures: readonly CorpusFixture[]): string[] {
  return fixtures.map((fixture) => fixture.id).sort();
}
