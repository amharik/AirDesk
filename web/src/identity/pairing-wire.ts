import { base64ToBytes, bytesToBase64 } from './encoding';

export const PAIRING_WIRE_PROTOCOL = 'adpair-wire';
export const PAIRING_WIRE_VERSION = 1;
const MAX_PAYLOAD_BYTES = 1_048_576;

export type PairingWireKind =
  | 'response'
  | 'share'
  | 'verifier-response'
  | 'initiator-finish'
  | 'responder-finish';

export interface PairingWireMessage {
  readonly protocol: typeof PAIRING_WIRE_PROTOCOL;
  readonly version: typeof PAIRING_WIRE_VERSION;
  readonly kind: PairingWireKind;
  readonly response?: Uint8Array;
  readonly share?: Uint8Array;
  readonly confirmation?: Uint8Array;
  readonly signature?: Uint8Array;
}

export type PairingWireErrorCode =
  | 'malformed'
  | 'unsupported-protocol'
  | 'unsupported-version'
  | 'invalid-payload';

export class PairingWireError extends Error {
  readonly code: PairingWireErrorCode;

  constructor(code: PairingWireErrorCode, message: string) {
    super(message);
    this.name = 'PairingWireError';
    this.code = code;
  }
}

function validatePayload(bytes: Uint8Array | undefined, name: string): Uint8Array {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0 || bytes.length > MAX_PAYLOAD_BYTES) {
    throw new PairingWireError('invalid-payload', `Invalid pairing wire payload: ${name}.`);
  }
  return bytes;
}

function message(
  kind: PairingWireKind,
  payload: {
    response?: Uint8Array;
    share?: Uint8Array;
    confirmation?: Uint8Array;
    signature?: Uint8Array;
  }
): PairingWireMessage {
  const result: PairingWireMessage = {
    protocol: PAIRING_WIRE_PROTOCOL,
    version: PAIRING_WIRE_VERSION,
    kind,
    ...payload
  };
  validateMessage(result);
  return result;
}

export function pairingWireResponse(response: Uint8Array): PairingWireMessage {
  return message('response', { response });
}

export function pairingWireShare(share: Uint8Array): PairingWireMessage {
  return message('share', { share });
}

export function pairingWireVerifierResponse(
  share: Uint8Array,
  confirmation: Uint8Array,
  signature: Uint8Array
): PairingWireMessage {
  return message('verifier-response', { share, confirmation, signature });
}

export function pairingWireInitiatorFinish(
  confirmation: Uint8Array,
  signature: Uint8Array
): PairingWireMessage {
  return message('initiator-finish', { confirmation, signature });
}

export function pairingWireResponderFinish(
  confirmation: Uint8Array,
  signature: Uint8Array
): PairingWireMessage {
  return message('responder-finish', { confirmation, signature });
}

function validateMessage(value: PairingWireMessage): void {
  if (value.protocol !== PAIRING_WIRE_PROTOCOL) {
    throw new PairingWireError('unsupported-protocol', 'Unsupported pairing message protocol.');
  }
  if (value.version !== PAIRING_WIRE_VERSION) {
    throw new PairingWireError('unsupported-version', 'Unsupported pairing message version.');
  }
  switch (value.kind) {
    case 'response':
      requireOnly(value, ['response']);
      break;
    case 'share':
      requireOnly(value, ['share']);
      break;
    case 'verifier-response':
      requireOnly(value, ['share', 'confirmation', 'signature']);
      break;
    case 'initiator-finish':
    case 'responder-finish':
      requireOnly(value, ['confirmation', 'signature']);
      break;
    default:
      throw new PairingWireError('invalid-payload', `Invalid pairing wire kind: ${String(value.kind)}.`);
  }
}

function requireOnly(value: PairingWireMessage, names: readonly string[]): void {
  const allowed = new Set(names);
  for (const name of ['response', 'share', 'confirmation', 'signature'] as const) {
    if (allowed.has(name)) {
      validatePayload(value[name], name);
    } else if (value[name] !== undefined) {
      throw new PairingWireError('invalid-payload', `Invalid pairing wire message: ${value.kind}.`);
    }
  }
}

export function encodePairingWireMessage(value: PairingWireMessage): Uint8Array {
  validateMessage(value);
  const encoded: Record<string, string | number> = {
    protocol: value.protocol,
    version: value.version,
    kind: value.kind
  };
  for (const name of ['response', 'share', 'confirmation', 'signature'] as const) {
    const payload = value[name];
    if (payload !== undefined) encoded[name] = bytesToBase64(payload);
  }
  return new TextEncoder().encode(JSON.stringify(encoded));
}

export function decodePairingWireMessage(serialized: string | Uint8Array): PairingWireMessage {
  let parsed: unknown;
  try {
    const text = typeof serialized === 'string' ? serialized : new TextDecoder().decode(serialized);
    parsed = JSON.parse(text);
  } catch {
    throw new PairingWireError('malformed', 'Pairing message is malformed.');
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new PairingWireError('malformed', 'Pairing message is malformed.');
  }
  const record = parsed as Record<string, unknown>;
  if (typeof record.protocol !== 'string') {
    throw new PairingWireError('malformed', 'Pairing message is malformed.');
  }
  if (record.protocol !== PAIRING_WIRE_PROTOCOL) {
    throw new PairingWireError('unsupported-protocol', 'Unsupported pairing message protocol.');
  }
  if (record.version !== PAIRING_WIRE_VERSION) {
    throw new PairingWireError('unsupported-version', 'Unsupported pairing message version.');
  }
  if (typeof record.kind !== 'string') {
    throw new PairingWireError('malformed', 'Pairing message is malformed.');
  }
  const payload: {
    response?: Uint8Array;
    share?: Uint8Array;
    confirmation?: Uint8Array;
    signature?: Uint8Array;
  } = {};
  for (const name of ['response', 'share', 'confirmation', 'signature'] as const) {
    const value = record[name];
    if (value === undefined) continue;
    if (typeof value !== 'string') {
      throw new PairingWireError('invalid-payload', `Invalid pairing wire payload: ${name}.`);
    }
    try {
      payload[name] = base64ToBytes(value);
    } catch {
      throw new PairingWireError('invalid-payload', `Invalid pairing wire payload: ${name}.`);
    }
  }
  const result: PairingWireMessage = {
    protocol: PAIRING_WIRE_PROTOCOL,
    version: PAIRING_WIRE_VERSION,
    kind: record.kind as PairingWireKind,
    ...payload
  };
  validateMessage(result);
  return result;
}
