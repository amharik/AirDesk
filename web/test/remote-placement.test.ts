import { describe, expect, it } from 'vitest';
import {
  compareCapabilityDescriptors,
  selectProvider
} from '../src/remote/placement';
import type { CapabilityDescriptor, PlacementRequest } from '../src/remote/placement';

const capUri = 'airdesk://compute/wasm/execute';

function provider(overrides: Partial<CapabilityDescriptor> = {}): CapabilityDescriptor {
  return {
    providerDeviceId: 'dev-a',
    runtimeId: 'runtime-1',
    capUri,
    version: 2,
    availability: 'available',
    authorization: 'granted',
    execution: 'remote',
    transport: 'websocket',
    latencyMs: 20,
    ...overrides
  };
}

function request(overrides: Partial<PlacementRequest> = {}): PlacementRequest {
  return { capUri, ...overrides };
}

describe('remote capability placement', () => {
  it('selects an authorized, available provider deterministically', () => {
    const descriptors = [
      provider({ providerDeviceId: 'dev-b', latencyMs: 30 }),
      provider({ providerDeviceId: 'dev-a', latencyMs: 20 })
    ];

    const forward = selectProvider(descriptors, request());
    const reverse = selectProvider([...descriptors].reverse(), request());

    expect(forward.ok).toBe(true);
    expect(reverse.ok).toBe(true);
    if (!forward.ok || !reverse.ok) return;
    expect(forward.provider.providerDeviceId).toBe('dev-a');
    expect(reverse.provider.providerDeviceId).toBe('dev-a');
    expect(forward.diagnostics.find((entry) => entry.outcome === 'selected')?.providerDeviceId).toBe(
      'dev-a'
    );
  });

  it('uses stable device and runtime tie-breaks when latency is equal', () => {
    const left = provider({ providerDeviceId: 'dev-b', runtimeId: 'runtime-1' });
    const right = provider({ providerDeviceId: 'dev-a', runtimeId: 'runtime-2' });
    expect(compareCapabilityDescriptors(left, right)).toBeGreaterThan(0);

    const result = selectProvider([left, right], request());
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.provider.providerDeviceId).toBe('dev-a');
    expect(result.provider.runtimeId).toBe('runtime-2');
  });

  it('honors explicit local, device and runtime placement', () => {
    const descriptors = [
      provider({ providerDeviceId: 'dev-a', runtimeId: 'runtime-local', execution: 'local' }),
      provider({ providerDeviceId: 'dev-b', runtimeId: 'runtime-b', execution: 'remote' })
    ];

    const local = selectProvider(descriptors, request({ placement: 'local' }));
    expect(local.ok).toBe(true);
    if (local.ok) expect(local.provider.execution).toBe('local');

    const device = selectProvider(descriptors, request({ placement: 'device', deviceId: 'dev-b' }));
    expect(device.ok).toBe(true);
    if (device.ok) expect(device.provider.providerDeviceId).toBe('dev-b');

    const runtime = selectProvider(
      descriptors,
      request({ placement: 'runtime', runtimeId: 'runtime-local' })
    );
    expect(runtime.ok).toBe(true);
    if (runtime.ok) expect(runtime.provider.runtimeId).toBe('runtime-local');
  });

  it('returns typed unauthorized failures for ungranted, denied and revoked providers', () => {
    for (const authorization of ['ungranted', 'denied', 'revoked'] as const) {
      const result = selectProvider([provider({ authorization })], request());
      expect(result.ok).toBe(false);
      if (result.ok) continue;
      expect(result.code).toBe('unauthorized');
      expect(result.diagnostics[0]?.reason).toContain(authorization);
    }
  });

  it('returns typed busy, restricted and unavailable failures', () => {
    const busy = selectProvider([provider({ availability: 'busy' })], request());
    expect(busy.ok).toBe(false);
    if (!busy.ok) expect(busy.code).toBe('busy');

    const restricted = selectProvider([provider({ availability: 'restricted' })], request());
    expect(restricted.ok).toBe(false);
    if (!restricted.ok) expect(restricted.code).toBe('restricted');

    const unavailable = selectProvider([provider({ availability: 'unavailable' })], request());
    expect(unavailable.ok).toBe(false);
    if (!unavailable.ok) expect(unavailable.code).toBe('unavailable');
  });

  it('returns typed version mismatch when no provider supports the required version', () => {
    const result = selectProvider(
      [provider({ version: 2 }), provider({ providerDeviceId: 'dev-b', version: 1 })],
      request({ version: 3 })
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('version-mismatch');
    expect(result.diagnostics).toHaveLength(2);
    expect(result.diagnostics.every((entry) => entry.outcome === 'version-mismatch')).toBe(true);
  });

  it('returns typed transport, latency and placement failures', () => {
    const transport = selectProvider([provider({ transport: 'quic' })], request({ transport: 'websocket' }));
    expect(transport.ok).toBe(false);
    if (!transport.ok) expect(transport.code).toBe('transport-unavailable');

    const latency = selectProvider([provider({ latencyMs: 200 })], request({ latencyBudgetMs: 50 }));
    expect(latency.ok).toBe(false);
    if (!latency.ok) expect(latency.code).toBe('latency-budget');

    const placement = selectProvider(
      [provider({ execution: 'remote' })],
      request({ placement: 'local' })
    );
    expect(placement.ok).toBe(false);
    if (!placement.ok) expect(placement.code).toBe('placement-unavailable');

    const missingDevice = selectProvider([provider()], request({ placement: 'device' }));
    expect(missingDevice.ok).toBe(false);
    if (!missingDevice.ok) expect(missingDevice.code).toBe('placement-unavailable');
  });

  it('returns no-provider when no descriptor advertises the capability', () => {
    const result = selectProvider([provider()], request({ capUri: 'airdesk://media/camera/capture' }));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('no-provider');
    expect(result.diagnostics).toEqual([]);
  });
});
