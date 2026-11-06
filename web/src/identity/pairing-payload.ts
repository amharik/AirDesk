import { base64UrlToBytes, randomNonce } from './encoding';
import type { NonceReplayGuard } from './replay';

export const ADFP_PROTOCOL = 'adfp';
export const ADFP_VERSION = '0.1';

export type PairingPayloadType = 'offer' | 'response';
export type PairingChannelBindingKind = 'exporter' | 'certificate-hash';

export interface PairingChannelBinding {
  kind: PairingChannelBindingKind;
  value: string;
}

export interface PairingPayload {
  protocol: typeof ADFP_PROTOCOL;
  version: string;
  type: PairingPayloadType;
  deviceId: string;
  publicKey: string;
  nonce: string;
  replyTo?: string;
  expiresAt: number;
  endpointHint?: string;
  relayHint?: string;
  capabilities: string[];
  channelBinding: PairingChannelBinding;
}

export type PairingValidationErrorCode =
  | 'malformed-json'
  | 'malformed-payload'
  | 'unknown-field'
  | 'unsupported-protocol'
  | 'unknown-major'
  | 'unsupported-version'
  | 'unexpected-type'
  | 'invalid-device-id'
  | 'invalid-public-key'
  | 'invalid-nonce'
  | 'invalid-expiry'
  | 'expired'
  | 'missing-binding'
  | 'unsupported-binding'
  | 'invalid-binding'
  | 'invalid-capabilities'
  | 'invalid-endpoint-hint'
  | 'invalid-relay-hint'
  | 'invalid-reply-to'
  | 'replayed-nonce'
  | 'revoked-device'
  | 'offer-nonce-mismatch'
  | 'channel-binding-mismatch'
  | 'transcript-mismatch'
  | 'invalid-pake-evidence'
  | 'invalid-state';

export class PairingValidationError extends Error {
  readonly code: PairingValidationErrorCode;

  constructor(code: PairingValidationErrorCode, message: string) {
    super(message);
    this.name = 'PairingValidationError';
    this.code = code;
  }
}

export interface PairingParseOptions {
  now?: number;
  expectedType?: PairingPayloadType;
  replayGuard?: NonceReplayGuard;
}

const DEVICE_ID_PATTERN = /^ad-device:[0-9a-f]{64}$/;
const VERSION_PATTERN = /^([0-9]+)\.([0-9]+)$/;
const MAX_HINT_LENGTH = 2048;
const MAX_CAPABILITIES = 64;
const MAX_CAPABILITY_LENGTH = 128;

const OFFER_FIELDS = new Set([
  'protocol',
  'version',
  'type',
  'deviceId',
  'publicKey',
  'nonce',
  'expiresAt',
  'endpointHint',
  'relayHint',
  'capabilities',
  'channelBinding'
]);

const RESPONSE_FIELDS = new Set([...OFFER_FIELDS, 'replyTo']);

function fail(code: PairingValidationErrorCode, message: string): never {
  throw new PairingValidationError(code, message);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOwn(record: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(record, key);
}

function checkFields(record: Record<string, unknown>, allowed: Set<string>): void {
  for (const key of Object.keys(record)) {
    if (!allowed.has(key)) fail('unknown-field', `unknown pairing field: ${key}`);
  }
}

function requiredString(
  record: Record<string, unknown>,
  key: string,
  code: PairingValidationErrorCode,
  maxLength: number
): string {
  const value = record[key];
  if (typeof value !== 'string' || value.length === 0 || value.length > maxLength) {
    fail(code, `invalid ${key}`);
  }
  return value;
}

function optionalHint(
  record: Record<string, unknown>,
  key: string,
  code: PairingValidationErrorCode
): string | undefined {
  if (!hasOwn(record, key)) return undefined;
  const value = record[key];
  if (typeof value !== 'string' || value.length === 0 || value.length > MAX_HINT_LENGTH) {
    fail(code, `invalid ${key}`);
  }
  return value;
}

function parseNonce(value: string, code: PairingValidationErrorCode): string {
  let bytes: Uint8Array;
  try {
    bytes = base64UrlToBytes(value);
  } catch {
    fail(code, 'invalid nonce encoding');
  }
  if (bytes.length < 16 || bytes.length > 128) fail(code, 'nonce length out of range');
  return value;
}

function parsePublicKey(value: string): string {
  let bytes: Uint8Array;
  try {
    bytes = base64UrlToBytes(value);
  } catch {
    fail('invalid-public-key', 'invalid public key encoding');
  }
  if (bytes.length < 32 || bytes.length > 1024) {
    fail('invalid-public-key', 'public key length out of range');
  }
  return value;
}

function parseCapabilities(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > MAX_CAPABILITIES) {
    fail('invalid-capabilities', 'invalid capabilities');
  }
  const seen = new Set<string>();
  const capabilities: string[] = [];
  for (const capability of value) {
    if (
      typeof capability !== 'string' ||
      capability.length === 0 ||
      capability.length > MAX_CAPABILITY_LENGTH
    ) {
      fail('invalid-capabilities', 'invalid capability');
    }
    if (seen.has(capability)) fail('invalid-capabilities', 'duplicate capability');
    seen.add(capability);
    capabilities.push(capability);
  }
  return capabilities;
}

function parseBinding(value: unknown): PairingChannelBinding {
  if (!isRecord(value)) fail('missing-binding', 'channel binding is required');
  checkFields(value, new Set(['kind', 'value']));

  const kind = value.kind;
  if (kind === undefined || kind === 'none') {
    fail('missing-binding', 'unbound pairing is not allowed');
  }
  if (kind !== 'exporter' && kind !== 'certificate-hash') {
    fail('unsupported-binding', 'unsupported channel binding');
  }

  const bindingValue = value.value;
  if (typeof bindingValue !== 'string' || bindingValue.length === 0 || bindingValue.length > 2048) {
    fail('invalid-binding', 'invalid channel binding value');
  }

  if (kind === 'certificate-hash') {
    if (!/^[0-9a-fA-F]{64}$/.test(bindingValue)) {
      fail('invalid-binding', 'invalid certificate hash');
    }
    return { kind, value: bindingValue.toLowerCase() };
  }

  try {
    if (base64UrlToBytes(bindingValue).length < 16) {
      fail('invalid-binding', 'exporter binding is too short');
    }
  } catch {
    fail('invalid-binding', 'invalid exporter binding');
  }
  return { kind, value: bindingValue };
}

export function validatePairingPayload(
  value: unknown,
  options: PairingParseOptions = {}
): PairingPayload {
  if (!isRecord(value)) fail('malformed-payload', 'pairing payload must be an object');

  const type = value.type;
  if (type !== 'offer' && type !== 'response') {
    fail('unexpected-type', 'pairing type must be offer or response');
  }
  if (options.expectedType && type !== options.expectedType) {
    fail('unexpected-type', `expected ${options.expectedType}`);
  }

  checkFields(value, type === 'offer' ? OFFER_FIELDS : RESPONSE_FIELDS);

  if (value.protocol !== ADFP_PROTOCOL) {
    fail('unsupported-protocol', 'unsupported pairing protocol');
  }

  const version = value.version;
  if (typeof version !== 'string') fail('unsupported-version', 'pairing version is required');
  const versionMatch = VERSION_PATTERN.exec(version);
  if (!versionMatch) fail('unsupported-version', 'invalid pairing version');
  if (Number(versionMatch[1]) !== 0) fail('unknown-major', 'unknown pairing major version');
  if (version !== ADFP_VERSION) fail('unsupported-version', 'unsupported pairing version');

  const deviceId = requiredString(value, 'deviceId', 'invalid-device-id', 128);
  if (!DEVICE_ID_PATTERN.test(deviceId)) fail('invalid-device-id', 'invalid device id');

  const publicKey = parsePublicKey(requiredString(value, 'publicKey', 'invalid-public-key', 2048));
  const nonce = parseNonce(requiredString(value, 'nonce', 'invalid-nonce', 256), 'invalid-nonce');

  let replyTo: string | undefined;
  if (type === 'response') {
    replyTo = parseNonce(
      requiredString(value, 'replyTo', 'invalid-reply-to', 256),
      'invalid-reply-to'
    );
  }

  const expiresAt = value.expiresAt;
  if (!Number.isSafeInteger(expiresAt) || (expiresAt as number) <= 0) {
    fail('invalid-expiry', 'invalid pairing expiry');
  }
  const now = options.now ?? Date.now();
  if ((expiresAt as number) <= now) fail('expired', 'pairing payload has expired');

  const endpointHint = optionalHint(value, 'endpointHint', 'invalid-endpoint-hint');
  const relayHint = optionalHint(value, 'relayHint', 'invalid-relay-hint');
  const capabilities = parseCapabilities(value.capabilities);
  const channelBinding = parseBinding(value.channelBinding);

  if (options.replayGuard) {
    options.replayGuard.consume(nonce, expiresAt as number);
  }

  const payload: PairingPayload = {
    protocol: ADFP_PROTOCOL,
    version,
    type,
    deviceId,
    publicKey,
    nonce,
    expiresAt: expiresAt as number,
    capabilities,
    channelBinding
  };
  if (replyTo) payload.replyTo = replyTo;
  if (endpointHint) payload.endpointHint = endpointHint;
  if (relayHint) payload.relayHint = relayHint;
  return payload;
}

export function parsePairingJson(raw: string, options: PairingParseOptions = {}): PairingPayload {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    fail('malformed-json', 'pairing payload is not valid JSON');
  }
  return validatePairingPayload(value, options);
}

export interface CreatePairingPayloadInput {
  type: PairingPayloadType;
  deviceId: string;
  publicKey: string;
  channelBinding: PairingChannelBinding;
  capabilities?: readonly string[];
  nonce?: string;
  replyTo?: string;
  expiresAt?: number;
  ttlMs?: number;
  now?: number;
  endpointHint?: string;
  relayHint?: string;
  cryptoSource?: Crypto;
}

export function createPairingPayload(input: CreatePairingPayloadInput): PairingPayload {
  const now = input.now ?? Date.now();
  const expiresAt = input.expiresAt ?? now + (input.ttlMs ?? 120_000);
  const payload: PairingPayload = {
    protocol: ADFP_PROTOCOL,
    version: ADFP_VERSION,
    type: input.type,
    deviceId: input.deviceId,
    publicKey: input.publicKey,
    nonce: input.nonce ?? randomNonce(input.cryptoSource),
    expiresAt,
    capabilities: [...(input.capabilities ?? [])],
    channelBinding: { ...input.channelBinding }
  };
  if (input.replyTo) payload.replyTo = input.replyTo;
  if (input.endpointHint) payload.endpointHint = input.endpointHint;
  if (input.relayHint) payload.relayHint = input.relayHint;
  return payload;
}

export function serializePairingPayload(payload: PairingPayload): string {
  return JSON.stringify(payload);
}
