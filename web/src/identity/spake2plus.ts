import { p256 } from '@noble/curves/nist.js';
import { scryptAsync } from '@noble/hashes/scrypt.js';
import {
  asBufferSource,
  bytesEqual,
  bytesToBase64Url,
  bytesToHex,
  concatBytes,
  hexToBytes,
  randomBytes,
  sha256,
  utf8
} from './encoding';
import type { Spake2PlusExchangeResult } from './pake';

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
  | 'confirmation-mismatch'
  | 'invalid-state';

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

function registrationScalar(
  value: Spake2PlusBytes,
  name: string,
  allowZero: boolean
): { bytes: Uint8Array; scalar: bigint } {
  const bytes = scalarBytes(value, name);
  const scalar = scalarValue(bytes);
  if (scalar >= P256_ORDER || (!allowZero && scalar === 0n)) {
    const range = allowZero ? '[0, n-1]' : '[1, n-1]';
    throw new Spake2PlusError(
      'invalid-scalar',
      `${name} must be in the range ${range}`
    );
  }
  return { bytes, scalar };
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
  const w0 = registrationScalar(input.w0, 'w0', true).bytes;

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
  const { scalar: w1Value } = registrationScalar(w1, 'w1', false);
  return encodePoint(p256.Point.BASE.multiply(w1Value), 'L');
}

export const SPAKE2PLUS_P256_PBKDF_PROFILE = Object.freeze({
  name: 'scrypt',
  N: 32768,
  r: 8,
  p: 1,
  dkLen: 80
} as const);

export interface Spake2PlusPasswordInput {
  password: string | Uint8Array;
  salt: Spake2PlusBytes;
  idProver?: Spake2PlusBytes;
  idVerifier?: Spake2PlusBytes;
}

export interface Spake2PlusPasswordScalars {
  readonly w0: Uint8Array;
  readonly w1: Uint8Array;
}

export interface Spake2PlusPasswordRegistration extends Spake2PlusPasswordScalars {
  readonly salt: Uint8Array;
  readonly L: Uint8Array;
  readonly profile: typeof SPAKE2PLUS_P256_PBKDF_PROFILE;
}

export function createSpake2PlusPasswordSalt(source?: Crypto): Uint8Array {
  return randomBytes(32, source);
}

function passwordBytes(password: string | Uint8Array): Uint8Array {
  if (typeof password === 'string') {
    const normalized = password.normalize('NFKC');
    if (normalized.length === 0) {
      throw new Spake2PlusError('invalid-input', 'password must not be empty');
    }
    return utf8(normalized);
  }
  if (password instanceof Uint8Array) {
    if (password.length === 0) {
      throw new Spake2PlusError('invalid-input', 'password must not be empty');
    }
    return new Uint8Array(password);
  }
  throw new Spake2PlusError('invalid-input', 'password must be a string or bytes');
}

function passwordSalt(value: Spake2PlusBytes): Uint8Array {
  const salt = inputBytes(value, 'salt');
  if (salt.length < 16 || salt.length > 64) {
    throw new Spake2PlusError('invalid-length', 'salt must be 16 to 64 bytes');
  }
  return salt;
}

function wideScalar(bytes: Uint8Array): Uint8Array {
  const reduced = BigInt(`0x${bytesToHex(bytes)}`) % P256_ORDER;
  const result = new Uint8Array(SCALAR_BYTES);
  let value = reduced;
  for (let index = SCALAR_BYTES - 1; index >= 0; index -= 1) {
    result[index] = Number(value & 0xffn);
    value >>= 8n;
  }
  return result;
}

export function canonicalSpake2PlusPasswordMaterial(
  input: Spake2PlusPasswordInput
): Uint8Array {
  return concatBytes(
    lengthPrefixed(passwordBytes(input.password)),
    lengthPrefixed(inputBytes(input.idProver ?? new Uint8Array(0), 'idProver')),
    lengthPrefixed(inputBytes(input.idVerifier ?? new Uint8Array(0), 'idVerifier'))
  );
}

export async function deriveSpake2PlusPasswordScalars(
  input: Spake2PlusPasswordInput
): Promise<Spake2PlusPasswordScalars> {
  const material = canonicalSpake2PlusPasswordMaterial(input);
  const salt = passwordSalt(input.salt);
  const output = await scryptAsync(material, salt, SPAKE2PLUS_P256_PBKDF_PROFILE);
  if (output.length !== SPAKE2PLUS_P256_PBKDF_PROFILE.dkLen) {
    throw new Spake2PlusError('invalid-length', 'PBKDF output length mismatch');
  }

  const half = SPAKE2PLUS_P256_PBKDF_PROFILE.dkLen / 2;
  const w0 = wideScalar(output.subarray(0, half));
  const w1 = wideScalar(output.subarray(half));
  if (registrationScalar(w1, 'w1', false).scalar === 0n) {
    throw new Spake2PlusError('invalid-scalar', 'derived w1 must not be zero');
  }
  return { w0, w1 };
}

export async function createSpake2PlusPasswordRegistration(
  input: Omit<Spake2PlusPasswordInput, 'salt'> & { salt?: Spake2PlusBytes }
): Promise<Spake2PlusPasswordRegistration> {
  const salt = input.salt === undefined
    ? createSpake2PlusPasswordSalt()
    : inputBytes(input.salt, 'salt');
  const { w0, w1 } = await deriveSpake2PlusPasswordScalars({ ...input, salt });
  return {
    w0,
    w1,
    salt: new Uint8Array(salt),
    L: computeSpake2PlusRegistrationRecord(w1),
    profile: SPAKE2PLUS_P256_PBKDF_PROFILE
  };
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
  const { scalar: w0 } = registrationScalar(input.w0, 'w0', true);
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
  const w0Bytes = registrationScalar(input.w0, 'w0', true).bytes;
  const w1Bytes = registrationScalar(input.w1, 'w1', false).bytes;
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
  const w0Bytes = registrationScalar(input.w0, 'w0', true).bytes;
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

export type Spake2PlusRole = 'prover' | 'verifier';

export interface Spake2PlusSessionOptions {
  role: Spake2PlusRole;
  context: Spake2PlusBytes;
  idProver: Spake2PlusBytes;
  idVerifier: Spake2PlusBytes;
  w0: Spake2PlusBytes;
  w1?: Spake2PlusBytes;
  L?: Spake2PlusBytes;
  x?: Spake2PlusBytes;
  y?: Spake2PlusBytes;
  subtle?: SubtleCrypto;
}

export interface Spake2PlusVerifierResponse {
  readonly share: Uint8Array;
  readonly confirmation: Uint8Array;
}

export interface Spake2PlusSessionResult {
  readonly exchange: Spake2PlusExchangeResult;
  readonly transcript: Uint8Array;
  readonly keys: Spake2PlusKeys;
  readonly confirmation: Uint8Array;
  readonly expectedConfirmation: Uint8Array;
}

type Spake2PlusSessionPhase =
  | 'initial'
  | 'awaiting-share'
  | 'awaiting-confirmation'
  | 'completed';

function sessionError(message: string): Spake2PlusError {
  return new Spake2PlusError('invalid-state', message);
}

function finishResult(
  result: Spake2PlusFinishResult,
  confirmationP: Uint8Array,
  confirmationV: Uint8Array
): Spake2PlusSessionResult {
  return {
    exchange: {
      initiatorShare: bytesToBase64Url(result.shareP),
      responderShare: bytesToBase64Url(result.shareV),
      initiatorConfirmation: bytesToBase64Url(confirmationP),
      responderConfirmation: bytesToBase64Url(confirmationV),
      sharedSecret: bytesToBase64Url(result.keys.kShared)
    },
    transcript: new Uint8Array(result.transcript),
    keys: result.keys,
    confirmation: new Uint8Array(result.confirmation),
    expectedConfirmation: new Uint8Array(result.expectedConfirmation)
  };
}

export class Spake2PlusSession {
  readonly role: Spake2PlusRole;

  private readonly options: Spake2PlusSessionOptions;
  private phase: Spake2PlusSessionPhase = 'initial';
  private proverInit: Spake2PlusProverInitResult | null = null;
  private verifierPending: Spake2PlusVerifierFinishResult | null = null;

  constructor(options: Spake2PlusSessionOptions) {
    this.options = options;
    this.role = options.role;
  }

  proverStart(): Uint8Array {
    if (this.role !== 'prover') {
      throw sessionError('only the prover starts the exchange');
    }
    if (this.phase !== 'initial') {
      throw sessionError('prover exchange already started');
    }
    const start = spake2PlusProverInit({
      w0: this.options.w0,
      ...(this.options.x !== undefined ? { x: this.options.x } : {})
    });
    this.proverInit = start;
    this.phase = 'awaiting-share';
    return new Uint8Array(start.shareP);
  }

  async verifierRespond(shareP: Spake2PlusBytes): Promise<Spake2PlusVerifierResponse> {
    if (this.role !== 'verifier') {
      throw sessionError('only the verifier responds to a prover share');
    }
    if (this.phase !== 'initial') {
      throw sessionError('verifier response already produced');
    }
    if (this.options.L === undefined) {
      throw new Spake2PlusError('invalid-input', 'verifier registration record L is required');
    }
    const result = await spake2PlusVerifierFinish({
      w0: this.options.w0,
      L: this.options.L,
      shareP,
      context: this.options.context,
      idProver: this.options.idProver,
      idVerifier: this.options.idVerifier,
      ...(this.options.y !== undefined ? { y: this.options.y } : {}),
      ...(this.options.subtle !== undefined ? { subtle: this.options.subtle } : {})
    });
    this.verifierPending = result;
    this.phase = 'awaiting-confirmation';
    return {
      share: new Uint8Array(result.shareV),
      confirmation: new Uint8Array(result.confirmation)
    };
  }

  async proverFinish(
    shareV: Spake2PlusBytes,
    confirmationV: Uint8Array
  ): Promise<Spake2PlusSessionResult> {
    if (this.role !== 'prover') {
      throw sessionError('only the prover finishes with a verifier response');
    }
    if (this.phase !== 'awaiting-share' || !this.proverInit) {
      throw sessionError('prover is not awaiting a verifier share');
    }
    if (this.options.w1 === undefined) {
      throw new Spake2PlusError('invalid-input', 'prover witness w1 is required');
    }
    const result = await spake2PlusProverFinish({
      w0: this.options.w0,
      w1: this.options.w1,
      x: this.proverInit.x,
      shareV,
      context: this.options.context,
      idProver: this.options.idProver,
      idVerifier: this.options.idVerifier,
      ...(this.options.subtle !== undefined ? { subtle: this.options.subtle } : {})
    });
    assertSpake2PlusConfirmation(result.expectedConfirmation, confirmationV);
    this.phase = 'completed';
    return finishResult(
      result,
      result.confirmation,
      result.expectedConfirmation
    );
  }

  async verifierFinish(
    confirmationP: Uint8Array
  ): Promise<Spake2PlusSessionResult> {
    if (this.role !== 'verifier') {
      throw sessionError('only the verifier finishes with a prover confirmation');
    }
    if (this.phase !== 'awaiting-confirmation' || !this.verifierPending) {
      throw sessionError('verifier is not awaiting a prover confirmation');
    }
    assertSpake2PlusConfirmation(
      this.verifierPending.expectedConfirmation,
      confirmationP
    );
    this.phase = 'completed';
    return finishResult(
      this.verifierPending,
      this.verifierPending.expectedConfirmation,
      this.verifierPending.confirmation
    );
  }
}
