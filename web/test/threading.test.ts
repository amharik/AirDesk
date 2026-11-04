import { JSDOM } from 'jsdom';
import { describe, expect, it } from 'vitest';
import {
  createThreading,
  detectThreading,
  installThreading,
  SynchronizationUnavailableError
} from '../src/runtime/threading';

const sharedScope = {
  SharedArrayBuffer: function SharedArrayBuffer() {},
  Atomics: {},
  crossOriginIsolated: true
};

describe('runtime threading', () => {
  it('defaults to a single-threaded profile without synchronization primitives', () => {
    expect(detectThreading({})).toEqual({
      sharedArrayBuffer: false,
      atomics: false,
      crossOriginIsolated: false,
      sharedMemoryAvailable: false
    });
    expect(createThreading({}).profile).toBe('single-threaded');
  });

  it('requires shared memory, atomics, and cross-origin isolation together', () => {
    expect(detectThreading(sharedScope).sharedMemoryAvailable).toBe(true);
    expect(detectThreading({ ...sharedScope, crossOriginIsolated: false }).sharedMemoryAvailable).toBe(
      false
    );
    expect(detectThreading({ ...sharedScope, Atomics: undefined }).sharedMemoryAvailable).toBe(false);
    expect(
      detectThreading({ ...sharedScope, SharedArrayBuffer: undefined }).sharedMemoryAvailable
    ).toBe(false);
  });

  it('fails an explicit shared-memory request with SynchronizationUnavailable', () => {
    const threading = createThreading({}, 'shared-memory');

    expect(threading.requestedProfile).toBe('shared-memory');
    expect(threading.profile).toBe('single-threaded');
    expect(threading.supports('shared-memory')).toBe(false);
    expect(() => threading.require('shared-memory')).toThrow(SynchronizationUnavailableError);

    try {
      threading.require('shared-memory');
    } catch (error) {
      expect(error).toMatchObject({ code: 'SynchronizationUnavailable' });
    }
  });

  it('activates shared memory only when requested and fully supported', () => {
    const threading = createThreading(sharedScope, 'shared-memory');

    expect(threading.profile).toBe('shared-memory');
    expect(threading.supports('shared-memory')).toBe(true);
    expect(() => threading.require('shared-memory')).not.toThrow();
    expect(createThreading(sharedScope).profile).toBe('single-threaded');
  });

  it('reads the requested profile without silently profiling unsupported runtime shared memory', () => {
    const dom = new JSDOM('<!doctype html>', { url: 'https://airdesk.test/?threading=shared' });
    const window = dom.window as unknown as Window;
    const threading = installThreading(window);

    expect(threading.requestedProfile).toBe('shared-memory');
    expect(threading.profile).toBe('single-threaded');
    expect(window.AirDeskThreading).toBe(threading);
    expect(() => threading.require('shared-memory')).toThrow(SynchronizationUnavailableError);
  });
});
