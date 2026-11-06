export type CapabilityAvailability = 'available' | 'busy' | 'restricted' | 'unavailable';
export type CapabilityAuthorization = 'granted' | 'ungranted' | 'denied' | 'revoked';
export type CapabilityExecution = 'local' | 'remote' | 'streaming';
export type PlacementScope = 'local' | 'device' | 'runtime';

export interface CapabilityDescriptor {
  providerDeviceId: string;
  runtimeId: string;
  capUri: string;
  version: number;
  availability: CapabilityAvailability;
  authorization: CapabilityAuthorization;
  execution: CapabilityExecution;
  transport: string;
  latencyMs: number;
}

export interface PlacementRequest {
  capUri: string;
  version?: number;
  latencyBudgetMs?: number;
  transport?: string;
  placement?: PlacementScope;
  deviceId?: string;
  runtimeId?: string;
}

export type PlacementFailureCode =
  | 'unauthorized'
  | 'busy'
  | 'restricted'
  | 'unavailable'
  | 'version-mismatch'
  | 'transport-unavailable'
  | 'latency-budget'
  | 'placement-unavailable'
  | 'no-provider';

export interface PlacementDiagnostic {
  providerDeviceId: string;
  runtimeId: string;
  capUri: string;
  version: number;
  outcome: 'selected' | 'eligible' | PlacementFailureCode;
  reason: string;
}

export interface PlacementSuccess {
  ok: true;
  provider: CapabilityDescriptor;
  diagnostics: PlacementDiagnostic[];
}

export interface PlacementFailure {
  ok: false;
  code: PlacementFailureCode;
  message: string;
  diagnostics: PlacementDiagnostic[];
}

export type PlacementResult = PlacementSuccess | PlacementFailure;

const FAILURE_PRIORITY: readonly PlacementFailureCode[] = [
  'unauthorized',
  'version-mismatch',
  'transport-unavailable',
  'placement-unavailable',
  'latency-budget',
  'busy',
  'restricted',
  'unavailable'
];

function compareStrings(left: string, right: string): number {
  if (left === right) return 0;
  return left > right ? 1 : -1;
}

export function compareCapabilityDescriptors(
  left: CapabilityDescriptor,
  right: CapabilityDescriptor
): number {
  if (left.latencyMs !== right.latencyMs) return left.latencyMs - right.latencyMs;

  const deviceOrder = compareStrings(left.providerDeviceId, right.providerDeviceId);
  if (deviceOrder !== 0) return deviceOrder;

  const runtimeOrder = compareStrings(left.runtimeId, right.runtimeId);
  if (runtimeOrder !== 0) return runtimeOrder;

  if (left.version !== right.version) return right.version - left.version;

  const transportOrder = compareStrings(left.transport, right.transport);
  if (transportOrder !== 0) return transportOrder;

  return compareStrings(left.execution, right.execution);
}

function rejectionFor(
  descriptor: CapabilityDescriptor,
  request: PlacementRequest
): { code: PlacementFailureCode; reason: string } | null {
  if (descriptor.authorization !== 'granted') {
    return {
      code: 'unauthorized',
      reason: `authorization is ${descriptor.authorization}`
    };
  }
  if (request.version !== undefined && descriptor.version !== request.version) {
    return {
      code: 'version-mismatch',
      reason: `version ${descriptor.version} does not match required ${request.version}`
    };
  }
  if (request.transport !== undefined && descriptor.transport !== request.transport) {
    return {
      code: 'transport-unavailable',
      reason: `transport ${descriptor.transport} does not match ${request.transport}`
    };
  }
  if (request.placement === 'local' && descriptor.execution !== 'local') {
    return {
      code: 'placement-unavailable',
      reason: `execution ${descriptor.execution} is not local`
    };
  }
  if (
    request.placement === 'device' &&
    (request.deviceId === undefined || descriptor.providerDeviceId !== request.deviceId)
  ) {
    return {
      code: 'placement-unavailable',
      reason: `provider is not the requested device ${request.deviceId ?? '(missing)'}`
    };
  }
  if (
    request.placement === 'runtime' &&
    (request.runtimeId === undefined || descriptor.runtimeId !== request.runtimeId)
  ) {
    return {
      code: 'placement-unavailable',
      reason: `provider is not the requested runtime ${request.runtimeId ?? '(missing)'}`
    };
  }
  if (descriptor.availability === 'busy') {
    return { code: 'busy', reason: 'capability is temporarily busy' };
  }
  if (descriptor.availability === 'restricted') {
    return { code: 'restricted', reason: 'capability is restricted by policy' };
  }
  if (descriptor.availability === 'unavailable') {
    return { code: 'unavailable', reason: 'capability is unavailable' };
  }
  if (
    request.latencyBudgetMs !== undefined &&
    descriptor.latencyMs > request.latencyBudgetMs
  ) {
    return {
      code: 'latency-budget',
      reason: `latency ${descriptor.latencyMs}ms exceeds budget ${request.latencyBudgetMs}ms`
    };
  }
  return null;
}

function failureCode(codes: readonly PlacementFailureCode[]): PlacementFailureCode {
  for (const code of FAILURE_PRIORITY) {
    if (codes.includes(code)) return code;
  }
  return codes[0] ?? 'no-provider';
}

export function selectProvider(
  descriptors: readonly CapabilityDescriptor[],
  request: PlacementRequest
): PlacementResult {
  const matching = descriptors.filter((descriptor) => descriptor.capUri === request.capUri);
  if (matching.length === 0) {
    return {
      ok: false,
      code: 'no-provider',
      message: `No provider advertises ${request.capUri}.`,
      diagnostics: []
    };
  }

  const entries: Array<{
    descriptor: CapabilityDescriptor;
    outcome: 'eligible' | PlacementFailureCode;
    reason: string;
  }> = [];
  const failures: PlacementFailureCode[] = [];
  const eligible: CapabilityDescriptor[] = [];

  for (const descriptor of matching) {
    const rejection = rejectionFor(descriptor, request);
    if (rejection) {
      entries.push({ descriptor, outcome: rejection.code, reason: rejection.reason });
      failures.push(rejection.code);
    } else {
      entries.push({
        descriptor,
        outcome: 'eligible',
        reason: 'passes authorization, availability, version, transport, placement and latency filters'
      });
      eligible.push(descriptor);
    }
  }

  if (eligible.length === 0) {
    const code = failureCode(failures);
    return {
      ok: false,
      code,
      message: `No provider for ${request.capUri}: ${code}.`,
      diagnostics: entries.map((entry) => ({
        providerDeviceId: entry.descriptor.providerDeviceId,
        runtimeId: entry.descriptor.runtimeId,
        capUri: entry.descriptor.capUri,
        version: entry.descriptor.version,
        outcome: entry.outcome,
        reason: entry.reason
      }))
    };
  }

  const selected = [...eligible].sort(compareCapabilityDescriptors)[0];
  if (!selected) {
    return {
      ok: false,
      code: 'no-provider',
      message: `No provider for ${request.capUri}.`,
      diagnostics: []
    };
  }

  return {
    ok: true,
    provider: selected,
    diagnostics: entries.map((entry) => ({
      providerDeviceId: entry.descriptor.providerDeviceId,
      runtimeId: entry.descriptor.runtimeId,
      capUri: entry.descriptor.capUri,
      version: entry.descriptor.version,
      outcome: entry.descriptor === selected ? 'selected' : entry.outcome,
      reason:
        entry.descriptor === selected
          ? 'selected by deterministic latency, device, runtime, version, transport and execution ordering'
          : entry.reason
    }))
  };
}
