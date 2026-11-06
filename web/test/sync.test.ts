import { describe, expect, it } from 'vitest';
import {
  MergeMetadataRegistry,
  mergeAppendLog,
  mergeField,
  mergeLww
} from '../src/sync/merge';
import {
  OfflineEditQueue,
  WorkspaceSyncEngine,
  applyWorkspacePatch,
  mergeWorkspaceSnapshots
} from '../src/sync/workspace';
import type { FieldPatch, WorkspacePatch, WorkspaceSnapshot } from '../src/sync/workspace';
import {
  SYNC_ENVELOPE_VERSION,
  SyncEnvelopeError,
  SyncKeyError,
  base64ToBytes,
  bytesToBase64,
  decodeSyncPlaintext,
  decryptSyncEnvelope,
  deriveWorkspaceSyncKey,
  encryptSyncEnvelope,
  importWorkspaceSyncKey
} from '../src/sync/envelope';

const metadata = [
  { path: 'layout.bounds', merge: 'lww' as const },
  { path: 'history', merge: 'append-log' as const },
  { path: 'identity.name', merge: 'manual' as const }
];

const registry = new MergeMetadataRegistry(metadata);

function snapshot(overrides: Partial<WorkspaceSnapshot> = {}): WorkspaceSnapshot {
  return {
    workspaceId: 'ws-1',
    hostEpoch: 2,
    workspaceSeq: 10,
    revision: 3,
    metadata: metadata.map((entry) => ({ ...entry })),
    fields: {},
    ...overrides
  };
}

function workspacePatch(overrides: Partial<WorkspacePatch> = {}): WorkspacePatch {
  return {
    workspaceId: 'ws-1',
    senderDeviceId: 'dev-a',
    hostEpoch: 2,
    baseWorkspaceSeq: 10,
    revision: 4,
    fields: [],
    ...overrides
  };
}

function field(overrides: Partial<FieldPatch> = {}): FieldPatch {
  return {
    path: 'layout.bounds',
    value: { x: 2, y: 3 },
    revision: 4,
    deviceId: 'dev-a',
    ...overrides
  };
}

describe('sync merge metadata', () => {
  it('defaults unknown fields to manual and refuses to auto-merge them', () => {
    expect(registry.mergeClass('unclassified.value')).toBe('manual');
    expect(registry.has('unclassified.value')).toBe(false);

    const result = mergeField(registry, 'unclassified.value', { enabled: true }, { enabled: false });

    expect(result.merge).toBe('manual');
    expect(result.status).toBe('conflict');
    expect(result.conflicts[0]?.reason).toBe('unclassified-field');
  });

  it('uses revision first and device id as the stable LWW tie-break', () => {
    const higherRevision = mergeLww(
      { value: 'old', revision: 4, deviceId: 'dev-z' },
      { value: 'new', revision: 5, deviceId: 'dev-a' }
    );
    expect(higherRevision.winner).toBe('remote');
    expect(higherRevision.value?.value).toBe('new');

    const equalRevision = mergeLww(
      { value: 'from-a', revision: 8, deviceId: 'dev-a' },
      { value: 'from-b', revision: 8, deviceId: 'dev-b' }
    );
    expect(equalRevision.winner).toBe('remote');
    expect(equalRevision.value?.deviceId).toBe('dev-b');

    const ambiguous = mergeLww(
      { value: 'one', revision: 8, deviceId: 'dev-a' },
      { value: 'two', revision: 8, deviceId: 'dev-a' }
    );
    expect(ambiguous.winner).toBe('conflict');
    expect(ambiguous.conflict?.reason).toBe('ambiguous-lww');
  });

  it('deduplicates append-log entries and orders them deterministically', () => {
    const result = mergeAppendLog(
      [
        { id: 'a', value: { text: 'first' }, revision: 2 },
        { id: 'b', value: { text: 'second' }, revision: 1 }
      ],
      [
        { id: 'b', value: { text: 'second' }, revision: 1 },
        { id: 'c', value: { text: 'third' }, revision: 1 }
      ],
      'history'
    );

    expect(result.entries.map((entry) => entry.id)).toEqual(['b', 'c', 'a']);
    expect(result.duplicates).toEqual(['b']);
    expect(result.added).toBe(1);
    expect(result.conflicts).toEqual([]);
  });

  it('reports conflicting append-log entries with the same id', () => {
    const result = mergeAppendLog(
      [{ id: 'same', value: 'local' }],
      [{ id: 'same', value: 'remote' }],
      'history'
    );

    expect(result.duplicates).toEqual(['same']);
    expect(result.conflicts[0]?.reason).toBe('append-log-duplicate-conflict');
  });

  it('treats manual fields as explicit conflicts when values differ', () => {
    const equal = mergeField(registry, 'identity.name', 'Ada', 'Ada');
    expect(equal.status).toBe('unchanged');

    const conflict = mergeField(registry, 'identity.name', 'Ada', 'Grace');
    expect(conflict.status).toBe('conflict');
    expect(conflict.conflicts[0]?.reason).toBe('manual-merge');
  });
});

describe('workspace snapshot and patch synchronization', () => {
  it('applies lww, append-log and classified manual fields atomically', () => {
    const base = snapshot({
      fields: {
        'layout.bounds': { value: { x: 1, y: 1 }, revision: 3, deviceId: 'dev-a' },
        history: [{ id: 'h1', value: 'opened', revision: 1 }]
      }
    });
    const patch = workspacePatch({
      fields: [
        field({ value: { x: 5, y: 6 }, revision: 4, deviceId: 'dev-b' }),
        field({ path: 'history', value: 'resized', revision: 4, appendId: 'h2' }),
        field({ path: 'identity.name', value: 'Ada', revision: 4 })
      ]
    });

    const result = applyWorkspacePatch(base, patch);

    expect(result.status).toBe('applied');
    expect(result.conflicts).toEqual([]);
    expect(result.snapshot.workspaceSeq).toBe(11);
    expect(result.snapshot.revision).toBe(4);
    expect(result.snapshot.fields['layout.bounds']).toMatchObject({
      value: { x: 5, y: 6 },
      revision: 4,
      deviceId: 'dev-b'
    });
    expect(result.snapshot.fields.history).toHaveLength(2);
    expect(result.snapshot.fields['identity.name']).toBe('Ada');
  });

  it('rejects stale, replayed, future and wrong-epoch patches explicitly', () => {
    const base = snapshot();
    const stale = applyWorkspacePatch(base, workspacePatch({ baseWorkspaceSeq: 9 }));
    expect(stale.status).toBe('rejected');
    expect(stale.reason).toBe('stale-seq');

    const future = applyWorkspacePatch(base, workspacePatch({ baseWorkspaceSeq: 11 }));
    expect(future.status).toBe('rejected');
    expect(future.reason).toBe('future-seq');

    const replayed = applyWorkspacePatch(
      snapshot({ workspaceSeq: 11 }),
      workspacePatch({ baseWorkspaceSeq: 10, fields: [field()] })
    );
    expect(replayed.status).toBe('rejected');
    expect(replayed.reason).toBe('stale-seq');

    const wrongWorkspace = applyWorkspacePatch(
      base,
      workspacePatch({ workspaceId: 'ws-2', fields: [field()] })
    );
    expect(wrongWorkspace.reason).toBe('workspace-mismatch');

    const staleEpoch = applyWorkspacePatch(base, workspacePatch({ hostEpoch: 1 }));
    expect(staleEpoch.reason).toBe('stale-epoch');

    const staleRevision = applyWorkspacePatch(
      base,
      workspacePatch({ revision: 2, fields: [field()] })
    );
    expect(staleRevision.reason).toBe('stale-revision');
  });

  it('returns a manual conflict instead of silently applying concurrent edits', () => {
    const base = snapshot({
      fields: { 'identity.name': 'Ada' }
    });
    const result = applyWorkspacePatch(
      base,
      workspacePatch({
        fields: [field({ path: 'identity.name', value: 'Grace' })]
      })
    );

    expect(result.status).toBe('conflict');
    expect(result.snapshot).toEqual(base);
    expect(result.conflicts[0]?.path).toBe('identity.name');
  });

  it('merges concurrent snapshots deterministically by field class', () => {
    const local = snapshot({
      fields: {
        'layout.bounds': { value: { x: 1 }, revision: 4, deviceId: 'dev-a' },
        history: [{ id: 'h1', value: 'local', revision: 1 }]
      }
    });
    const remote = snapshot({
      fields: {
        'layout.bounds': { value: { x: 2 }, revision: 4, deviceId: 'dev-b' },
        history: [
          { id: 'h1', value: 'local', revision: 1 },
          { id: 'h2', value: 'remote', revision: 2 }
        ]
      }
    });

    const result = mergeWorkspaceSnapshots(local, remote);

    expect(result.status).toBe('applied');
    expect(result.snapshot.workspaceSeq).toBe(11);
    expect(result.snapshot.fields['layout.bounds']).toMatchObject({
      value: { x: 2 },
      deviceId: 'dev-b'
    });
    expect(result.snapshot.fields.history).toHaveLength(2);
  });

  it('queues offline edits and stops replay at the first explicit conflict', () => {
    const engine = new WorkspaceSyncEngine(
      snapshot({
        fields: {
          'layout.bounds': { value: { x: 0 }, revision: 3, deviceId: 'dev-a' }
        }
      })
    );
    const queue = new OfflineEditQueue();
    queue.enqueue(field({ value: { x: 1 }, revision: 5 }));
    queue.enqueue(field({ path: 'history', value: 'offline-1', revision: 5, appendId: 'h1' }));

    const apply = (edit: FieldPatch) =>
      engine.apply(
        workspacePatch({
          baseWorkspaceSeq: engine.snapshot.workspaceSeq,
          revision: engine.snapshot.revision + 1,
          fields: [edit]
        })
      );

    const drained = queue.drain(apply);
    expect(drained.remaining).toEqual([]);
    expect(drained.applied).toHaveLength(2);
    expect(queue.size).toBe(0);
    expect(engine.snapshot.fields.history).toHaveLength(1);

    const blocking = new OfflineEditQueue();
    blocking.enqueue(field({ path: 'unknown.field', value: 'remote', revision: 9 }));
    const blocked = blocking.drain(apply);
    expect(blocked.haltedBy?.status).toBe('conflict');
    expect(blocked.remaining).toHaveLength(1);
    expect(blocking.size).toBe(1);
  });

  it('preserves committed state when an apply is interrupted and recovers it', () => {
    const initial = snapshot({
      fields: {
        'layout.bounds': { value: { x: 0 }, revision: 3, deviceId: 'dev-a' }
      }
    });
    const engine = new WorkspaceSyncEngine(initial);
    const interrupted = engine.apply(
      workspacePatch({
        fields: [
          field({ value: { x: 1 }, revision: 4 }),
          field({ path: 'history', value: 'late', revision: 4, appendId: 'h1' })
        ]
      }),
      {
        afterField: () => {
          throw new Error('simulated interruption');
        }
      }
    );

    expect(interrupted.status).toBe('rejected');
    expect(interrupted.reason).toBe('interrupted');
    expect(engine.snapshot).toEqual(initial);
    expect(engine.recover()).toEqual(initial);

    const recovered = engine.apply(
      workspacePatch({
        fields: [field({ value: { x: 7 }, revision: 4 })]
      })
    );
    expect(recovered.status).toBe('applied');
    expect(engine.recover().workspaceSeq).toBe(11);
  });
});

async function syncKey(): Promise<CryptoKey> {
  return importWorkspaceSyncKey(crypto.getRandomValues(new Uint8Array(32)));
}

describe('encrypted sync envelopes', () => {
  it('round-trips a versioned AES-GCM envelope with authenticated metadata', async () => {
    const key = await syncKey();
    const envelope = await encryptSyncEnvelope({
      key,
      workspaceId: 'ws-1',
      senderDeviceId: 'dev-a',
      hostEpoch: 2,
      syncSeq: 7,
      plaintext: 'workspace patch payload',
      aad: 'patch-v1'
    });

    expect(envelope.version).toBe(SYNC_ENVELOPE_VERSION);
    expect(envelope.nonce).not.toBe('');

    const decrypted = await decryptSyncEnvelope({
      key,
      envelope,
      expected: {
        workspaceId: 'ws-1',
        hostEpoch: 2,
        senderDeviceId: 'dev-a',
        lastSyncSeq: 6
      }
    });

    expect(decodeSyncPlaintext(decrypted.plaintext)).toBe('workspace patch payload');
  });

  it('rejects wrong workspace, epoch, sender device and revoked senders', async () => {
    const key = await syncKey();
    const envelope = await encryptSyncEnvelope({
      key,
      workspaceId: 'ws-1',
      senderDeviceId: 'dev-a',
      hostEpoch: 2,
      syncSeq: 7,
      plaintext: 'payload'
    });
    const expected = { workspaceId: 'ws-1', hostEpoch: 2, senderDeviceId: 'dev-a' };

    await expect(
      decryptSyncEnvelope({ key, envelope, expected: { ...expected, workspaceId: 'ws-2' } })
    ).rejects.toMatchObject({ code: 'WorkspaceMismatch' });

    await expect(
      decryptSyncEnvelope({ key, envelope, expected: { ...expected, hostEpoch: 3 } })
    ).rejects.toMatchObject({ code: 'EpochMismatch' });

    await expect(
      decryptSyncEnvelope({ key, envelope, expected: { ...expected, senderDeviceId: 'dev-b' } })
    ).rejects.toMatchObject({ code: 'DeviceMismatch' });

    await expect(
      decryptSyncEnvelope({
        key,
        envelope,
        expected: { ...expected, revokedSenderDeviceIds: ['dev-a'] }
      })
    ).rejects.toMatchObject({ code: 'SenderRevoked' });
  });

  it('rejects replayed sequences, truncated ciphertext and tampered metadata', async () => {
    const key = await syncKey();
    const envelope = await encryptSyncEnvelope({
      key,
      workspaceId: 'ws-1',
      senderDeviceId: 'dev-a',
      hostEpoch: 2,
      syncSeq: 7,
      plaintext: 'payload'
    });
    const expected = { workspaceId: 'ws-1', hostEpoch: 2 };

    await expect(
      decryptSyncEnvelope({ key, envelope, expected: { ...expected, lastSyncSeq: 7 } })
    ).rejects.toMatchObject({ code: 'StaleSequence' });

    const truncated = {
      ...envelope,
      ciphertext: bytesToBase64(base64ToBytes(envelope.ciphertext).slice(0, 8))
    };
    expect(() => base64ToBytes(envelope.ciphertext)).not.toThrow();
    await expect(
      decryptSyncEnvelope({ key, envelope: truncated, expected })
    ).rejects.toMatchObject({ code: 'TruncatedCiphertext' });

    const tampered = { ...envelope, syncSeq: 8 };
    await expect(
      decryptSyncEnvelope({ key, envelope: tampered, expected })
    ).rejects.toMatchObject({ code: 'AuthenticationFailed' });

    const flipped = base64ToBytes(envelope.ciphertext);
    flipped[flipped.length - 1] = (flipped[flipped.length - 1] ?? 0) ^ 0xff;
    await expect(
      decryptSyncEnvelope({
        key,
        envelope: { ...envelope, ciphertext: bytesToBase64(flipped) },
        expected
      })
    ).rejects.toMatchObject({ code: 'AuthenticationFailed' });
  });

  it('derives workspace-scoped keys and validates key material', async () => {
    const secret = crypto.getRandomValues(new Uint8Array(32));
    const workspaceKey = await deriveWorkspaceSyncKey(secret, 'ws-1');
    const envelope = await encryptSyncEnvelope({
      key: workspaceKey,
      workspaceId: 'ws-1',
      senderDeviceId: 'dev-a',
      hostEpoch: 2,
      syncSeq: 3,
      plaintext: 'derived'
    });
    const expected = { workspaceId: 'ws-1', hostEpoch: 2 };

    await expect(decryptSyncEnvelope({ key: workspaceKey, envelope, expected })).resolves.toBeTruthy();

    const otherWorkspaceKey = await deriveWorkspaceSyncKey(secret, 'ws-2');
    await expect(
      decryptSyncEnvelope({ key: otherWorkspaceKey, envelope, expected })
    ).rejects.toMatchObject({ code: 'AuthenticationFailed' });

    await expect(importWorkspaceSyncKey(new Uint8Array(16))).rejects.toBeInstanceOf(SyncKeyError);
    expect(new SyncEnvelopeError('InvalidEnvelope', 'bad').message).toContain('InvalidEnvelope');
  });
});
