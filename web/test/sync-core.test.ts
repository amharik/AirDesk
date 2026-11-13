import { describe, expect, it } from 'vitest';
import { mergeWorkspaceSnapshotsWithCore } from '../src/sync/core';
import { mergeWorkspaceSnapshots } from '../src/sync/workspace';
import type { WorkspaceSnapshot } from '../src/sync/workspace';

function snapshot(overrides: Partial<WorkspaceSnapshot> = {}): WorkspaceSnapshot {
  return {
    workspaceId: 'ws-1',
    hostEpoch: 3,
    workspaceSeq: 4,
    revision: 4,
    fields: {},
    metadata: [
      { path: 'layout.bounds', merge: 'lww', sinceSchemaVersion: 1 }
    ],
    ...overrides
  };
}

describe('core workspace sync bridge', () => {
  it('round-trips snapshots through the JSON bridge', () => {
    const local = snapshot({
      fields: {
        'layout.bounds': { value: { x: 1 }, revision: 4, deviceId: 'dev-a' }
      }
    });
    const remote = snapshot({
      fields: {
        'layout.bounds': { value: { x: 2 }, revision: 4, deviceId: 'dev-b' }
      }
    });
    const calls: Array<[string, string]> = [];

    const result = mergeWorkspaceSnapshotsWithCore(local, remote, {
      mergeSnapshots(localJson: string, remoteJson: string) {
        calls.push([localJson, remoteJson]);
        return JSON.stringify({
          status: 'applied',
          snapshot: remote,
          fieldResults: [],
          conflicts: []
        });
      }
    });

    expect(calls).toHaveLength(1);
    expect(JSON.parse(calls[0]![0])).toMatchObject({ workspaceId: 'ws-1' });
    expect(JSON.parse(calls[0]![1])).toMatchObject({ workspaceId: 'ws-1' });
    expect(result.status).toBe('applied');
    expect(result.snapshot.fields['layout.bounds']).toMatchObject({ deviceId: 'dev-b' });
  });

  it('falls back to native when the binding throws', () => {
    const local = snapshot({
      fields: {
        'layout.bounds': { value: { x: 1 }, revision: 4, deviceId: 'dev-a' }
      }
    });
    const remote = snapshot({
      fields: {
        'layout.bounds': { value: { x: 2 }, revision: 4, deviceId: 'dev-b' }
      }
    });

    const result = mergeWorkspaceSnapshots(local, remote, {}, {
      mergeSnapshots() {
        throw new Error('binding unavailable');
      }
    });

    expect(result.status).toBe('applied');
    expect(result.snapshot.fields['layout.bounds']).toMatchObject({ deviceId: 'dev-b' });
  });
});
