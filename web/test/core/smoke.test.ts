import { describe, expect, it, vi } from 'vitest';
import {
  createCoreSmokeLoader,
  isCoreSmokeEnabled,
  loadCoreSmoke,
  type CoreSmokeModule
} from '../../src/core/smoke';

const module: CoreSmokeModule = {
  coreAbiVersion: () => 1,
  coreIsAbiCompatible: (required) => required === 1,
  coreSmokeLabel: () => 'airdesk-core/1'
};

describe('core smoke adapter', () => {
  it('only enables the smoke path when explicitly requested', () => {
    expect(isCoreSmokeEnabled('?coreSmoke=1')).toBe(true);
    expect(isCoreSmokeEnabled('?coreSmoke=0')).toBe(false);
    expect(isCoreSmokeEnabled('')).toBe(false);
  });

  it('does not load the module while the flag is disabled', async () => {
    const loader = vi.fn(async () => module);
    await expect(loadCoreSmoke(false, loader)).resolves.toBeNull();
    expect(loader).not.toHaveBeenCalled();
  });

  it('reports the generated module ABI and label', async () => {
    await expect(loadCoreSmoke(true, async () => module)).resolves.toEqual({
      label: 'airdesk-core/1',
      abiVersion: 1,
      compatible: true
    });
  });

  it('loads a module through the generated bindings URL', async () => {
    const url = new URL(
      'data:text/javascript,' +
        encodeURIComponent(
          'export function coreAbiVersion(){return 1}' +
            'export function coreIsAbiCompatible(required){return required === 1}' +
            "export function coreSmokeLabel(){return 'airdesk-core/1'}"
        )
    ).href;
    await expect(createCoreSmokeLoader(url)()).resolves.toMatchObject({
      coreAbiVersion: expect.any(Function),
      coreIsAbiCompatible: expect.any(Function),
      coreSmokeLabel: expect.any(Function)
    });
  });
});
