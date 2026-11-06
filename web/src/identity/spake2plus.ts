import { p256 } from '@noble/curves/nist.js';
import {
  asBufferSource,
  bytesEqual,
  bytesToHex,
  concatBytes,
  hexToBytes,
  randomBytes,
  sha256,
  utf8
} from './encoding';

export const SPAKE2PLUS_P256_SUITE =
  'SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256' as const;

export const SPAKE2PLUS_P256_M_COMPRESSED_HEX =
  '02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f';
export const SPAKE2PLUS_P256_N_COMPRESSED_HEX =
  '03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49';

export const SPAKE2PLUS_P256_M = hexToBytes(SPAKE2PLUS_P256_M_COMPRESSED_HEX);
export const SPAKE2PLUS_P256_N = hexToBytes(SPAKE2PLUS_P256_N_COMPRESSED_HEX);

export type Spake2PlusErrorCode =
  | 'invalid-input'
  | 'invalid-length'
  | 'invalid-point'
  | 'identity-point'
  | 'non-subgroup-point'
  | 'invalid-scalar'
  | 'confirmation-mismatch';

export class Spake2PlusError extends Error {
  constructor(
    readonly code: Spake2PlusErrorCode,
    message: string
  ) {
    super(message);
    this.name = 'Spake2PlusError';
  }
}

export type Spake2PlusBytes = Uint8Array | string;
export type P256Point = InstanceType<typeof p256.Point>;

const POINT_BYTES = 65;
const SCALAR_BYTES = 32;
const CONFIRMATION_BYTES = 32;
const P256_ORDER = p256.Point.CURVE().n;
const M_POINT = p256.Point.fromHex(SPAKE2PLUS_P256_M_COMPRESSED_HEX);
const N_POINT = p256.Point.fromHex(SPAKE2PLUS_P256_N_COMPRESSED_HEX);

function inputBytes(value: Spake2PlusBytes, name: string): Uint8Array {
  if (typeof value === 'string') return utf8(value);
  if (value instanceof Uint8Array) return new Uint8Array(value);
  throw new Spake2PlusError('invalid-input', `${name} must be bytes or a string`);
}

function scalarBytes(value: Spake2PlusBytes, name: string): Uint8Array {
  const bytes = inputBytes(value, name);
  if (bytes.length !== SCALAR_BYTES) {
    throw new Spake2PlusError('invalid-length', `${name} must be 32 bytes`);
  }
  return bytes;
}

function scalarValue(bytes: Uint8Array): bigint {
  return BigInt(`0x${bytesToHex(bytes)}`);
}

function ephemeralScalarBytes(value: Spake2PlusBytes | undefined, name: string): Uint8Array {
  if (value === undefined) {
    for (;;) {
      const candidate = randomBytes(SCALAR_BYTES);
      const scalar = scalarValue(candidate);
      if (scalar > 0n && scalar < P256_ORDER) return candidate;
    }
  }
  const bytes = scalarBytes(value, name);
  const scalar = scalarValue(bytes);
  if (scalar === 0n || scalar >= P256_ORDER) {
    throw new Spake2PlusError(
      'invalid-scalar',
      `${name} must be in the range [1, n-1]`
    );
  }
  return bytes;
}

function multiplyPoint(point: P256Point, scalar: bigint): P256Point {
  const reduced = scalar % P256_ORDER;
  if (reduced === 0n) return p256.Point.ZERO;
  return point.multiply(reduced);
}

function decodePoint(value: Spake2PlusBytes, name: string): P256Point {
  const bytes = inputBytes(value, name);
  if (bytes.length === 1 && bytes[0] === 0x00) {
    throw new Spake2PlusError('identity-point', `${name} is the identity point`);
  }
  if (bytes.length !== POINT_BYTES || bytes[0] !== 0x04) {
    throw new Spake2PlusError(
      'invalid-length',
      `${name} must be an uncompressed SEC1 P-256 point`
    );
  }
  let point: P256Point;
  try {
    point = p256.Point.fromBytes(bytes);
  } catch {
    throw new Spake2PlusError('invalid-point', `${name} is not a valid P-256 point`);
  }
  if (point.is0()) {
    throw new Spake2PlusError('identity-point', `${name} is the identity point`);
  }
  if (!point.isTorsionFree()) {
    throw new Spake2PlusError(
      'non-subgroup-point',
      `${name} is not in the prime-order subgroup`
    );
  }
  return point;
}

function encodePoint(point: P256Point, name: string): Uint8Array {
  if (point.is0()) {
    throw new Spake2PlusError('identity-point', `${name} is the identity point`);
  }
  try {
    return point.toBytes(false);
  } catch {
    throw new Spake2PlusError('invalid-point', `${name} is not a valid P-256 point`);
  }
}

function lengthPrefix(length: number): Uint8Array {
  if (!Number.isSafeInteger(length) || length < 0) {
    throw new Spake2PlusError('invalid-length', 'transcript component length is invalid');
  }
  const prefix = new Uint8Array(8);
  let remaining = BigInt(length);
  for (let index = 0; index < prefix.length; index += 1) {
    prefix[index] = Number(remaining & 0xffn);
    remaining >>= 8n;
  }
  return prefix;
}

function lengthPrefixed(value: Uint8Array): Uint8Array {
  return concatBytes(lengthPrefix(value.length), value);
}

export interface Spake2PlusTranscriptInput {
  context: Spake2PlusBytes;
  idProver: Spake2PlusBytes;
  idVerifier: Spake2PlusBytes;
  shareP: Spake2PlusBytes;
  shareV: Spake2PlusBytes;
  z: Spake2PlusBytes;
  v: Spake2PlusBytes;
  w0: Spake2PlusBytes;
}

export function computeSpake2PlusTranscript(
  input: Spake2PlusTranscriptInput
): Uint8Array {
  const context = inputBytes(input.context, 'context');
  const idProver = inputBytes(input.idProver, 'idProver');
  const idVerifier = inputBytes(input.idVerifier, 'idVerifier');
  const shareP = encodePoint(decodePoint(input.shareP, 'shareP'), 'shareP');
  const shareV = encodePoint(decodePoint(input.shareV, 'shareV'), 'shareV');
  const z = encodePoint(decodePoint(input.z, 'Z'), 'Z');
  const v = encodePoint(decodePoint(input.v, 'V'), 'V');
  const w0 = scalarBytes(input.w0, 'w0');

  return concatBytes(
    lengthPrefixed(context),
    lengthPrefixed(idProver),
    lengthPrefixed(idVerifier),
    lengthPrefixed(encodePoint(M_POINT, 'M')),
    lengthPrefixed(encodePoint(N_POINT, 'N')),
    lengthPrefixed(shareP),
    lengthPrefixed(shareV),
    lengthPrefixed(z),
    lengthPrefixed(v),
    lengthPrefixed(w0)
  );
}

export interface Spake2PlusKeys {
  readonly kMain: Uint8Array;
  readonly kConfirmP: Uint8Array;
  readonly kConfirmV: Uint8Array;
  readonly kShared: Uint8Array;
}

async function hkdfSha256(
  ikm: Uint8Array,
  info: string,
  length: number,
  subtle: SubtleCrypto
): Promise<Uint8Array> {
  const key = await subtle.importKey('raw', asBufferSource(ikm), 'HKDF', false, [
    'deriveBits'
  ]);
  const bits = await subtle.deriveBits(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: asBufferSource(new Uint8Array(0)),
      info: asBufferSource(utf8(info))
    },
    key,
    length * 8
  );
  return new Uint8Array(bits);
}

async function hmacSha256(
  key: Uint8Array,
  message: Uint8Array,
  subtle: SubtleCrypto
): Promise<Uint8Array> {
  const handle = await subtle.importKey(
    'raw',
    asBufferSource(key),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  return new Uint8Array(
    await subtle.sign('HMAC', handle, asBufferSource(message))
  );
}

export async function deriveSpake2PlusKeys(
  transcript: Uint8Array,
  subtle: SubtleCrypto = crypto.subtle
): Promise<Spake2PlusKeys> {
  const kMain = await sha256(transcript, subtle);
  const confirmationKeys = await hkdfSha256(
    kMain,
    'ConfirmationKeys',
    CONFIRMATION_BYTES * 2,
    subtle
  );
  const kShared = await hkdfSha256(kMain, 'SharedKey', 32, subtle);
  return {
    kMain,
    kConfirmP: confirmationKeys.slice(0, CONFIRMATION_BYTES),
    kConfirmV: confirmationKeys.slice(CONFIRMATION_BYTES),
    kShared
  };
}

export interface Spake2PlusConfirmationInput {
  keys: Spake2PlusKeys;
  shareP: Spake2PlusBytes;
  shareV: Spake2PlusBytes;
  subtle?: SubtleCrypto;
}

export interface Spake2PlusConfirmations {
  readonly confirmP: Uint8Array;
  readonly confirmV: Uint8Array;
}

export async function computeSpake2PlusConfirmations(
  input: Spake2PlusConfirmationInput
): Promise<Spake2PlusConfirmations> {
  const subtle = input.subtle ?? crypto.subtle;
  const shareP = encodePoint(decodePoint(input.shareP, 'shareP'), 'shareP');
  const shareV = encodePoint(decodePoint(input.shareV, 'shareV'), 'shareV');
  return {
    confirmP: await hmacSha256(input.keys.kConfirmP, shareV, subtle),
    confirmV: await hmacSha256(input.keys.kConfirmV, shareP, subtle)
  };
}

export function assertSpake2PlusConfirmation(
  expected: Uint8Array,
  received: Uint8Array
): void {
  if (
    expected.length !== CONFIRMATION_BYTES ||
    received.length !== CONFIRMATION_BYTES
  ) {
    throw new Spake2PlusError(
      'invalid-length',
      'confirmation must be 32 bytes'
    );
  }
  if (!bytesEqual(expected, received)) {
    throw new Spake2PlusError('confirmation-mismatch', 'confirmation mismatch');
  }
}

export function computeSpake2PlusRegistrationRecord(
  w1: Spake2PlusBytes
): Uint8Array {
  const w1Bytes = scalarBytes(w1, 'w1');
  const w1Value = scalarValue(w1Bytes) % P256_ORDER;
  if (w1Value === 0n) {
    throw new Spake2PlusError('invalid-scalar', 'w1 must not be zero modulo n');
  }
  return encodePoint(p256.Point.BASE.multiply(w1Value), 'L');
}

export interface Spake2PlusProverInitInput {
  w0: Spake2PlusBytes;
  x?: Spake2PlusBytes;
}

export interface Spake2PlusProverInitResult {
  readonly x: Uint8Array;
  readonly shareP: Uint8Array;
}

export function spake2PlusProverInit(
  input: Spake2PlusProverInitInput
): Spake2PlusProverInitResult {
  const w0Bytes = scalarBytes(input.w0, 'w0');
  const w0 = scalarValue(w0Bytes);
  const xBytes = ephemeralScalarBytes(input.x, 'x');
  const x = scalarValue(xBytes);
  const shareP = p256.Point.BASE.multiply(x).add(multiplyPoint(M_POINT, w0));
  return {
    x: new Uint8Array(xBytes),
    shareP: encodePoint(shareP, 'shareP')
  };
}

export interface Spake2PlusProverFinishInput {
  w0: Spake2PlusBytes;
  w1: Spake2PlusBytes;
  x: Spake2PlusBytes;
  shareV: Spake2PlusBytes;
  context: Spake2PlusBytes;
  idProver: Spake2PlusBytes;
  idVerifier: Spake2PlusBytes;
  subtle?: SubtleCrypto;
}

export interface Spake2PlusFinishResult {
  readonly shareP: Uint8Array;
  readonly shareV: Uint8Array;
  readonly z: Uint8Array;
  readonly v: Uint8Array;
  readonly transcript: Uint8Array;
  readonly keys: Spake2PlusKeys;
  readonly confirmation: Uint8Array;
  readonly expectedConfirmation: Uint8Array;
}

export async function spake2PlusProverFinish(
  input: Spake2PlusProverFinishInput
): Promise<Spake2PlusFinishResult> {
  const subtle = input.subtle ?? crypto.subtle;
  const w0Bytes = scalarBytes(input.w0, 'w0');
  const w1Bytes = scalarBytes(input.w1, 'w1');
  const xBytes = ephemeralScalarBytes(input.x, 'x');
  const w0 = scalarValue(w0Bytes);
  const w1 = scalarValue(w1Bytes);
  const x = scalarValue(xBytes);

  const shareVPoint = decodePoint(input.shareV, 'shareV');
  const sharePPoint = p256.Point.BASE.multiply(x).add(multiplyPoint(M_POINT, w0));
  const shareP = encodePoint(sharePPoint, 'shareP');
  const shareV = encodePoint(shareVPoint, 'shareV');

  const unblindedShareV = shareVPoint.subtract(multiplyPoint(N_POINT, w0));
  if (unblindedShareV.is0()) {
    throw new Spake2PlusError(
      'identity-point',
      'shareV unblinds to the identity point'
    );
  }
  const zPoint = multiplyPoint(unblindedShareV, x);
  const vPoint = multiplyPoint(unblindedShareV, w1);
  const z = encodePoint(zPoint, 'Z');
  const v = encodePoint(vPoint, 'V');

  const transcript = computeSpake2PlusTranscript({
    context: input.context,
    idProver: input.idProver,
    idVerifier: input.idVerifier,
    shareP,
    shareV,
    z,
    v,
    w0: w0Bytes
  });
  const keys = await deriveSpake2PlusKeys(transcript, subtle);
  const confirmations = await computeSpake2PlusConfirmations({
    keys,
    shareP,
    shareV,
    subtle
  });

  return {
    shareP,
    shareV,
    z,
    v,
    transcript,
    keys,
    confirmation: confirmations.confirmP,
    expectedConfirmation: confirmations.confirmV
  };
}

export interface Spake2PlusVerifierFinishInput {
  w0: Spake2PlusBytes;
  L: Spake2PlusBytes;
  shareP: Spake2PlusBytes;
  context: Spake2PlusBytes;
  idProver: Spake2PlusBytes;
  idVerifier: Spake2PlusBytes;
  y?: Spake2PlusBytes;
  subtle?: SubtleCrypto;
}

export interface Spake2PlusVerifierFinishResult extends Spake2PlusFinishResult {
  readonly y: Uint8Array;
}

export async function spake2PlusVerifierFinish(
  input: Spake2PlusVerifierFinishInput
): Promise<Spake2PlusVerifierFinishResult> {
  const subtle = input.subtle ?? crypto.subtle;
  const w0Bytes = scalarBytes(input.w0, 'w0');
  const w0 = scalarValue(w0Bytes);
  const yBytes = ephemeralScalarBytes(input.y, 'y');
  const y = scalarValue(yBytes);

  const LPoint = decodePoint(input.L, 'L');
  const sharePPoint = decodePoint(input.shareP, 'shareP');
  const shareP = encodePoint(sharePPoint, 'shareP');
  const shareVPoint = p256.Point.BASE.multiply(y).add(multiplyPoint(N_POINT, w0));
  const shareV = encodePoint(shareVPoint, 'shareV');

  const unblindedShareP = sharePPoint.subtract(multiplyPoint(M_POINT, w0));
  if (unblindedShareP.is0()) {
    throw new Spake2PlusError(
      'identity-point',
      'shareP unblinds to the identity point'
    );
  }
  const zPoint = multiplyPoint(unblindedShareP, y);
  const vPoint = multiplyPoint(LPoint, y);
  const z = encodePoint(zPoint, 'Z');
  const v = encodePoint(vPoint, 'V');

  const transcript = computeSpake2PlusTranscript({
    context: input.context,
    idProver: input.idProver,
    idVerifier: input.idVerifier,
    shareP,
    shareV,
    z,
    v,
    w0: w0Bytes
  });
  const keys = await deriveSpake2PlusKeys(transcript, subtle);
  const confirmations = await computeSpake2PlusConfirmations({
    keys,
    shareP,
    shareV,
    subtle
  });

  return {
    y: new Uint8Array(yBytes),
    shareP,
    shareV,
    z,
    v,
    transcript,
    keys,
    confirmation: confirmations.confirmV,
    expectedConfirmation: confirmations.confirmP
  };
}
