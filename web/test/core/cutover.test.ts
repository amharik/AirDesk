import { describe, expect, it } from 'vitest';
import {
  CORE_FEATURES,
  CoreCutoverStore,
  DEFAULT_CORE_AVAILABILITY,
  resolveCoreSelection
} from '../../src/core/cutover';

function memoryStorage(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => {
      values.set(key, value);
    }
  };
}

describe('core cutover control plane', () => {
  it('defaults every feature to native with no fallback', () => {
    const store = new CoreCutoverStore();
    for (const selection of store.snapshot()) {
      expect(selection.requested).toBe('native');
      expect(selection.active).toBe('native');
      expect(selection.reason).toBe('none');
      expect(selection.isFallback).toBe(false);
    }
  });

  it('honors query requests and reports gated fallbacks', () => {
    const store = new CoreCutoverStore({
      search: '?coreMovement=core&corePairing=core&coreEnvelope=core&coreSync=core',
      availability: { ...DEFAULT_CORE_AVAILABILITY, movement: true }
    });

    expect(store.get('movement')).toMatchObject({ active: 'core', reason: 'none' });
    expect(store.get('pairing')).toMatchObject({
      active: 'native',
      reason: 'independent-review-required',
      isFallback: true
    });
    expect(store.get('envelope')).toMatchObject({
      active: 'native',
      reason: 'binding-unavailable'
    });
    expect(store.get('sync')).toMatchObject({
      active: 'native',
      reason: 'fixture-migration-pending'
    });
  });

  it('falls movement back when the browser binding is unavailable', () => {
    expect(resolveCoreSelection('movement', 'core')).toMatchObject({
      active: 'native',
      reason: 'binding-unavailable'
    });
  });

  it('persists requested paths without persisting the resolved path', () => {
    const storage = memoryStorage();
    const store = new CoreCutoverStore({ storage, availability: { ...DEFAULT_CORE_AVAILABILITY, movement: true } });

    store.set('movement', 'core');
    store.set('pairing', 'core');
    expect(storage.getItem('airdesk.core.movement')).toBe('core');
    expect(storage.getItem('airdesk.core.pairing')).toBe('core');

    const reloaded = new CoreCutoverStore({
      storage,
      availability: { ...DEFAULT_CORE_AVAILABILITY, movement: true }
    });
    expect(reloaded.get('movement').active).toBe('core');
    expect(reloaded.get('pairing').active).toBe('native');
    expect(reloaded.telemetry()).toContain('pairing=native requested=core reason=independent-review-required');
  });

  it('treats invalid stored values as native', () => {
    const storage = memoryStorage(
      Object.fromEntries(CORE_FEATURES.map((feature) => [`airdesk.core.${feature}`, 'bogus']))
    );
    const store = new CoreCutoverStore({ storage });
    for (const feature of CORE_FEATURES) {
      expect(store.get(feature).requested).toBe('native');
    }
  });
});
