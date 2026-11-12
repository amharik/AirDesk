import { describe, expect, it } from 'vitest';
import {
  WindowProjectionRegistry,
  type WindowProjectionIdentity,
  type WindowProjectionTarget
} from '../src/remote/window-projection';

const identity: WindowProjectionIdentity = {
  windowId: 'window-editor',
  workspaceId: 'workspace-alpha',
  title: 'Editor',
  hostSessionId: 'session-host',
  generation: 1
};

const castTarget: WindowProjectionTarget = {
  targetId: 'cast-studio',
  kind: 'cast',
  displaySessionId: 'display-cast'
};

function registry(): WindowProjectionRegistry {
  let now = 1_000;
  return new WindowProjectionRegistry(() => {
    now += 10;
    return now;
  });
}

function begin(registry: WindowProjectionRegistry, target = castTarget): void {
  const result = registry.begin(identity, target);
  expect(result.ok).toBe(true);
}

describe('remote window projection', () => {
  it('keeps compute on the host and records surface revisions', () => {
    const projections = registry();
    begin(projections);

    const started = projections.get(identity.windowId);
    expect(started?.state).toBe('projecting');
    expect(started?.computeLocation).toBe('host');
    expect(started?.surfaceRevision).toBe(0);

    const surface = projections.acknowledgeSurface(identity.windowId, 4);
    expect(surface.ok).toBe(true);
    if (surface.ok) expect(surface.projection.surfaceRevision).toBe(4);
  });

  it('restores the same window identity after reconnect to a new target', () => {
    const projections = registry();
    begin(projections);
    projections.acknowledgeSurface(identity.windowId, 2);

    const disconnected = projections.disconnect(identity.windowId, 'network');
    expect(disconnected.ok).toBe(true);
    if (disconnected.ok) {
      expect(disconnected.projection.state).toBe('reconnecting');
      expect(disconnected.projection.identity.windowId).toBe(identity.windowId);
      expect(disconnected.projection.surfaceRevision).toBe(2);
    }

    const browserTarget: WindowProjectionTarget = {
      targetId: 'browser-laptop',
      kind: 'browser',
      displaySessionId: 'display-browser'
    };
    const resumed = projections.resume(identity.windowId, browserTarget, 2);
    expect(resumed.ok).toBe(true);
    if (!resumed.ok) return;
    expect(resumed.projection.state).toBe('restored');
    expect(resumed.projection.identity).toEqual({ ...identity, generation: 2 });
    expect(resumed.projection.target).toEqual(browserTarget);
    expect(resumed.projection.computeLocation).toBe('host');
    expect(projections.get(identity.windowId)?.surfaceRevision).toBe(2);
  });

  it('rejects duplicate windows and target conflicts', () => {
    const projections = registry();
    begin(projections);

    const duplicate = projections.begin(identity, {
      targetId: 'android-phone',
      kind: 'android',
      displaySessionId: 'display-android'
    });
    expect(duplicate.ok).toBe(false);
    if (!duplicate.ok) expect(duplicate.code).toBe('duplicate-window');

    const conflict = projections.begin(
      { ...identity, windowId: 'window-terminal' },
      castTarget
    );
    expect(conflict.ok).toBe(false);
    if (!conflict.ok) expect(conflict.code).toBe('target-conflict');
  });

  it('rejects stale generations and stale surface revisions', () => {
    const projections = registry();
    begin(projections);
    expect(projections.acknowledgeSurface(identity.windowId, 5).ok).toBe(true);

    const staleSurface = projections.acknowledgeSurface(identity.windowId, 5);
    expect(staleSurface.ok).toBe(false);
    if (!staleSurface.ok) expect(staleSurface.code).toBe('stale-revision');

    projections.disconnect(identity.windowId, 'network');
    const staleGeneration = projections.resume(identity.windowId, castTarget, 0);
    expect(staleGeneration.ok).toBe(false);
    if (!staleGeneration.ok) expect(staleGeneration.code).toBe('stale-generation');
  });

  it('rejects invalid identities and states, and releases the target', () => {
    const projections = registry();
    const invalid = projections.begin({ ...identity, windowId: 'bad id' }, castTarget);
    expect(invalid.ok).toBe(false);
    if (!invalid.ok) expect(invalid.code).toBe('invalid-identity');

    begin(projections);
    const illegal = projections.resume(identity.windowId, castTarget, 2);
    expect(illegal.ok).toBe(false);
    if (!illegal.ok) expect(illegal.code).toBe('illegal-state');

    const released = projections.release(identity.windowId);
    expect(released.ok).toBe(true);
    if (released.ok) expect(released.projection.state).toBe('released');
    expect(projections.list()).toEqual([]);

    const reused = projections.begin(identity, castTarget);
    expect(reused.ok).toBe(true);
  });
});
