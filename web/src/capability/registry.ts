import {
  compareCapabilityDescriptors,
  selectProvider
} from '../remote/placement';
import type {
  CapabilityAuthorization,
  CapabilityAvailability,
  CapabilityDescriptor,
  CapabilityExecution,
  PlacementRequest,
  PlacementResult
} from '../remote/placement';
import type { CapabilityRevocationRecord } from './revocation';

export interface RegisteredCapabilityDescriptor extends CapabilityDescriptor {
  permissions?: readonly string[];
  constraints?: Readonly<Record<string, string | number | boolean>>;
  authorizationRef?: string;
}

export type CapabilityRegistryErrorCode =
  | 'invalid-descriptor'
  | 'not-found';

export class CapabilityRegistryError extends Error {
  readonly code: CapabilityRegistryErrorCode;

  constructor(code: CapabilityRegistryErrorCode, message: string) {
    super(message);
    this.name = 'CapabilityRegistryError';
    this.code = code;
  }
}

const MAX_IDENTIFIER = 512;
const MAX_VERSION = 2_147_483_647;
const MAX_LATENCY_MS = 600_000;
const MAX_PERMISSIONS = 32;
const MAX_CONSTRAINTS = 32;
const MAX_TRANSPORT = 64;
const CAP_URI_PATTERN = /^airdesk:\/\/[A-Za-z0-9._~-]+(\/[A-Za-z0-9._~-]+)*$/;
const AVAILABILITY = new Set<CapabilityAvailability>([
  'available',
  'busy',
  'restricted',
  'unavailable'
]);
const AUTHORIZATION = new Set<CapabilityAuthorization>([
  'granted',
  'ungranted',
  'denied',
  'revoked'
]);
const EXECUTION = new Set<CapabilityExecution>([
  'local',
  'remote',
  'streaming'
]);
const CONSTRAINT_KEY_PATTERN = /^[A-Za-z0-9._~-]+$/;

function fail(message: string): never {
  throw new CapabilityRegistryError('invalid-descriptor', message);
}

function requiredString(value: unknown, label: string, maxLength = MAX_IDENTIFIER): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > maxLength) {
    fail(`invalid ${label}`);
  }
  return value;
}

function finiteNumber(value: unknown, label: string, maximum: number): number {
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    value < 0 ||
    value > maximum
  ) {
    fail(`invalid ${label}`);
  }
  return value;
}

function validatePermissions(value: unknown): readonly string[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length > MAX_PERMISSIONS) {
    fail('invalid capability permissions');
  }
  const permissions = value.map((permission) =>
    requiredString(permission, 'capability permission', 128)
  );
  if (new Set(permissions).size !== permissions.length) {
    fail('duplicate capability permission');
  }
  return Object.freeze(permissions);
}

function validateConstraints(
  value: unknown
): Readonly<Record<string, string | number | boolean>> | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    fail('invalid capability constraints');
  }
  const entries = Object.entries(value);
  if (entries.length > MAX_CONSTRAINTS) {
    fail('too many capability constraints');
  }
  const constraints: Record<string, string | number | boolean> = {};
  for (const [key, constraint] of entries) {
    if (!CONSTRAINT_KEY_PATTERN.test(key) || key.length > 64) {
      fail('invalid capability constraint key');
    }
    if (
      typeof constraint !== 'string' &&
      typeof constraint !== 'number' &&
      typeof constraint !== 'boolean'
    ) {
      fail('invalid capability constraint value');
    }
    if (typeof constraint === 'number' && !Number.isFinite(constraint)) {
      fail('invalid capability constraint value');
    }
    if (typeof constraint === 'string' && constraint.length > 256) {
      fail('invalid capability constraint value');
    }
    constraints[key] = constraint;
  }
  return Object.freeze(constraints);
}

export function validateCapabilityDescriptor(
  input: RegisteredCapabilityDescriptor
): RegisteredCapabilityDescriptor {
  if (typeof input !== 'object' || input === null) {
    fail('capability descriptor is required');
  }
  const providerDeviceId = requiredString(input.providerDeviceId, 'provider device ID');
  const runtimeId = requiredString(input.runtimeId, 'runtime ID');
  const capUri = requiredString(input.capUri, 'capability URI');
  if (!CAP_URI_PATTERN.test(capUri)) {
    fail('invalid capability URI');
  }
  if (
    typeof input.version !== 'number' ||
    !Number.isSafeInteger(input.version) ||
    input.version < 1 ||
    input.version > MAX_VERSION
  ) {
    fail('invalid capability version');
  }
  if (!AVAILABILITY.has(input.availability)) {
    fail('invalid capability availability');
  }
  if (!AUTHORIZATION.has(input.authorization)) {
    fail('invalid capability authorization');
  }
  if (!EXECUTION.has(input.execution)) {
    fail('invalid capability execution');
  }
  const transport = requiredString(input.transport, 'capability transport', MAX_TRANSPORT);
  const latencyMs = finiteNumber(input.latencyMs, 'capability latency', MAX_LATENCY_MS);
  const permissions = validatePermissions(input.permissions);
  const constraints = validateConstraints(input.constraints);
  const authorizationRef = input.authorizationRef === undefined
    ? undefined
    : requiredString(input.authorizationRef, 'capability authorization reference', 256);

  return Object.freeze({
    providerDeviceId,
    runtimeId,
    capUri,
    version: input.version,
    availability: input.availability,
    authorization: input.authorization,
    execution: input.execution,
    transport,
    latencyMs,
    ...(permissions === undefined ? {} : { permissions }),
    ...(constraints === undefined ? {} : { constraints }),
    ...(authorizationRef === undefined ? {} : { authorizationRef })
  });
}

function descriptorKey(
  providerDeviceId: string,
  runtimeId: string,
  capUri: string,
  version: number
): string {
  return [providerDeviceId, runtimeId, capUri, String(version)].join('\u0000');
}

export class CapabilityRegistry {
  private readonly descriptorsByKey = new Map<string, RegisteredCapabilityDescriptor>();

  get size(): number {
    return this.descriptorsByKey.size;
  }

  register(input: RegisteredCapabilityDescriptor): boolean {
    const descriptor = validateCapabilityDescriptor(input);
    const key = descriptorKey(
      descriptor.providerDeviceId,
      descriptor.runtimeId,
      descriptor.capUri,
      descriptor.version
    );
    const added = !this.descriptorsByKey.has(key);
    this.descriptorsByKey.set(key, descriptor);
    return added;
  }

  remove(providerDeviceId: string, capUri: string, version?: number): number {
    let removed = 0;
    for (const [key, descriptor] of this.descriptorsByKey) {
      if (
        descriptor.providerDeviceId === providerDeviceId &&
        descriptor.capUri === capUri &&
        (version === undefined || descriptor.version === version)
      ) {
        this.descriptorsByKey.delete(key);
        removed += 1;
      }
    }
    return removed;
  }

  updateAvailability(
    providerDeviceId: string,
    runtimeId: string,
    capUri: string,
    version: number,
    availability: CapabilityAvailability
  ): boolean {
    return this.update(providerDeviceId, runtimeId, capUri, version, { availability });
  }

  updateAuthorization(
    providerDeviceId: string,
    runtimeId: string,
    capUri: string,
    version: number,
    authorization: CapabilityAuthorization
  ): boolean {
    return this.update(providerDeviceId, runtimeId, capUri, version, { authorization });
  }

  descriptor(
    providerDeviceId: string,
    runtimeId: string,
    capUri: string,
    version: number
  ): RegisteredCapabilityDescriptor | undefined {
    return this.descriptorsByKey.get(
      descriptorKey(providerDeviceId, runtimeId, capUri, version)
    );
  }

  list(): readonly RegisteredCapabilityDescriptor[] {
    return Object.freeze(
      [...this.descriptorsByKey.values()].sort(compareCapabilityDescriptors)
    );
  }

  resolve(request: PlacementRequest): PlacementResult {
    return selectProvider(this.list(), request);
  }

  applyRevocation(record: Pick<CapabilityRevocationRecord, 'entries'>): number {
    return this.applyRevokedReferences(
      record.entries
        .filter((entry) => entry.kind === 'grant')
        .map((entry) => entry.ref)
    );
  }

  applyRevokedReferences(references: Iterable<string>): number {
    const revoked = new Set(references);
    let updated = 0;
    for (const [key, descriptor] of this.descriptorsByKey) {
      if (
        descriptor.authorization === 'revoked' ||
        descriptor.authorizationRef === undefined ||
        !revoked.has(descriptor.authorizationRef)
      ) {
        continue;
      }
      this.descriptorsByKey.set(
        key,
        validateCapabilityDescriptor({ ...descriptor, authorization: 'revoked' })
      );
      updated += 1;
    }
    return updated;
  }

  clear(): void {
    this.descriptorsByKey.clear();
  }

  private update(
    providerDeviceId: string,
    runtimeId: string,
    capUri: string,
    version: number,
    patch: Partial<Pick<CapabilityDescriptor, 'availability' | 'authorization'>>
  ): boolean {
    const key = descriptorKey(providerDeviceId, runtimeId, capUri, version);
    const descriptor = this.descriptorsByKey.get(key);
    if (!descriptor) return false;
    this.descriptorsByKey.set(key, validateCapabilityDescriptor({ ...descriptor, ...patch }));
    return true;
  }
}
