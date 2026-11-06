import { bytesEqual, sha256 } from '../identity/encoding';
import type {
  DeviceIdentityAlgorithm,
  DeviceSignatureVerifier
} from '../identity/identity';
import { decodeCbor, encodeCbor } from './cbor';
import type { CborInput, CborMap, CborValue } from './cbor';
import { CapabilityGrantError } from './grant';

export const CAPABILITY_REVOCATION_DOMAIN = 'AD-CAP-REV-1';
export const CAPABILITY_REVOCATION_MAX_BYTES = 8_192;
export const CAPABILITY_REVOCATION_MAX_ENTRIES = 1_024;

export type CapabilityRevocationKind = 'grant' | 'lease';
export type CapabilityRevocationReason =
  | 'user-revoked'
  | 'device-revoked'
  | 'policy'
  | 'superseded';

export interface CapabilityRevocationEntry {
  ref: string;
  kind: CapabilityRevocationKind;
  at: number;
  reason: CapabilityRevocationReason;
}

export interface CapabilityRevocationRecord {
  iss: string;
  seq: number;
  issued_at: number;
  entries: CapabilityRevocationEntry[];
}

export interface CapabilityRevocationSigner {
  deviceId: string;
  algorithm: DeviceIdentityAlgorithm;
  sign(data: Uint8Array): Promise<Uint8Array>;
}

export interface VerifiedCapabilityRevocationRecord {
  record: CapabilityRevocationRecord;
  token: Uint8Array;
  tokenHash: Uint8Array;
  payload: Uint8Array;
  signature: Uint8Array;
  algorithm: DeviceIdentityAlgorithm;
}

export interface VerifyCapabilityRevocationOptions {
  now?: number;
  expectedIssuer?: string;
  minimumSequence?: number;
  maxStalenessMs?: number;
  maxFutureSkewMs?: number;
}

export interface AssertCapabilityNotRevokedOptions {
  issuer: string;
  now: number;
  maxStalenessMs: number;
  maxFutureSkewMs?: number;
}

const MAX_IDENTIFIER = 256;
const REASONS = new Set<CapabilityRevocationReason>([
  'user-revoked',
  'device-revoked',
  'policy',
  'superseded'
]);
const ALGORITHM_IDS: Record<DeviceIdentityAlgorithm, number> = {
  Ed25519: -8,
  'P-256': -7
};
const ALGORITHM_NAMES = new Map<number, DeviceIdentityAlgorithm>([
  [-8, 'Ed25519'],
  [-7, 'P-256']
]);
const RECORD_KEYS = new Set(['iss', 'seq', 'issued_at', 'entries']);
const ENTRY_KEYS = new Set(['ref', 'kind', 'at', 'reason']);

function fail(
  message: string,
  code:
    | 'invalid-revocation'
    | 'revocation-stale'
    | 'revoked'
    | 'issuer-mismatch'
    | 'unsupported-algorithm'
    | 'token-too-large'
): never {
  throw new CapabilityGrantError(code, message);
}

function toMap(value: CborValue, label: string): CborMap {
  if (!(value instanceof Map)) fail(`${label} must be a map`, 'invalid-revocation');
  return value;
}

function stringField(
  map: CborMap,
  key: string,
  allowed?: Set<string>,
  maxLength = MAX_IDENTIFIER
): string {
  const value = map.get(key);
  if (typeof value !== 'string' || value.length === 0 || value.length > maxLength) {
    fail(`invalid revocation ${key}`, 'invalid-revocation');
  }
  if (allowed && !allowed.has(value)) {
    fail(`unsupported revocation ${key}`, 'invalid-revocation');
  }
  return value;
}

function integerField(map: CborMap, key: string, minimum = 0): number {
  const value = map.get(key);
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < minimum) {
    fail(`invalid revocation ${key}`, 'invalid-revocation');
  }
  return value;
}

function assertKeys(map: CborMap, allowed: Set<string>, label: string): void {
  for (const key of map.keys()) {
    if (typeof key !== 'string' || !allowed.has(key)) {
      fail(`unknown ${label} field`, 'invalid-revocation');
    }
  }
}

function parseEntry(value: CborValue): CapabilityRevocationEntry {
  const map = toMap(value, 'revocation entry');
  assertKeys(map, ENTRY_KEYS, 'revocation entry');
  const kind = stringField(map, 'kind', new Set(['grant', 'lease']));
  const reason = stringField(map, 'reason', REASONS);
  return {
    ref: stringField(map, 'ref', undefined),
    kind: kind as CapabilityRevocationKind,
    at: integerField(map, 'at'),
    reason: reason as CapabilityRevocationReason
  };
}

function parseRecord(payload: Uint8Array): CapabilityRevocationRecord {
  const decoded = decodeCbor(payload);
  const map = toMap(decoded, 'revocation record');
  assertKeys(map, RECORD_KEYS, 'revocation record');
  const entriesValue = map.get('entries');
  if (
    !Array.isArray(entriesValue) ||
    entriesValue.length > CAPABILITY_REVOCATION_MAX_ENTRIES
  ) {
    fail('invalid revocation entries', 'invalid-revocation');
  }
  const entries = entriesValue.map(parseEntry);
  const seen = new Set<string>();
  for (const entry of entries) {
    const key = `${entry.kind}:${entry.ref}`;
    if (seen.has(key)) {
      fail('duplicate revocation entry', 'invalid-revocation');
    }
    seen.add(key);
  }
  const issuedAt = integerField(map, 'issued_at');
  if (entries.some((entry) => entry.at > issuedAt)) {
    fail('revocation entry is newer than its record', 'invalid-revocation');
  }
  return {
    iss: stringField(map, 'iss'),
    seq: integerField(map, 'seq', 1),
    issued_at: issuedAt,
    entries
  };
}

function encodeRecord(record: CapabilityRevocationRecord): Uint8Array {
  const entries: CborInput[] = record.entries.map((entry) => ({
    ref: entry.ref,
    kind: entry.kind,
    at: entry.at,
    reason: entry.reason
  }));
  return encodeCbor({
    iss: record.iss,
    seq: record.seq,
    issued_at: record.issued_at,
    entries
  });
}

function protectedHeader(algorithm: DeviceIdentityAlgorithm): Uint8Array {
  return encodeCbor(new Map([[1, ALGORITHM_IDS[algorithm]]]));
}

function decodeProtectedHeader(value: Uint8Array): DeviceIdentityAlgorithm {
  const decoded = decodeCbor(value);
  if (!(decoded instanceof Map) || decoded.size !== 1 || !decoded.has(1)) {
    fail('invalid revocation protected header', 'invalid-revocation');
  }
  const algorithmId = decoded.get(1);
  if (typeof algorithmId !== 'number') {
    fail('invalid revocation algorithm', 'invalid-revocation');
  }
  const algorithm = ALGORITHM_NAMES.get(algorithmId);
  if (!algorithm) fail('unsupported revocation algorithm', 'unsupported-algorithm');
  return algorithm;
}

function signatureInput(protectedBytes: Uint8Array, payload: Uint8Array): Uint8Array {
  return encodeCbor([
    'Signature1',
    protectedBytes,
    new TextEncoder().encode(CAPABILITY_REVOCATION_DOMAIN),
    payload
  ]);
}

function validateRecord(record: CapabilityRevocationRecord): void {
  if (record.iss.length === 0 || record.iss.length > MAX_IDENTIFIER) {
    fail('invalid revocation issuer', 'invalid-revocation');
  }
  if (!Number.isSafeInteger(record.seq) || record.seq < 1) {
    fail('invalid revocation sequence', 'invalid-revocation');
  }
  if (!Number.isSafeInteger(record.issued_at) || record.issued_at < 0) {
    fail('invalid revocation issue time', 'invalid-revocation');
  }
  if (record.entries.length > CAPABILITY_REVOCATION_MAX_ENTRIES) {
    fail('too many revocation entries', 'invalid-revocation');
  }
  const seen = new Set<string>();
  for (const entry of record.entries) {
    if (
      typeof entry.ref !== 'string' ||
      entry.ref.length === 0 ||
      entry.ref.length > MAX_IDENTIFIER
    ) {
      fail('invalid revocation reference', 'invalid-revocation');
    }
    if (entry.kind !== 'grant' && entry.kind !== 'lease') {
      fail('invalid revocation kind', 'invalid-revocation');
    }
    if (!REASONS.has(entry.reason)) {
      fail('invalid revocation reason', 'invalid-revocation');
    }
    if (
      !Number.isSafeInteger(entry.at) ||
      entry.at < 0 ||
      entry.at > record.issued_at
    ) {
      fail('invalid revocation time', 'invalid-revocation');
    }
    const key = `${entry.kind}:${entry.ref}`;
    if (seen.has(key)) fail('duplicate revocation entry', 'invalid-revocation');
    seen.add(key);
  }
}

export async function signCapabilityRevocationRecord(
  record: CapabilityRevocationRecord,
  signer: CapabilityRevocationSigner
): Promise<Uint8Array> {
  if (record.iss !== signer.deviceId) {
    fail('revocation issuer must match the signing device', 'issuer-mismatch');
  }
  validateRecord(record);
  const payload = encodeRecord(record);
  const protectedBytes = protectedHeader(signer.algorithm);
  const signature = await signer.sign(signatureInput(protectedBytes, payload));
  if (signature.length === 0 || signature.length > 128) {
    fail('invalid revocation signature', 'invalid-revocation');
  }
  const token = encodeCbor([protectedBytes, payload, signature]);
  if (token.length > CAPABILITY_REVOCATION_MAX_BYTES) {
    fail('revocation record is too large', 'token-too-large');
  }
  return token;
}

export async function verifyCapabilityRevocationRecord(
  token: Uint8Array,
  verifier: DeviceSignatureVerifier,
  options: VerifyCapabilityRevocationOptions = {}
): Promise<VerifiedCapabilityRevocationRecord> {
  if (!(token instanceof Uint8Array) || token.length === 0) {
    fail('revocation record is required', 'invalid-revocation');
  }
  if (token.length > CAPABILITY_REVOCATION_MAX_BYTES) {
    fail('revocation record is too large', 'token-too-large');
  }

  let decoded: CborValue;
  try {
    decoded = decodeCbor(token);
  } catch (error) {
    throw new CapabilityGrantError(
      'invalid-revocation',
      error instanceof Error ? error.message : 'invalid revocation record'
    );
  }
  if (!Array.isArray(decoded) || decoded.length !== 3) {
    fail('invalid revocation structure', 'invalid-revocation');
  }
  const [protectedBytes, payload, signature] = decoded;
  if (
    !(protectedBytes instanceof Uint8Array) ||
    !(payload instanceof Uint8Array) ||
    !(signature instanceof Uint8Array) ||
    signature.length === 0
  ) {
    fail('invalid revocation content', 'invalid-revocation');
  }

  const algorithm = decodeProtectedHeader(protectedBytes);
  if (algorithm !== verifier.algorithm) {
    fail('revocation algorithm does not match the verifier', 'unsupported-algorithm');
  }
  const valid = await verifier.verify(
    signatureInput(protectedBytes, payload),
    signature
  );
  if (!valid) fail('invalid revocation signature', 'invalid-revocation');

  const record = parseRecord(payload);
  if (record.iss !== verifier.deviceId) {
    fail('revocation issuer does not match the verifier', 'issuer-mismatch');
  }
  if (options.expectedIssuer !== undefined && record.iss !== options.expectedIssuer) {
    fail('revocation issuer mismatch', 'issuer-mismatch');
  }
  if (options.minimumSequence !== undefined && record.seq < options.minimumSequence) {
    fail('revocation sequence is stale', 'revocation-stale');
  }
  const now = options.now ?? Date.now();
  const maxFutureSkewMs = options.maxFutureSkewMs ?? 300_000;
  if (record.issued_at > now + maxFutureSkewMs) {
    fail('revocation record is from the future', 'revocation-stale');
  }
  if (
    options.maxStalenessMs !== undefined &&
    now - record.issued_at > options.maxStalenessMs
  ) {
    fail('revocation record is too old', 'revocation-stale');
  }

  return {
    record,
    token: new Uint8Array(token),
    tokenHash: await sha256(token),
    payload,
    signature,
    algorithm
  };
}

export class CapabilityRevocationStore {
  private readonly records = new Map<string, VerifiedCapabilityRevocationRecord>();
  private readonly trustedIssuers?: ReadonlySet<string>;
  private readonly maxFutureSkewMs: number;

  constructor(options: {
    trustedIssuers?: Iterable<string>;
    maxFutureSkewMs?: number;
  } = {}) {
    this.trustedIssuers =
      options.trustedIssuers === undefined
        ? undefined
        : new Set(options.trustedIssuers);
    this.maxFutureSkewMs = options.maxFutureSkewMs ?? 300_000;
  }

  add(record: VerifiedCapabilityRevocationRecord): boolean {
    const issuer = record.record.iss;
    if (this.trustedIssuers && !this.trustedIssuers.has(issuer)) {
      fail('revocation issuer is not trusted', 'issuer-mismatch');
    }
    const existing = this.records.get(issuer);
    if (existing) {
      if (record.record.seq < existing.record.seq) {
        fail('revocation sequence went backwards', 'revocation-stale');
      }
      if (record.record.seq === existing.record.seq) {
        if (!bytesEqual(record.tokenHash, existing.tokenHash)) {
          fail('conflicting revocation records for one sequence', 'invalid-revocation');
        }
        return false;
      }
      const nextEntries = new Set(
        record.record.entries.map((entry) => `${entry.kind}:${entry.ref}`)
      );
      for (const previous of existing.record.entries) {
        if (!nextEntries.has(`${previous.kind}:${previous.ref}`)) {
          fail('revocation record drops a prior entry', 'invalid-revocation');
        }
      }
    }
    this.records.set(issuer, record);
    return true;
  }

  latest(issuer: string): VerifiedCapabilityRevocationRecord | undefined {
    return this.records.get(issuer);
  }

  assertNotRevoked(
    ref: string,
    kind: CapabilityRevocationKind,
    options: AssertCapabilityNotRevokedOptions
  ): void {
    if (
      typeof ref !== 'string' ||
      ref.length === 0 ||
      ref.length > MAX_IDENTIFIER
    ) {
      fail('invalid revocation reference', 'invalid-revocation');
    }
    if (!Number.isSafeInteger(options.now) || !Number.isSafeInteger(options.maxStalenessMs) || options.maxStalenessMs < 0) {
      fail('invalid revocation freshness policy', 'revocation-stale');
    }
    const latest = this.records.get(options.issuer);
    if (!latest) {
      fail('no revocation record is available', 'revocation-stale');
    }
    const age = options.now - latest.record.issued_at;
    if (age < 0 && -age > (options.maxFutureSkewMs ?? this.maxFutureSkewMs)) {
      fail('revocation record is from the future', 'revocation-stale');
    }
    if (age > options.maxStalenessMs) {
      fail('revocation record is too old', 'revocation-stale');
    }
    const entry = latest.record.entries.find(
      (candidate) => candidate.kind === kind && candidate.ref === ref
    );
    if (entry) fail(`capability ${kind} has been revoked`, 'revoked');
  }
}
