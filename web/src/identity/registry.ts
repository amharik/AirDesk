import { bytesToBase64Url, randomBytes } from './encoding';

const DEVICE_ID_PATTERN = /^ad-device:[0-9a-f]{64}$/;

export type DeviceRegistryErrorCode =
  | 'invalid-device-id'
  | 'invalid-public-key'
  | 'invalid-ttl'
  | 'device-unknown'
  | 'device-revoked';

export class DeviceRegistryError extends Error {
  readonly code: DeviceRegistryErrorCode;

  constructor(code: DeviceRegistryErrorCode, message: string) {
    super(message);
    this.name = 'DeviceRegistryError';
    this.code = code;
  }
}

export interface PairingEnrollment {
  deviceId: string;
  publicKey: string;
  requestedCapabilities?: readonly string[];
  pairedAt?: number;
}

export interface PairedDeviceRecord {
  deviceId: string;
  publicKey: string;
  pairedAt: number;
  revokedAt: number | null;
  requestedCapabilities: readonly string[];
  epoch: number;
}

export interface DeviceSessionLease {
  deviceId: string;
  leaseId: string;
  issuedAt: number;
  expiresAt: number;
  epoch: number;
}

export interface DeviceRegistryOptions {
  now?: () => number;
  createLeaseId?: () => string;
}

function cloneRecord(record: PairedDeviceRecord): PairedDeviceRecord {
  return { ...record, requestedCapabilities: [...record.requestedCapabilities] };
}

export class DeviceRegistry {
  private readonly devices = new Map<string, PairedDeviceRecord>();
  private readonly now: () => number;
  private readonly createLeaseId: () => string;

  constructor(options: DeviceRegistryOptions = {}) {
    this.now = options.now ?? Date.now;
    this.createLeaseId =
      options.createLeaseId ?? (() => bytesToBase64Url(randomBytes(16)));
  }

  pair(enrollment: PairingEnrollment): PairedDeviceRecord {
    if (!DEVICE_ID_PATTERN.test(enrollment.deviceId)) {
      throw new DeviceRegistryError('invalid-device-id', 'invalid device id');
    }
    if (!enrollment.publicKey || enrollment.publicKey.length > 2048) {
      throw new DeviceRegistryError('invalid-public-key', 'invalid public key');
    }

    const existing = this.devices.get(enrollment.deviceId);
    if (existing && existing.revokedAt !== null) {
      throw new DeviceRegistryError('device-revoked', 'revoked device cannot be re-paired');
    }

    const requestedCapabilities = Object.freeze([
      ...new Set(enrollment.requestedCapabilities ?? [])
    ]);
    const record: PairedDeviceRecord = {
      deviceId: enrollment.deviceId,
      publicKey: enrollment.publicKey,
      pairedAt: enrollment.pairedAt ?? this.now(),
      revokedAt: null,
      requestedCapabilities,
      epoch: existing?.epoch ?? 0
    };
    this.devices.set(record.deviceId, record);
    return cloneRecord(record);
  }

  revoke(deviceId: string): boolean {
    const record = this.devices.get(deviceId);
    if (!record || record.revokedAt !== null) return false;
    record.revokedAt = this.now();
    record.epoch += 1;
    return true;
  }

  get(deviceId: string): PairedDeviceRecord | null {
    const record = this.devices.get(deviceId);
    return record ? cloneRecord(record) : null;
  }

  list(): PairedDeviceRecord[] {
    return [...this.devices.values()].map(cloneRecord);
  }

  isTrusted(deviceId: string): boolean {
    const record = this.devices.get(deviceId);
    return Boolean(record && record.revokedAt === null);
  }

  isRevoked(deviceId: string): boolean {
    const record = this.devices.get(deviceId);
    return Boolean(record && record.revokedAt !== null);
  }

  capabilities(deviceId: string): readonly string[] {
    void deviceId;
    return Object.freeze([]);
  }

  issueSession(deviceId: string, ttlMs: number): DeviceSessionLease {
    if (!Number.isSafeInteger(ttlMs) || ttlMs <= 0) {
      throw new DeviceRegistryError('invalid-ttl', 'invalid lease lifetime');
    }
    const record = this.devices.get(deviceId);
    if (!record) throw new DeviceRegistryError('device-unknown', 'device is not paired');
    if (record.revokedAt !== null) {
      throw new DeviceRegistryError('device-revoked', 'device has been revoked');
    }

    const issuedAt = this.now();
    return {
      deviceId,
      leaseId: this.createLeaseId(),
      issuedAt,
      expiresAt: issuedAt + ttlMs,
      epoch: record.epoch
    };
  }

  validateLease(lease: DeviceSessionLease): boolean {
    const record = this.devices.get(lease.deviceId);
    if (!record || record.revokedAt !== null) return false;
    if (lease.epoch !== record.epoch) return false;
    return lease.expiresAt > this.now();
  }
}
