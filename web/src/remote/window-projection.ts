export type WindowProjectionTargetKind = 'cast' | 'browser' | 'android';

export type WindowProjectionState =
  | 'projecting'
  | 'reconnecting'
  | 'restored'
  | 'released'
  | 'failed';

export type WindowProjectionFailureCode =
  | 'invalid-identity'
  | 'invalid-target'
  | 'duplicate-window'
  | 'target-conflict'
  | 'not-found'
  | 'illegal-state'
  | 'stale-generation'
  | 'stale-revision';

export interface WindowProjectionIdentity {
  windowId: string;
  workspaceId: string;
  title: string;
  hostSessionId: string;
  generation: number;
}

export interface WindowProjectionTarget {
  targetId: string;
  kind: WindowProjectionTargetKind;
  displaySessionId: string;
}

export interface WindowProjection {
  identity: WindowProjectionIdentity;
  target: WindowProjectionTarget;
  state: WindowProjectionState;
  surfaceRevision: number;
  computeLocation: 'host';
  createdAtMs: number;
  updatedAtMs: number;
  lastError?: string;
}

export interface WindowProjectionFailure {
  ok: false;
  code: WindowProjectionFailureCode;
  message: string;
}

export type WindowProjectionResult =
  | { ok: true; projection: WindowProjection }
  | WindowProjectionFailure;

const IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const TARGET_KINDS: readonly WindowProjectionTargetKind[] = ['cast', 'browser', 'android'];

function validIdentifier(value: string): boolean {
  return IDENTIFIER.test(value);
}

function validIdentity(identity: WindowProjectionIdentity): boolean {
  return (
    validIdentifier(identity.windowId) &&
    validIdentifier(identity.workspaceId) &&
    validIdentifier(identity.hostSessionId) &&
    identity.title.trim().length > 0 &&
    identity.title.length <= 256 &&
    Number.isInteger(identity.generation) &&
    identity.generation >= 0
  );
}

function validTarget(target: WindowProjectionTarget): boolean {
  return (
    TARGET_KINDS.includes(target.kind) &&
    validIdentifier(target.targetId) &&
    validIdentifier(target.displaySessionId)
  );
}

function failure(
  code: WindowProjectionFailureCode,
  message: string
): WindowProjectionFailure {
  return { ok: false, code, message };
}

function clone(projection: WindowProjection): WindowProjection {
  return {
    ...projection,
    identity: { ...projection.identity },
    target: { ...projection.target }
  };
}

export class WindowProjectionRegistry {
  private readonly projections = new Map<string, WindowProjection>();
  private readonly targets = new Map<string, string>();
  private readonly now: () => number;

  constructor(now: () => number = Date.now) {
    this.now = now;
  }

  begin(
    identity: WindowProjectionIdentity,
    target: WindowProjectionTarget
  ): WindowProjectionResult {
    if (!validIdentity(identity)) {
      return failure('invalid-identity', 'Window identity is invalid.');
    }
    if (!validTarget(target)) {
      return failure('invalid-target', 'Projection target is invalid.');
    }
    const existing = this.projections.get(identity.windowId);
    if (existing && existing.state !== 'released' && existing.state !== 'failed') {
      return failure('duplicate-window', `Window ${identity.windowId} is already projecting.`);
    }
    const owner = this.targets.get(target.displaySessionId);
    if (owner && owner !== identity.windowId) {
      return failure(
        'target-conflict',
        `Display ${target.displaySessionId} is already projecting window ${owner}.`
      );
    }

    const timestamp = this.now();
    const projection: WindowProjection = {
      identity: { ...identity },
      target: { ...target },
      state: 'projecting',
      surfaceRevision: 0,
      computeLocation: 'host',
      createdAtMs: timestamp,
      updatedAtMs: timestamp
    };
    this.projections.set(identity.windowId, projection);
    this.targets.set(target.displaySessionId, identity.windowId);
    return { ok: true, projection: clone(projection) };
  }

  acknowledgeSurface(windowId: string, revision: number): WindowProjectionResult {
    const projection = this.projections.get(windowId);
    if (!projection) {
      return failure('not-found', `Window ${windowId} is not projecting.`);
    }
    if (projection.state !== 'projecting' && projection.state !== 'restored') {
      return failure('illegal-state', `Window ${windowId} cannot accept surfaces while ${projection.state}.`);
    }
    if (!Number.isInteger(revision) || revision < 1) {
      return failure('stale-revision', 'Surface revision must be a positive integer.');
    }
    if (revision <= projection.surfaceRevision) {
      return failure(
        'stale-revision',
        `Surface revision ${revision} is not newer than ${projection.surfaceRevision}.`
      );
    }
    projection.surfaceRevision = revision;
    projection.updatedAtMs = this.now();
    return { ok: true, projection: clone(projection) };
  }

  disconnect(windowId: string, reason: string): WindowProjectionResult {
    const projection = this.projections.get(windowId);
    if (!projection) {
      return failure('not-found', `Window ${windowId} is not projecting.`);
    }
    if (projection.state === 'reconnecting') {
      return { ok: true, projection: clone(projection) };
    }
    if (projection.state !== 'projecting' && projection.state !== 'restored') {
      return failure('illegal-state', `Window ${windowId} cannot disconnect from ${projection.state}.`);
    }
    projection.state = 'reconnecting';
    projection.lastError = reason;
    projection.updatedAtMs = this.now();
    return { ok: true, projection: clone(projection) };
  }

  resume(
    windowId: string,
    target: WindowProjectionTarget,
    generation: number
  ): WindowProjectionResult {
    const projection = this.projections.get(windowId);
    if (!projection) {
      return failure('not-found', `Window ${windowId} is not projecting.`);
    }
    if (projection.state !== 'reconnecting') {
      return failure('illegal-state', `Window ${windowId} is not reconnecting.`);
    }
    if (!validTarget(target)) {
      return failure('invalid-target', 'Projection target is invalid.');
    }
    if (!Number.isInteger(generation) || generation < projection.identity.generation) {
      return failure('stale-generation', 'Reconnect generation is stale.');
    }
    const owner = this.targets.get(target.displaySessionId);
    if (owner && owner !== windowId) {
      return failure(
        'target-conflict',
        `Display ${target.displaySessionId} is already projecting window ${owner}.`
      );
    }

    if (target.displaySessionId !== projection.target.displaySessionId) {
      this.targets.delete(projection.target.displaySessionId);
      this.targets.set(target.displaySessionId, windowId);
    }
    projection.target = { ...target };
    projection.identity.generation = generation;
    projection.state = 'restored';
    projection.updatedAtMs = this.now();
    delete projection.lastError;
    return { ok: true, projection: clone(projection) };
  }

  release(windowId: string): WindowProjectionResult {
    const projection = this.projections.get(windowId);
    if (!projection) {
      return failure('not-found', `Window ${windowId} is not projecting.`);
    }
    if (projection.state === 'released') {
      return { ok: true, projection: clone(projection) };
    }
    this.targets.delete(projection.target.displaySessionId);
    projection.state = 'released';
    projection.updatedAtMs = this.now();
    return { ok: true, projection: clone(projection) };
  }

  fail(windowId: string, reason: string): WindowProjectionResult {
    const projection = this.projections.get(windowId);
    if (!projection) {
      return failure('not-found', `Window ${windowId} is not projecting.`);
    }
    this.targets.delete(projection.target.displaySessionId);
    projection.state = 'failed';
    projection.lastError = reason;
    projection.updatedAtMs = this.now();
    return { ok: true, projection: clone(projection) };
  }

  get(windowId: string): WindowProjection | undefined {
    const projection = this.projections.get(windowId);
    return projection ? clone(projection) : undefined;
  }

  list(): WindowProjection[] {
    return [...this.projections.values()]
      .filter((projection) => projection.state !== 'released')
      .sort((left, right) => left.identity.windowId.localeCompare(right.identity.windowId))
      .map(clone);
  }
}
