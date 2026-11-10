import type {
  CapabilityAuthorization,
  CapabilityAvailability
} from '../remote/placement';

export type DeviceAgentLifecycleState = 'starting' | 'ready' | 'degraded' | 'unavailable';
export type DeviceAgentEventType = 'lifecycle' | 'health' | 'capability' | 'lease';
export type DeviceAgentPlatformPermissionState =
  | 'granted'
  | 'denied'
  | 'not-determined'
  | 'restricted';
export type DeviceAgentErrorCode =
  | 'invalid-identity'
  | 'invalid-capability'
  | 'capability-unknown'
  | 'authorization-denied'
  | 'authorization-revoked'
  | 'capability-busy'
  | 'capability-restricted'
  | 'capability-unavailable'
  | 'operation-not-allowed'
  | 'platform-permission-denied'
  | 'agent-unavailable'
  | 'lease-not-found'
  | 'invalid-event-type'
  | 'invalid-request';

export class DeviceAgentContractError extends Error {
  readonly code: DeviceAgentErrorCode;
  readonly detail?: string;

  constructor(code: DeviceAgentErrorCode, message: string, detail?: string) {
    super(message);
    this.name = 'DeviceAgentContractError';
    this.code = code;
    this.detail = detail;
  }
}

export interface DeviceAgentIdentity {
  deviceId: string;
  displayName: string;
  platform: string;
  algorithm: string;
  publicKeySpkiBase64Url: string;
  createdAtEpochMillis: number;
}

export interface DeviceAgentCapability {
  capUri: string;
  version: number;
  providerDeviceId: string;
  operations: readonly string[];
  permissions: readonly string[];
  execution: string;
  transport: string;
  constraints: string;
  availability: CapabilityAvailability;
  authorization: CapabilityAuthorization;
  label: string;
  summary: string;
  note: string;
  authorizationRef?: string;
}

export interface DeviceAgentCapabilityRequest {
  capUri: string;
  operations: readonly string[];
  workspaceId: string;
  applicationId: string;
  requesterDeviceId: string;
  sessionId: string;
  leaseId?: string;
  auditId?: string;
}

export interface DeviceAgentLease {
  leaseId: string;
  auditId: string;
  capUri: string;
  operations: readonly string[];
  workspaceId: string;
  applicationId: string;
  requesterDeviceId: string;
  sessionId: string;
  issuedAtEpochMillis: number;
  expiresAtEpochMillis: number;
}

export interface DeviceAgentHealth {
  state: DeviceAgentLifecycleState;
  generation: number;
  uptimeMillis: number;
  capabilityCount: number;
  availableCapabilityCount: number;
  busyCapabilityCount: number;
  restrictedCapabilityCount: number;
  unavailableCapabilityCount: number;
  authorizedCapabilityCount: number;
  activeLeaseCount: number;
}

export interface DeviceAgentEvent {
  type: DeviceAgentEventType;
  sequence: number;
  atEpochMillis: number;
  action: string;
  leaseId?: string;
  capUri?: string;
  state?: DeviceAgentLifecycleState;
  permission?: string;
}

export interface DeviceAgentSubscription {
  readonly active: boolean;
  cancel(): void;
}

export interface DeviceAgentOptions {
  leaseDurationMillis?: number;
  now?: () => number;
}

interface SubscriptionRecord {
  type: DeviceAgentEventType;
  handler: (event: DeviceAgentEvent) => void;
}

const EVENT_TYPES = new Set<DeviceAgentEventType>([
  'lifecycle',
  'health',
  'capability',
  'lease'
]);
const AVAILABILITY = new Set<CapabilityAvailability>([
  'available',
  'busy',
  'restricted',
  'unavailable'
]);
const AUTHORIZATION = new Set<CapabilityAuthorization>([
  'ungranted',
  'granted',
  'denied',
  'revoked'
]);
const PERMISSION_STATES = new Set<DeviceAgentPlatformPermissionState>([
  'granted',
  'denied',
  'not-determined',
  'restricted'
]);

function bounded(value: unknown, maximum: number): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= maximum;
}

function uniqueBoundedStrings(
  value: readonly string[],
  maximum: number
): boolean {
  return value.every((entry) => bounded(entry, maximum)) &&
    new Set(value).size === value.length;
}

export class DeviceAgent {
  private readonly identityValue: DeviceAgentIdentity;
  private readonly capabilityValues: readonly DeviceAgentCapability[];
  private readonly permissions: ReadonlyMap<string, DeviceAgentPlatformPermissionState>;
  private readonly leaseDurationMillis: number;
  private readonly now: () => number;
  private lifecycleState: DeviceAgentLifecycleState = 'starting';
  private generation = 0;
  private startedAtEpochMillis: number | undefined;
  private readonly leases = new Map<string, DeviceAgentLease>();
  private readonly subscriptions = new Map<number, SubscriptionRecord>();
  private nextSubscriptionId = 0;
  private nextSequence = 0;
  private nextLeaseOrdinal = 0;

  constructor(
    identity: DeviceAgentIdentity,
    capabilities: readonly DeviceAgentCapability[],
    permissions: Readonly<Record<string, DeviceAgentPlatformPermissionState>> = {},
    options: DeviceAgentOptions = {}
  ) {
    this.validateIdentity(identity);
    this.validateCapabilities(capabilities);
    for (const [permission, state] of Object.entries(permissions)) {
      if (!bounded(permission, 128) || !PERMISSION_STATES.has(state)) {
        throw new DeviceAgentContractError(
          'invalid-request',
          'invalid platform permission state',
          permission
        );
      }
    }
    const leaseDurationMillis = options.leaseDurationMillis ?? 600_000;
    if (!Number.isSafeInteger(leaseDurationMillis) || leaseDurationMillis <= 0) {
      throw new DeviceAgentContractError(
        'invalid-request',
        'lease duration must be a positive safe integer'
      );
    }
    this.identityValue = Object.freeze({ ...identity });
    this.capabilityValues = Object.freeze(
      capabilities.map((capability) => Object.freeze({
        ...capability,
        operations: Object.freeze([...capability.operations]),
        permissions: Object.freeze([...capability.permissions])
      }))
    );
    this.permissions = new Map(Object.entries(permissions));
    this.leaseDurationMillis = leaseDurationMillis;
    this.now = options.now ?? Date.now;
  }

  identity(): DeviceAgentIdentity {
    return { ...this.identityValue };
  }

  capabilities(): readonly DeviceAgentCapability[] {
    return [...this.capabilityValues].sort((left, right) =>
      left.capUri < right.capUri ? -1 : left.capUri > right.capUri ? 1 : 0
    );
  }

  get state(): DeviceAgentLifecycleState {
    return this.lifecycleState;
  }

  start(): void {
    if (this.lifecycleState === 'ready') return;
    const action = this.lifecycleState === 'unavailable' ? 'reconnected' : 'started';
    this.lifecycleState = 'ready';
    this.generation += 1;
    this.startedAtEpochMillis = this.now();
    this.emit('lifecycle', action, { state: 'ready' });
    this.emit('health', 'updated', { state: 'ready' });
  }

  reconnect(): void {
    this.start();
  }

  disconnect(): void {
    if (this.lifecycleState === 'unavailable') return;
    const revoked = [...this.leases.values()].sort((left, right) =>
      left.leaseId < right.leaseId ? -1 : left.leaseId > right.leaseId ? 1 : 0
    );
    this.leases.clear();
    this.lifecycleState = 'unavailable';
    this.generation += 1;
    this.startedAtEpochMillis = undefined;
    for (const lease of revoked) {
      this.emit('lease', 'revoked', {
        leaseId: lease.leaseId,
        capUri: lease.capUri
      });
    }
    this.emit('lifecycle', 'disconnected', { state: 'unavailable' });
    this.emit('health', 'updated', { state: 'unavailable' });
  }

  markDegraded(reason: string): void {
    if (this.lifecycleState === 'unavailable') return;
    this.lifecycleState = 'degraded';
    this.generation += 1;
    this.emit('lifecycle', reason, { state: 'degraded' });
    this.emit('health', 'updated', { state: 'degraded' });
  }

  restore(): void {
    if (this.lifecycleState !== 'degraded') return;
    this.lifecycleState = 'ready';
    this.generation += 1;
    this.emit('lifecycle', 'restored', { state: 'ready' });
    this.emit('health', 'updated', { state: 'ready' });
  }

  health(): DeviceAgentHealth {
    const capabilities = this.capabilityValues;
    return {
      state: this.lifecycleState,
      generation: this.generation,
      uptimeMillis: this.startedAtEpochMillis === undefined
        ? 0
        : Math.max(0, this.now() - this.startedAtEpochMillis),
      capabilityCount: capabilities.length,
      availableCapabilityCount: capabilities.filter(
        (capability) => capability.availability === 'available'
      ).length,
      busyCapabilityCount: capabilities.filter(
        (capability) => capability.availability === 'busy'
      ).length,
      restrictedCapabilityCount: capabilities.filter(
        (capability) => capability.availability === 'restricted'
      ).length,
      unavailableCapabilityCount: capabilities.filter(
        (capability) => capability.availability === 'unavailable'
      ).length,
      authorizedCapabilityCount: capabilities.filter(
        (capability) => capability.authorization === 'granted'
      ).length,
      activeLeaseCount: this.leases.size
    };
  }

  activeLeases(): readonly DeviceAgentLease[] {
    return [...this.leases.values()].sort((left, right) =>
      left.leaseId < right.leaseId ? -1 : left.leaseId > right.leaseId ? 1 : 0
    );
  }

  requestCapability(request: DeviceAgentCapabilityRequest): DeviceAgentLease {
    if (this.lifecycleState !== 'ready' && this.lifecycleState !== 'degraded') {
      throw new DeviceAgentContractError(
        'agent-unavailable',
        'the device agent is unavailable'
      );
    }
    if (
      !bounded(request.capUri, 512) ||
      !Array.isArray(request.operations) ||
      request.operations.length === 0 ||
      !uniqueBoundedStrings(request.operations, 128) ||
      !bounded(request.workspaceId, 512) ||
      !bounded(request.applicationId, 512) ||
      !bounded(request.requesterDeviceId, 512) ||
      !bounded(request.sessionId, 512) ||
      (request.leaseId !== undefined && !bounded(request.leaseId, 512)) ||
      (request.auditId !== undefined && !bounded(request.auditId, 512))
    ) {
      throw new DeviceAgentContractError(
        'invalid-request',
        'required capability request fields are missing'
      );
    }
    const capability = this.capabilityValues.find(
      (candidate) => candidate.capUri === request.capUri
    );
    if (capability === undefined) {
      throw new DeviceAgentContractError(
        'capability-unknown',
        `capability ${request.capUri} is not advertised`,
        request.capUri
      );
    }
    for (const operation of request.operations) {
      if (!capability.operations.includes(operation)) {
        throw new DeviceAgentContractError(
          'operation-not-allowed',
          `operation ${operation} is not allowed`,
          operation
        );
      }
    }
    switch (capability.authorization) {
      case 'granted':
        break;
      case 'revoked':
        throw new DeviceAgentContractError(
          'authorization-revoked',
          'the capability authorization was revoked'
        );
      case 'ungranted':
      case 'denied':
        throw new DeviceAgentContractError(
          'authorization-denied',
          'the capability is not authorized'
        );
    }
    switch (capability.availability) {
      case 'available':
        break;
      case 'busy':
        throw new DeviceAgentContractError(
          'capability-busy',
          'the capability is temporarily busy'
        );
      case 'restricted':
        throw new DeviceAgentContractError(
          'capability-restricted',
          'the capability is restricted by policy'
        );
      case 'unavailable':
        throw new DeviceAgentContractError(
          'capability-unavailable',
          'the capability is unavailable'
        );
    }
    for (const permission of capability.permissions) {
      if (this.permissions.get(permission) !== 'granted') {
        throw new DeviceAgentContractError(
          'platform-permission-denied',
          `platform permission ${permission} is not granted`,
          permission
        );
      }
    }

    this.nextLeaseOrdinal += 1;
    const leaseId = request.leaseId ?? `lease-${this.nextLeaseOrdinal}`;
    if (this.leases.has(leaseId)) {
      throw new DeviceAgentContractError(
        'invalid-request',
        `lease ${leaseId} is already active`,
        leaseId
      );
    }
    const issuedAt = this.now();
    const lease: DeviceAgentLease = Object.freeze({
      leaseId,
      auditId: request.auditId ?? `audit-${this.nextLeaseOrdinal}`,
      capUri: capability.capUri,
      operations: Object.freeze([...request.operations]),
      workspaceId: request.workspaceId,
      applicationId: request.applicationId,
      requesterDeviceId: request.requesterDeviceId,
      sessionId: request.sessionId,
      issuedAtEpochMillis: issuedAt,
      expiresAtEpochMillis: issuedAt + this.leaseDurationMillis
    });
    this.leases.set(leaseId, lease);
    this.emit('lease', 'granted', {
      leaseId,
      capUri: capability.capUri
    });
    this.emit('health', 'updated', { state: this.lifecycleState });
    return lease;
  }

  releaseCapability(leaseId: string): void {
    const lease = this.leases.get(leaseId);
    if (lease === undefined) {
      throw new DeviceAgentContractError(
        'lease-not-found',
        `lease ${leaseId} is not active`,
        leaseId
      );
    }
    this.leases.delete(leaseId);
    this.emit('lease', 'released', {
      leaseId,
      capUri: lease.capUri
    });
    this.emit('health', 'updated', { state: this.lifecycleState });
  }

  subscribe(
    eventType: string,
    handler: (event: DeviceAgentEvent) => void
  ): DeviceAgentSubscription {
    if (!EVENT_TYPES.has(eventType as DeviceAgentEventType)) {
      throw new DeviceAgentContractError(
        'invalid-event-type',
        `subscription event type ${eventType} is invalid`,
        eventType
      );
    }
    this.nextSubscriptionId += 1;
    const subscriptionId = this.nextSubscriptionId;
    this.subscriptions.set(subscriptionId, {
      type: eventType as DeviceAgentEventType,
      handler
    });
    let active = true;
    return {
      get active(): boolean {
        return active;
      },
      cancel: () => {
        if (!active) return;
        active = false;
        this.subscriptions.delete(subscriptionId);
      }
    };
  }

  private validateIdentity(identity: DeviceAgentIdentity): void {
    if (
      !bounded(identity.deviceId, 512) ||
      !bounded(identity.displayName, 128) ||
      !bounded(identity.platform, 32) ||
      !bounded(identity.algorithm, 32) ||
      !bounded(identity.publicKeySpkiBase64Url, 4096) ||
      !Number.isSafeInteger(identity.createdAtEpochMillis) ||
      identity.createdAtEpochMillis < 0
    ) {
      throw new DeviceAgentContractError(
        'invalid-identity',
        'the device agent identity is invalid'
      );
    }
  }

  private validateCapabilities(capabilities: readonly DeviceAgentCapability[]): void {
    if (capabilities.length === 0) {
      throw new DeviceAgentContractError(
        'invalid-capability',
        'at least one capability is required'
      );
    }
    const capUris = new Set<string>();
    for (const capability of capabilities) {
      if (
        !bounded(capability.capUri, 512) ||
        capUris.has(capability.capUri) ||
        !Number.isSafeInteger(capability.version) ||
        capability.version < 1 ||
        !bounded(capability.providerDeviceId, 512) ||
        !Array.isArray(capability.operations) ||
        capability.operations.length === 0 ||
        !uniqueBoundedStrings(capability.operations, 128) ||
        !Array.isArray(capability.permissions) ||
        !uniqueBoundedStrings(capability.permissions, 128) ||
        !bounded(capability.execution, 64) ||
        !bounded(capability.transport, 64) ||
        !bounded(capability.constraints, 4096) ||
        !AVAILABILITY.has(capability.availability) ||
        !AUTHORIZATION.has(capability.authorization) ||
        !bounded(capability.label, 128) ||
        !bounded(capability.summary, 512) ||
        !bounded(capability.note, 2048) ||
        (capability.authorizationRef !== undefined &&
          !bounded(capability.authorizationRef, 256))
      ) {
        throw new DeviceAgentContractError(
          'invalid-capability',
          'a device agent capability is invalid',
          capability.capUri
        );
      }
      capUris.add(capability.capUri);
    }
  }

  private emit(
    type: DeviceAgentEventType,
    action: string,
    fields: {
      leaseId?: string;
      capUri?: string;
      state?: DeviceAgentLifecycleState;
      permission?: string;
    } = {}
  ): void {
    const matching = [...this.subscriptions.values()].filter(
      (subscription) => subscription.type === type
    );
    if (matching.length === 0) return;
    for (const subscription of matching) {
      this.nextSequence += 1;
      subscription.handler({
        type,
        sequence: this.nextSequence,
        atEpochMillis: this.now(),
        action,
        ...(fields.leaseId === undefined ? {} : { leaseId: fields.leaseId }),
        ...(fields.capUri === undefined ? {} : { capUri: fields.capUri }),
        ...(fields.state === undefined ? {} : { state: fields.state }),
        ...(fields.permission === undefined ? {} : { permission: fields.permission })
      });
    }
  }
}
