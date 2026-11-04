export type RuntimeThreadingProfile = 'single-threaded' | 'shared-memory';

export const synchronizationUnavailable = 'SynchronizationUnavailable';

export interface ThreadingScope {
  readonly SharedArrayBuffer?: unknown;
  readonly Atomics?: unknown;
  readonly crossOriginIsolated?: boolean;
}

export interface ThreadingCapabilities {
  readonly sharedArrayBuffer: boolean;
  readonly atomics: boolean;
  readonly crossOriginIsolated: boolean;
  readonly sharedMemoryAvailable: boolean;
}

export interface AirDeskThreadingAPI extends ThreadingCapabilities {
  readonly requestedProfile: RuntimeThreadingProfile;
  readonly profile: RuntimeThreadingProfile;
  supports(profile: RuntimeThreadingProfile): boolean;
  require(profile: RuntimeThreadingProfile): void;
}

export class SynchronizationUnavailableError extends Error {
  readonly code = synchronizationUnavailable;

  constructor() {
    super(
      'SynchronizationUnavailable: shared-memory threading requires SharedArrayBuffer, Atomics, and cross-origin isolation.'
    );
    this.name = 'SynchronizationUnavailableError';
  }
}

export function detectThreading(scope: ThreadingScope): ThreadingCapabilities {
  const sharedArrayBuffer = typeof scope.SharedArrayBuffer === 'function';
  const atomics = typeof scope.Atomics === 'object' && scope.Atomics !== null;
  const crossOriginIsolated = scope.crossOriginIsolated === true;

  return {
    sharedArrayBuffer,
    atomics,
    crossOriginIsolated,
    sharedMemoryAvailable: sharedArrayBuffer && atomics && crossOriginIsolated
  };
}

export function createThreading(
  scope: ThreadingScope,
  requestedProfile: RuntimeThreadingProfile = 'single-threaded'
): AirDeskThreadingAPI {
  const capabilities = detectThreading(scope);
  const profile =
    requestedProfile === 'shared-memory' && capabilities.sharedMemoryAvailable
      ? 'shared-memory'
      : 'single-threaded';

  return {
    ...capabilities,
    requestedProfile,
    profile,
    supports(candidate: RuntimeThreadingProfile): boolean {
      return candidate === 'single-threaded' || capabilities.sharedMemoryAvailable;
    },
    require(candidate: RuntimeThreadingProfile): void {
      if (candidate === 'shared-memory' && !capabilities.sharedMemoryAvailable) {
        throw new SynchronizationUnavailableError();
      }
    }
  };
}

export function requestedThreadingProfile(win: Window): RuntimeThreadingProfile {
  let requested = String(win.AIRDESK_THREADING || '');

  try {
    requested = String(new URLSearchParams(win.location.search).get('threading') || requested);
  } catch {
    // Keep the explicit window setting when the URL cannot be parsed.
  }

  return requested === 'shared-memory' || requested === 'shared' ? 'shared-memory' : 'single-threaded';
}

export function installThreading(win: Window): AirDeskThreadingAPI {
  const threading = createThreading(win, requestedThreadingProfile(win));
  win.AirDeskThreading = threading;
  return threading;
}
