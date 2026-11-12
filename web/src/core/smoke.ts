export interface CoreSmokeModule {
  coreAbiVersion(): number;
  coreIsAbiCompatible(required: number): boolean;
  coreSmokeLabel(): string;
}

export interface CoreSmokeResult {
  label: string;
  abiVersion: number;
  compatible: boolean;
}

export type CoreSmokeLoader = () => Promise<CoreSmokeModule>;

export const defaultCoreSmokeModuleURL = '/core/airdesk_wasm.js';

export function isCoreSmokeEnabled(search: string = globalThis.location?.search ?? ''): boolean {
  return new URLSearchParams(search).get('coreSmoke') === '1';
}

export function createCoreSmokeLoader(moduleURL = defaultCoreSmokeModuleURL): CoreSmokeLoader {
  return async () => {
    const module = (await import(/* @vite-ignore */ moduleURL)) as CoreSmokeModule & {
      default?: () => Promise<unknown>;
    };
    if (typeof module.default === 'function') {
      await module.default();
    }
    return module;
  };
}

export async function loadCoreSmoke(
  enabled = isCoreSmokeEnabled(),
  loader: CoreSmokeLoader = createCoreSmokeLoader()
): Promise<CoreSmokeResult | null> {
  if (!enabled) return null;
  const module = await loader();
  const abiVersion = module.coreAbiVersion();
  return {
    label: module.coreSmokeLabel(),
    abiVersion,
    compatible: module.coreIsAbiCompatible(abiVersion)
  };
}
