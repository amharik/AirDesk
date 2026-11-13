export type CoreFeature = 'movement' | 'envelope' | 'pairing' | 'sync';
export type CoreFeaturePath = 'native' | 'core';
export type CoreFallbackReason =
  | 'none'
  | 'binding-unavailable'
  | 'independent-review-required'
  | 'fixture-migration-pending';

export interface CoreFeatureSelection {
  feature: CoreFeature;
  requested: CoreFeaturePath;
  active: CoreFeaturePath;
  reason: CoreFallbackReason;
  isFallback: boolean;
  telemetry: string;
}

export type CoreCutoverAvailability = Record<CoreFeature, boolean>;

export const CORE_FEATURES: readonly CoreFeature[] = [
  'movement',
  'envelope',
  'pairing',
  'sync'
];

export const DEFAULT_CORE_AVAILABILITY: CoreCutoverAvailability = Object.freeze({
  movement: false,
  envelope: false,
  pairing: false,
  sync: false
});

export interface CoreCutoverStoreOptions {
  search?: string;
  storage?: Pick<Storage, 'getItem' | 'setItem'> | null;
  availability?: CoreCutoverAvailability;
}

function isFeaturePath(value: string | null | undefined): value is CoreFeaturePath {
  return value === 'native' || value === 'core';
}

function queryValue(search: string, feature: CoreFeature): string | null {
  const params = new URLSearchParams(search);
  return params.get(`core${feature.charAt(0).toUpperCase()}${feature.slice(1)}`);
}

export function resolveCoreSelection(
  feature: CoreFeature,
  requested: CoreFeaturePath,
  availability: CoreCutoverAvailability = DEFAULT_CORE_AVAILABILITY
): CoreFeatureSelection {
  let active: CoreFeaturePath = requested;
  let reason: CoreFallbackReason = 'none';

  if (requested === 'core') {
    switch (feature) {
      case 'movement':
        if (!availability.movement) {
          active = 'native';
          reason = 'binding-unavailable';
        }
        break;
      case 'envelope':
        active = 'native';
        reason = 'binding-unavailable';
        break;
      case 'pairing':
        active = 'native';
        reason = 'independent-review-required';
        break;
      case 'sync':
        active = 'native';
        reason = 'fixture-migration-pending';
        break;
    }
  }

  return {
    feature,
    requested,
    active,
    reason,
    isFallback: requested !== active,
    telemetry: `${feature}=${active} requested=${requested} reason=${reason}`
  };
}

export class CoreCutoverStore {
  private readonly requested = new Map<CoreFeature, CoreFeaturePath>();
  private readonly storage: Pick<Storage, 'getItem' | 'setItem'> | null;
  private readonly availability: CoreCutoverAvailability;

  constructor(options: CoreCutoverStoreOptions = {}) {
    this.storage = options.storage ?? null;
    this.availability = options.availability ?? DEFAULT_CORE_AVAILABILITY;
    const search = options.search ?? '';

    for (const feature of CORE_FEATURES) {
      const fromQuery = queryValue(search, feature);
      const stored = this.storage?.getItem(this.storageKey(feature)) ?? null;
      this.requested.set(feature, isFeaturePath(fromQuery) ? fromQuery : isFeaturePath(stored) ? stored : 'native');
    }
  }

  get(feature: CoreFeature): CoreFeatureSelection {
    return resolveCoreSelection(feature, this.requested.get(feature) ?? 'native', this.availability);
  }

  set(feature: CoreFeature, path: CoreFeaturePath): CoreFeatureSelection {
    this.requested.set(feature, path);
    this.storage?.setItem(this.storageKey(feature), path);
    return this.get(feature);
  }

  snapshot(): CoreFeatureSelection[] {
    return CORE_FEATURES.map((feature) => this.get(feature));
  }

  telemetry(): string {
    return this.snapshot().map((selection) => selection.telemetry).join(';');
  }

  private storageKey(feature: CoreFeature): string {
    return `airdesk.core.${feature}`;
  }
}
