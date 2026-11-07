import { describe, expect, it } from 'vitest';
import {
  CapabilityRegistry,
  CapabilityRegistryError,
  validateCapabilityDescriptor
} from '../src/capability';
import type { RegisteredCapabilityDescriptor } from '../src/capability';

const capUri = 'airdesk://media/camera/capture';

function descriptor(
  overrides: Partial<RegisteredCapabilityDescriptor> = {}
): RegisteredCapabilityDescriptor {
  return {
    providerDeviceId: 'dev-a',
    runtimeId: 'runtime-1',
    capUri,
    version: 1,
    availability: 'available',
    authorization: 'granted',
    execution: 'remote',
    transport: 'websocket',
    latencyMs: 20,
    ...overrides
  };
}

function registryFailure(action: () => unknown): void {
  let thrown: unknown;
  try {
    action();
  } catch (error) {
    thrown = error;
  }
  expect(thrown).toBeInstanceOf(CapabilityRegistryError);
  expect((thrown as CapabilityRegistryError).code).toBe('invalid-descriptor');
}

describe('capability registry', () => {
  it('validates, freezes and registers descriptors by provider, runtime, URI and version', () => {
    const registry = new CapabilityRegistry();
    const validated = validateCapabilityDescriptor(
      descriptor({
        permissions: ['ios.camera.video'],
        constraints: { hardwareAvailable: true, streaming: false }
      })
    );

    expect(Object.isFrozen(validated)).toBe(true);
    expect(Object.isFrozen(validated.permissions)).toBe(true);
    expect(Object.isFrozen(validated.constraints)).toBe(true);
    expect(registry.register(validated)).toBe(true);
    expect(registry.size).toBe(1);
    expect(registry.list()).toEqual([validated]);
  });

  it('rejects malformed descriptors before they can be resolved', () => {
    const invalid = [
      { providerDeviceId: '' },
      { runtimeId: '' },
      { capUri: 'https://media/camera/capture' },
      { version: 0 },
      { availability: 'online' },
      { authorization: 'unknown' },
      { execution: 'cloud' },
      { transport: '' },
      { latencyMs: Number.NaN },
      { permissions: ['camera', 'camera'] },
      { constraints: ['not', 'a', 'map'] },
      { constraints: { streaming: Number.POSITIVE_INFINITY } }
    ];

    for (const patch of invalid) {
      registryFailure(() =>
        validateCapabilityDescriptor(
          descriptor(patch as unknown as Partial<RegisteredCapabilityDescriptor>)
        )
      );
    }
  });

  it('replaces an existing advertisement at the same key and removes by version', () => {
    const registry = new CapabilityRegistry();
    expect(registry.register(descriptor())).toBe(true);
    expect(registry.register(descriptor({ latencyMs: 5 }))).toBe(false);
    expect(registry.size).toBe(1);
    expect(registry.list()[0]?.latencyMs).toBe(5);

    expect(registry.register(descriptor({ version: 2 }))).toBe(true);
    expect(registry.size).toBe(2);
    expect(registry.remove('dev-a', capUri, 1)).toBe(1);
    expect(registry.size).toBe(1);
    expect(registry.remove('dev-a', capUri)).toBe(1);
    expect(registry.size).toBe(0);
  });

  it('keeps availability and authorization independent', () => {
    const registry = new CapabilityRegistry();
    registry.register(descriptor());

    expect(registry.updateAvailability('dev-a', 'runtime-1', capUri, 1, 'busy')).toBe(true);
    expect(registry.list()[0]).toMatchObject({
      availability: 'busy',
      authorization: 'granted'
    });

    expect(registry.updateAuthorization('dev-a', 'runtime-1', capUri, 1, 'revoked')).toBe(true);
    expect(registry.list()[0]).toMatchObject({
      availability: 'busy',
      authorization: 'revoked'
    });

    expect(registry.updateAvailability('dev-b', 'runtime-1', capUri, 1, 'busy')).toBe(false);
    expect(registry.updateAuthorization('dev-a', 'runtime-1', capUri, 2, 'granted')).toBe(false);
  });

  it('resolves deterministically with explainable diagnostics', () => {
    const registry = new CapabilityRegistry();
    registry.register(descriptor({ providerDeviceId: 'dev-b', latencyMs: 30 }));
    registry.register(descriptor({ providerDeviceId: 'dev-a', latencyMs: 20 }));
    registry.register(descriptor({ providerDeviceId: 'dev-c', latencyMs: 10, authorization: 'ungranted' }));

    const result = registry.resolve({ capUri });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.provider.providerDeviceId).toBe('dev-a');
    expect(
      result.diagnostics.find((entry) => entry.outcome === 'selected')?.providerDeviceId
    ).toBe('dev-a');
    expect(
      result.diagnostics.find((entry) => entry.providerDeviceId === 'dev-c')?.outcome
    ).toBe('unauthorized');
  });
});
