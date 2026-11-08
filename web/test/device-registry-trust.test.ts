import { describe, expect, it } from 'vitest';
import { DeviceRegistry, DeviceRegistryError } from '../src/identity';

const DEVICE = `ad-device:${'a'.repeat(64)}`;
const OTHER = `ad-device:${'b'.repeat(64)}`;

describe('browser device registry trust states', () => {
  it('keeps pending peers untrusted and unable to open sessions', () => {
    const registry = new DeviceRegistry();
    const record = registry.enrollPending({ deviceId: DEVICE, publicKey: 'pending-key' });

    expect(record.trustState).toBe('pending');
    expect(registry.isTrusted(DEVICE)).toBe(false);
    expect(() => registry.issueSession(DEVICE, 60_000)).toThrowError(
      expect.objectContaining({ code: 'device-pending' })
    );
  });

  it('promotes pending peers only through explicit trust', () => {
    const registry = new DeviceRegistry();
    registry.enrollPending({ deviceId: DEVICE, publicKey: 'pending-key' });

    const trusted = registry.trust(DEVICE);

    expect(trusted.trustState).toBe('trusted');
    expect(registry.isTrusted(DEVICE)).toBe(true);
    expect(registry.issueSession(DEVICE, 60_000).deviceId).toBe(DEVICE);
  });

  it('does not let a pending enrollment downgrade a trusted peer', () => {
    const registry = new DeviceRegistry();
    registry.pair({ deviceId: DEVICE, publicKey: 'trusted-key' });
    registry.enrollPending({ deviceId: DEVICE, publicKey: 'trusted-key' });

    expect(registry.isTrusted(DEVICE)).toBe(true);
    expect(registry.get(DEVICE)?.trustState).toBe('trusted');
  });

  it('revokes pending and trusted peers and refuses later trust', () => {
    const registry = new DeviceRegistry();
    registry.enrollPending({ deviceId: DEVICE, publicKey: 'pending-key' });
    registry.pair({ deviceId: OTHER, publicKey: 'trusted-key' });

    expect(registry.revoke(DEVICE)).toBe(true);
    expect(registry.revoke(OTHER)).toBe(true);
    expect(registry.isRevoked(DEVICE)).toBe(true);
    expect(registry.isRevoked(OTHER)).toBe(true);
    expect(() => registry.trust(DEVICE)).toThrowError(
      expect.objectContaining({ code: 'device-revoked' })
    );
    expect(() => registry.enrollPending({ deviceId: OTHER, publicKey: 'trusted-key' })).toThrowError(
      DeviceRegistryError
    );
    expect(registry.validateLease({
      deviceId: DEVICE,
      leaseId: 'lease',
      issuedAt: 0,
      expiresAt: Number.MAX_SAFE_INTEGER,
      epoch: 0
    })).toBe(false);
  });
});
