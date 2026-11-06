import {
  base64UrlToBytes,
  bytesToBase64Url,
  randomBytes,
  utf8
} from './encoding';
import {
  PairingValidationError,
  validatePairingPayload
} from './pairing-payload';
import type {
  PairingParseOptions,
  PairingPayload
} from './pairing-payload';
import {
  createSpake2PlusPasswordRegistration,
  type Spake2PlusPasswordRegistration
} from './spake2plus';

export const PAIRING_CODE_PROTOCOL = 'adpair1';
export const PAIRING_CODE_PREFIX = 'ADPAIR1:';
export const PAIRING_CODE_VERSION = 1;
export const PAIRING_PIN_DIGITS = 6;

export type PairingCodeMode = 'pin' | 'qr-secret';

export type PairingCodeErrorCode =
  | 'invalid-code'
  | 'malformed-code'
  | 'unsupported-code-version'
  | 'unknown-field'
  | 'invalid-mode'
  | 'invalid-salt'
  | 'invalid-secret'
  | 'invalid-pin'
  | 'expired-code'
  | 'pin-locked';

export class PairingCodeError extends Error {
  readonly code: PairingCodeErrorCode;

  constructor(code: PairingCodeErrorCode, message: string) {
    super(message);
    this.name = 'PairingCodeError';
    this.code = code;
  }
}

export interface PairingCode {
  protocol: typeof PAIRING_CODE_PROTOCOL;
  version: typeof PAIRING_CODE_VERSION;
  mode: PairingCodeMode;
  salt: string;
  secret?: string;
  offer: PairingPayload;
}

export interface PairingChallenge {
  code: PairingCode;
  serialized: string;
  mode: PairingCodeMode;
  salt: Uint8Array;
  expiresAt: number;
  pin?: string;
  secret?: Uint8Array;
}

export interface PairingChallengeOptions {
  now?: number;
  cryptoSource?: Crypto;
}

export interface PairingCodeParseOptions extends PairingParseOptions {
  expectedMode?: PairingCodeMode;
}

export interface PairingCodeRegistrationInput {
  code: PairingCode;
  initiatorDeviceId: string;
  responderDeviceId: string;
  pin?: string;
}

const CODE_FIELDS = new Set([
  'protocol',
  'version',
  'mode',
  'salt',
  'secret',
  'offer'
]);
const MIN_SALT_BYTES = 16;
const MAX_SALT_BYTES = 64;
const MIN_SECRET_BYTES = 16;
const MAX_SECRET_BYTES = 64;
const PIN_PATTERN = /^\d{6}$/;
const TEXT_DECODER = new TextDecoder();

function fail(code: PairingCodeErrorCode, message: string): never {
  throw new PairingCodeError(code, message);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function decodeSalt(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 128) {
    fail('invalid-salt', 'invalid pairing salt');
  }
  let bytes: Uint8Array;
  try {
    bytes = base64UrlToBytes(value);
  } catch {
    fail('invalid-salt', 'invalid pairing salt encoding');
  }
  if (bytes.length < MIN_SALT_BYTES || bytes.length > MAX_SALT_BYTES) {
    fail('invalid-salt', 'pairing salt length out of range');
  }
  return value;
}

function decodeSecret(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 128) {
    fail('invalid-secret', 'invalid QR pairing secret');
  }
  let bytes: Uint8Array;
  try {
    bytes = base64UrlToBytes(value);
  } catch {
    fail('invalid-secret', 'invalid QR pairing secret encoding');
  }
  if (bytes.length < MIN_SECRET_BYTES || bytes.length > MAX_SECRET_BYTES) {
    fail('invalid-secret', 'QR pairing secret length out of range');
  }
  return value;
}

function assertPin(pin: string | undefined): string {
  if (typeof pin !== 'string' || !PIN_PATTERN.test(pin)) {
    fail('invalid-pin', `PIN must be ${PAIRING_PIN_DIGITS} digits`);
  }
  return pin;
}

function validateCode(
  value: unknown,
  options: PairingCodeParseOptions
): PairingCode {
  if (!isRecord(value)) fail('malformed-code', 'pairing code must be an object');
  for (const key of Object.keys(value)) {
    if (!CODE_FIELDS.has(key)) fail('unknown-field', `unknown pairing code field: ${key}`);
  }
  if (value.protocol !== PAIRING_CODE_PROTOCOL) {
    fail('invalid-code', 'unsupported pairing code protocol');
  }
  if (value.version !== PAIRING_CODE_VERSION) {
    fail('unsupported-code-version', 'unsupported pairing code version');
  }
  if (value.mode !== 'pin' && value.mode !== 'qr-secret') {
    fail('invalid-mode', 'pairing code mode must be pin or qr-secret');
  }
  if (options.expectedMode && value.mode !== options.expectedMode) {
    fail('invalid-mode', `expected ${options.expectedMode} pairing code`);
  }

  const salt = decodeSalt(value.salt);
  let offer: PairingPayload;
  try {
    offer = validatePairingPayload(value.offer, {
      ...options,
      expectedType: 'offer'
    });
  } catch (error) {
    if (error instanceof PairingValidationError && error.code === 'expired') {
      fail('expired-code', 'pairing code has expired');
    }
    throw error;
  }
  if (offer.expiresAt <= (options.now ?? Date.now())) {
    fail('expired-code', 'pairing code has expired');
  }

  if (value.mode === 'pin') {
    if (Object.prototype.hasOwnProperty.call(value, 'secret')) {
      throw new PairingCodeError('invalid-secret', 'PIN codes must not carry a secret');
    }
    return {
      protocol: PAIRING_CODE_PROTOCOL,
      version: PAIRING_CODE_VERSION,
      mode: 'pin',
      salt,
      offer
    };
  }

  return {
    protocol: PAIRING_CODE_PROTOCOL,
    version: PAIRING_CODE_VERSION,
    mode: 'qr-secret',
    salt,
    secret: decodeSecret(value.secret),
    offer
  };
}

export function serializePairingCode(code: PairingCode): string {
  const value: PairingCode = {
    protocol: code.protocol,
    version: code.version,
    mode: code.mode,
    salt: code.salt,
    offer: code.offer
  };
  if (code.secret !== undefined) value.secret = code.secret;
  return `${PAIRING_CODE_PREFIX}${bytesToBase64Url(utf8(JSON.stringify(value)))}`;
}

export function parsePairingCode(
  raw: string,
  options: PairingCodeParseOptions = {}
): PairingCode {
  if (typeof raw !== 'string' || raw.length === 0 || raw.length > 16_384) {
    fail('invalid-code', 'invalid pairing code');
  }
  if (!raw.startsWith(PAIRING_CODE_PREFIX)) {
    fail('invalid-code', 'pairing code prefix is missing');
  }

  let value: unknown;
  try {
    const json = TEXT_DECODER.decode(
      base64UrlToBytes(raw.slice(PAIRING_CODE_PREFIX.length))
    );
    value = JSON.parse(json);
  } catch {
    fail('malformed-code', 'pairing code is not valid JSON');
  }
  return validateCode(value, options);
}

function randomPin(source: Crypto): string {
  const limit = 2 ** 32 - (2 ** 32 % 1_000_000);
  const words = new Uint32Array(1);
  do {
    source.getRandomValues(words);
  } while (words[0]! >= limit);
  return String(words[0]! % 1_000_000).padStart(PAIRING_PIN_DIGITS, '0');
}

function challenge(
  code: PairingCode,
  pin?: string,
  secret?: Uint8Array
): PairingChallenge {
  return {
    code,
    serialized: serializePairingCode(code),
    mode: code.mode,
    salt: base64UrlToBytes(code.salt),
    expiresAt: code.offer.expiresAt,
    ...(pin === undefined ? {} : { pin }),
    ...(secret === undefined ? {} : { secret })
  };
}

export function createPairingPinChallenge(
  offer: PairingPayload,
  options: PairingChallengeOptions = {}
): PairingChallenge {
  if (offer.type !== 'offer') fail('invalid-code', 'pairing challenge requires an offer');
  if (offer.expiresAt <= (options.now ?? Date.now())) {
    fail('expired-code', 'pairing offer has expired');
  }
  const source = options.cryptoSource ?? crypto;
  const pin = randomPin(source);
  const salt = bytesToBase64Url(randomBytes(32, source));
  return challenge(
    {
      protocol: PAIRING_CODE_PROTOCOL,
      version: PAIRING_CODE_VERSION,
      mode: 'pin',
      salt,
      offer
    },
    pin
  );
}

export function createPairingQrSecretChallenge(
  offer: PairingPayload,
  options: PairingChallengeOptions = {}
): PairingChallenge {
  if (offer.type !== 'offer') fail('invalid-code', 'pairing challenge requires an offer');
  if (offer.expiresAt <= (options.now ?? Date.now())) {
    fail('expired-code', 'pairing offer has expired');
  }
  const source = options.cryptoSource ?? crypto;
  const secret = randomBytes(32, source);
  const salt = randomBytes(32, source);
  return challenge(
    {
      protocol: PAIRING_CODE_PROTOCOL,
      version: PAIRING_CODE_VERSION,
      mode: 'qr-secret',
      salt: bytesToBase64Url(salt),
      secret: bytesToBase64Url(secret),
      offer
    },
    undefined,
    secret
  );
}

export async function derivePairingCodeRegistration(
  input: PairingCodeRegistrationInput
): Promise<Spake2PlusPasswordRegistration> {
  const { code } = input;
  if (code.mode === 'pin' && code.secret !== undefined) {
    fail('invalid-secret', 'PIN codes must not carry a secret');
  }
  if (!input.initiatorDeviceId || !input.responderDeviceId) {
    fail('invalid-code', 'pairing device ids are required');
  }
  if (input.initiatorDeviceId === input.responderDeviceId) {
    fail('invalid-code', 'pairing device ids must differ');
  }

  const password = code.mode === 'pin'
    ? assertPin(input.pin)
    : base64UrlToBytes(code.secret!);

  return createSpake2PlusPasswordRegistration({
    password,
    salt: base64UrlToBytes(code.salt),
    idProver: utf8(input.initiatorDeviceId),
    idVerifier: utf8(input.responderDeviceId)
  });
}

export interface PairingPinAttemptGuardOptions {
  maxAttempts?: number;
  now?: () => number;
}

interface AttemptState {
  failures: number;
  expiresAt: number;
}

export class PairingPinAttemptGuard {
  private readonly attempts = new Map<string, AttemptState>();
  private readonly maxAttempts: number;
  private readonly now: () => number;

  constructor(options: PairingPinAttemptGuardOptions = {}) {
    this.maxAttempts = options.maxAttempts ?? 5;
    if (!Number.isSafeInteger(this.maxAttempts) || this.maxAttempts <= 0) {
      throw new PairingCodeError('invalid-code', 'maxAttempts must be positive');
    }
    this.now = options.now ?? Date.now;
  }

  assertAllowed(key: string, expiresAt: number): void {
    this.prune();
    if (expiresAt <= this.now()) {
      throw new PairingCodeError('expired-code', 'pairing PIN has expired');
    }
    const state = this.attempts.get(key);
    if (state && state.failures >= this.maxAttempts) {
      throw new PairingCodeError('pin-locked', 'pairing PIN is locked');
    }
  }

  recordFailure(key: string, expiresAt: number): number {
    this.assertAllowed(key, expiresAt);
    const state = this.attempts.get(key) ?? { failures: 0, expiresAt };
    state.failures += 1;
    state.expiresAt = Math.max(state.expiresAt, expiresAt);
    this.attempts.set(key, state);
    return Math.max(0, this.maxAttempts - state.failures);
  }

  recordSuccess(key: string): void {
    this.attempts.delete(key);
  }

  reset(key: string): void {
    this.attempts.delete(key);
  }

  prune(): void {
    const now = this.now();
    for (const [key, state] of this.attempts) {
      if (state.expiresAt <= now) this.attempts.delete(key);
    }
  }
}

export function isPairingCodeError(error: unknown): error is PairingCodeError {
  return error instanceof PairingCodeError;
}

export function isPairingCodeValidationError(
  error: unknown
): error is PairingValidationError {
  return error instanceof PairingValidationError;
}
