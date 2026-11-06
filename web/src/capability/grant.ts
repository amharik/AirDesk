import { bytesToBase64Url, concatBytes, sha256 } from '../identity/encoding';
import type {
  DeviceIdentityAlgorithm,
  DeviceSignatureVerifier
} from '../identity/identity';
import { decodeCbor, decodeCborAt, encodeCbor } from './cbor';
import type { CborInput, CborMap, CborValue } from './cbor';

export const COSE_SIGN1_TAG = 18;
export const COSE_ALG_EDDSA = -8;
export const COSE_ALG_ES256 = -7;
export const CAPABILITY_GRANT_MAX_BYTES = 8_192;
export const CAPABILITY_CHAIN_MAX_DEPTH = 3;

export type CapabilityGrantErrorCode =
  | 'invalid-token'
  | 'token-too-large'
  | 'unsupported-algorithm'
  | 'invalid-protected-header'
  | 'invalid-claims'
  | 'invalid-signature'
  | 'expired'
  | 'not-yet-valid'
  | 'issuer-mismatch'
  | 'audience-mismatch'
  | 'subject-mismatch'
  | 'epoch-mismatch'
  | 'chain-too-deep'
  | 'chain-mismatch'
  | 'parent-mismatch'
  | 'attenuation-widened'
  | 'lease-invalid'
  | 'missing-proof'
  | 'proof-not-required'
  | 'proof-mismatch'
  | 'confirmation-mismatch'
  | 'invalid-revocation'
  | 'revocation-stale'
  | 'revoked'
  | 'root-issuer-not-approved'
  | 'operation-not-granted';

export class CapabilityGrantError extends Error {
  readonly code: CapabilityGrantErrorCode;

  constructor(code: CapabilityGrantErrorCode, message: string) {
    super(message);
    this.name = 'CapabilityGrantError';
    this.code = code;
  }
}

export interface CapabilityGrantSigner {
  deviceId: string;
  algorithm: DeviceIdentityAlgorithm;
  sign(data: Uint8Array): Promise<Uint8Array>;
}

export interface CapabilityGrantClaims {
  iss: string;
  sub: string;
  aud: string;
  jti: string;
  cap_uri: string;
  op: string[];
  nbf: number;
  exp: number;
  epoch_id: number;
  cnf?: string;
  parent?: string;
}

export interface VerifiedCapabilityGrant {
  claims: CapabilityGrantClaims;
  token: Uint8Array;
  tokenHash: Uint8Array;
  protectedHeader: Uint8Array;
  payload: Uint8Array;
  signature: Uint8Array;
  algorithm: DeviceIdentityAlgorithm;
}

export interface VerifyCapabilityGrantOptions {
  now?: number;
  expectedAudience?: string;
  expectedSubject?: string;
  expectedEpochId?: number;
}

export interface VerifyCapabilityGrantChainOptions extends VerifyCapabilityGrantOptions {
  expectedRootIssuer?: string;
}

export interface CapabilityLease {
  leaseId: string;
  grantJti: string;
  capUri: string;
  workspaceId: string;
  applicationId: string;
  requesterDeviceId: string;
  sessionId: string;
  operations: string[];
  issuedAt: number;
  expiresAt: number;
  epochId: number;
  auditId: string;
}

export interface CreateCapabilityLeaseInput {
  leaseId: string;
  workspaceId: string;
  applicationId: string;
  requesterDeviceId: string;
  sessionId: string;
  operations: string[];
  issuedAt: number;
  expiresAt: number;
  auditId: string;
}

export interface ValidateCapabilityLeaseOptions {
  now?: number;
  workspaceId?: string;
  applicationId?: string;
  requesterDeviceId?: string;
  sessionId?: string;
}

const ALGORITHM_IDS: Record<DeviceIdentityAlgorithm, number> = {
  Ed25519: COSE_ALG_EDDSA,
  'P-256': COSE_ALG_ES256
};
const ALGORITHM_NAMES = new Map<number, DeviceIdentityAlgorithm>([
  [COSE_ALG_EDDSA, 'Ed25519'],
  [COSE_ALG_ES256, 'P-256']
]);
const MAX_IDENTIFIER = 256;
const MAX_CAP_URI = 512;
const MAX_OPERATION = 64;
const MAX_OPERATIONS = 32;
const BASE64URL_32 = /^[A-Za-z0-9_-]{43}$/;
const CAP_URI_PATTERN = /^airdesk:\/\/[A-Za-z0-9._~-]+(\/[A-Za-z0-9._~-]+)*$/;
const CLAIM_KEYS = new Set([
  'iss',
  'sub',
  'aud',
  'jti',
  'cap_uri',
  'op',
  'nbf',
  'exp',
  'epoch_id',
  'cnf',
  'parent'
]);

function fail(code: CapabilityGrantErrorCode, message: string): never {
  throw new CapabilityGrantError(code, message);
}

function mapToClaimRecord(map: CborMap): Record<string, CborValue> {
  const record: Record<string, CborValue> = {};
  for (const [key, value] of map) {
    if (typeof key !== 'string') fail('invalid-claims', 'claim keys must be text');
    if (!CLAIM_KEYS.has(key)) fail('invalid-claims', `unknown claim: ${key}`);
    record[key] = value;
  }
  return record;
}

function requiredString(
  record: Record<string, CborValue>,
  key: string,
  maxLength: number
): string {
  const value = record[key];
  if (typeof value !== 'string' || value.length === 0 || value.length > maxLength) {
    fail('invalid-claims', `invalid ${key}`);
  }
  return value;
}

function optionalDigest(
  record: Record<string, CborValue>,
  key: string
): string | undefined {
  if (!(key in record)) return undefined;
  const value = record[key];
  if (typeof value !== 'string' || !BASE64URL_32.test(value)) {
    fail('invalid-claims', `invalid ${key}`);
  }
  return value;
}

function requiredInteger(
  record: Record<string, CborValue>,
  key: string,
  minimum = 0
): number {
  const value = record[key];
  if (
    typeof value !== 'number' ||
    !Number.isSafeInteger(value) ||
    value < minimum
  ) {
    fail('invalid-claims', `invalid ${key}`);
  }
  return value;
}

function parseOperations(value: CborValue | undefined): string[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_OPERATIONS) {
    fail('invalid-claims', 'invalid op');
  }
  const operations: string[] = [];
  const seen = new Set<string>();
  for (const operation of value) {
    if (
      typeof operation !== 'string' ||
      operation.length === 0 ||
      operation.length > MAX_OPERATION ||
      seen.has(operation)
    ) {
      fail('invalid-claims', 'invalid op');
    }
    seen.add(operation);
    operations.push(operation);
  }
  return operations;
}

function normalizeClaims(claims: CapabilityGrantClaims): CapabilityGrantClaims {
  for (const [key, value] of [
    ['iss', claims.iss],
    ['sub', claims.sub],
    ['aud', claims.aud],
    ['jti', claims.jti]
  ] as const) {
    if (typeof value !== 'string' || value.length === 0 || value.length > MAX_IDENTIFIER) {
      fail('invalid-claims', `invalid ${key}`);
    }
  }
  const capUri = claims.cap_uri;
  if (typeof capUri !== 'string' || !CAP_URI_PATTERN.test(capUri)) {
    fail('invalid-claims', 'invalid cap_uri');
  }
  const operations = parseOperations(claims.op);
  if (!Number.isSafeInteger(claims.nbf) || !Number.isSafeInteger(claims.exp)) {
    fail('invalid-claims', 'invalid grant validity');
  }
  if (claims.exp <= claims.nbf) {
    fail('invalid-claims', 'grant expiry must be after nbf');
  }
  if (!Number.isSafeInteger(claims.epoch_id) || claims.epoch_id < 0) {
    fail('invalid-claims', 'invalid epoch_id');
  }
  if (
    claims.cnf !== undefined &&
    (typeof claims.cnf !== 'string' || !BASE64URL_32.test(claims.cnf))
  ) {
    fail('invalid-claims', 'invalid cnf');
  }
  if (
    claims.parent !== undefined &&
    (typeof claims.parent !== 'string' || !BASE64URL_32.test(claims.parent))
  ) {
    fail('invalid-claims', 'invalid parent');
  }
  return {
    iss: claims.iss,
    sub: claims.sub,
    aud: claims.aud,
    jti: claims.jti,
    cap_uri: capUri,
    op: operations,
    nbf: claims.nbf,
    exp: claims.exp,
    epoch_id: claims.epoch_id,
    ...(claims.cnf === undefined ? {} : { cnf: claims.cnf }),
    ...(claims.parent === undefined ? {} : { parent: claims.parent })
  };
}

function parseClaims(payload: Uint8Array): CapabilityGrantClaims {
  const decoded = decodeCbor(payload);
  if (!(decoded instanceof Map)) fail('invalid-claims', 'grant payload must be a map');
  const record = mapToClaimRecord(decoded);

  const claims: CapabilityGrantClaims = {
    iss: requiredString(record, 'iss', MAX_IDENTIFIER),
    sub: requiredString(record, 'sub', MAX_IDENTIFIER),
    aud: requiredString(record, 'aud', MAX_IDENTIFIER),
    jti: requiredString(record, 'jti', MAX_IDENTIFIER),
    cap_uri: requiredString(record, 'cap_uri', MAX_CAP_URI),
    op: parseOperations(record.op),
    nbf: requiredInteger(record, 'nbf'),
    exp: requiredInteger(record, 'exp'),
    epoch_id: requiredInteger(record, 'epoch_id')
  };

  const cnf = optionalDigest(record, 'cnf');
  if (cnf !== undefined) claims.cnf = cnf;
  const parent = optionalDigest(record, 'parent');
  if (parent !== undefined) claims.parent = parent;
  return normalizeClaims(claims);
}

function encodeClaims(claims: CapabilityGrantClaims): Uint8Array {
  const normalized = normalizeClaims(claims);
  const record: Record<string, CborInput> = {
    iss: normalized.iss,
    sub: normalized.sub,
    aud: normalized.aud,
    jti: normalized.jti,
    cap_uri: normalized.cap_uri,
    op: normalized.op,
    nbf: normalized.nbf,
    exp: normalized.exp,
    epoch_id: normalized.epoch_id
  };
  if (normalized.cnf !== undefined) record.cnf = normalized.cnf;
  if (normalized.parent !== undefined) record.parent = normalized.parent;
  return encodeCbor(record);
}

function protectedHeader(algorithm: DeviceIdentityAlgorithm): Uint8Array {
  return encodeCbor(new Map([[1, ALGORITHM_IDS[algorithm]]]));
}

function decodeProtectedHeader(value: Uint8Array): DeviceIdentityAlgorithm {
  const decoded = decodeCbor(value);
  if (!(decoded instanceof Map) || decoded.size !== 1 || !decoded.has(1)) {
    fail('invalid-protected-header', 'invalid COSE protected header');
  }
  const alg = decoded.get(1);
  if (typeof alg !== 'number') fail('unsupported-algorithm', 'invalid COSE algorithm');
  const algorithm = ALGORITHM_NAMES.get(alg);
  if (!algorithm) fail('unsupported-algorithm', 'unsupported COSE algorithm');
  return algorithm;
}

function sigStructure(protectedBytes: Uint8Array, payload: Uint8Array): Uint8Array {
  return encodeCbor([
    'Signature1',
    protectedBytes,
    new Uint8Array(0),
    payload
  ]);
}

function encodeCoseSign1(
  protectedBytes: Uint8Array,
  payload: Uint8Array,
  signature: Uint8Array
): Uint8Array {
  const token = concatBytes(
    new Uint8Array([0xd2]),
    encodeCbor([protectedBytes, new Map(), payload, signature])
  );
  if (token.length > CAPABILITY_GRANT_MAX_BYTES) {
    fail('token-too-large', 'capability grant token is too large');
  }
  return token;
}

export async function signCapabilityGrant(
  claims: CapabilityGrantClaims,
  signer: CapabilityGrantSigner
): Promise<Uint8Array> {
  if (claims.iss !== signer.deviceId) {
    fail('issuer-mismatch', 'grant issuer must match the signing device');
  }
  const normalized = normalizeClaims(claims);
  const payload = encodeClaims(normalized);
  const protectedBytes = protectedHeader(signer.algorithm);
  const signature = await signer.sign(sigStructure(protectedBytes, payload));
  if (signature.length === 0 || signature.length > 128) {
    fail('invalid-signature', 'invalid grant signature');
  }
  return encodeCoseSign1(protectedBytes, payload, signature);
}

interface ParsedCoseSign1 {
  protectedHeader: Uint8Array;
  payload: Uint8Array;
  signature: Uint8Array;
}

function parseCoseSign1(token: Uint8Array): ParsedCoseSign1 {
  if (!(token instanceof Uint8Array) || token.length === 0) {
    fail('invalid-token', 'capability grant token is required');
  }
  if (token.length > CAPABILITY_GRANT_MAX_BYTES) {
    fail('token-too-large', 'capability grant token is too large');
  }

  const offset = token[0] === 0xd2 ? 1 : 0;
  let decoded: { value: CborValue; next: number };
  try {
    decoded = decodeCborAt(token, offset);
  } catch (error) {
    throw new CapabilityGrantError(
      'invalid-token',
      error instanceof Error ? error.message : 'invalid COSE token'
    );
  }
  if (decoded.next !== token.length || !Array.isArray(decoded.value) || decoded.value.length !== 4) {
    fail('invalid-token', 'invalid COSE_Sign1 structure');
  }
  const [protectedHeader, unprotected, payload, signature] = decoded.value;
  if (!(protectedHeader instanceof Uint8Array) || !(payload instanceof Uint8Array)) {
    fail('invalid-token', 'invalid COSE_Sign1 content');
  }
  if (!(unprotected instanceof Map) || unprotected.size !== 0) {
    fail('invalid-token', 'COSE unprotected headers must be empty');
  }
  if (!(signature instanceof Uint8Array) || signature.length === 0) {
    fail('invalid-signature', 'grant signature is required');
  }
  return { protectedHeader, payload, signature };
}

export async function verifyCapabilityGrant(
  token: Uint8Array,
  verifier: DeviceSignatureVerifier,
  options: VerifyCapabilityGrantOptions = {}
): Promise<VerifiedCapabilityGrant> {
  const parsed = parseCoseSign1(token);
  const algorithm = decodeProtectedHeader(parsed.protectedHeader);
  if (algorithm !== verifier.algorithm) {
    fail('unsupported-algorithm', 'grant algorithm does not match the verifier');
  }

  const valid = await verifier.verify(
    sigStructure(parsed.protectedHeader, parsed.payload),
    parsed.signature
  );
  if (!valid) fail('invalid-signature', 'invalid grant signature');

  const claims = parseClaims(parsed.payload);
  if (claims.iss !== verifier.deviceId) {
    fail('issuer-mismatch', 'grant issuer does not match the verifier');
  }

  const now = options.now ?? Date.now();
  if (now < claims.nbf) fail('not-yet-valid', 'grant is not yet valid');
  if (now >= claims.exp) fail('expired', 'grant has expired');
  if (options.expectedAudience && claims.aud !== options.expectedAudience) {
    fail('audience-mismatch', 'grant audience mismatch');
  }
  if (options.expectedSubject && claims.sub !== options.expectedSubject) {
    fail('subject-mismatch', 'grant subject mismatch');
  }
  if (
    options.expectedEpochId !== undefined &&
    claims.epoch_id !== options.expectedEpochId
  ) {
    fail('epoch-mismatch', 'grant epoch mismatch');
  }

  return {
    claims,
    token: new Uint8Array(token),
    tokenHash: await sha256(token),
    protectedHeader: parsed.protectedHeader,
    payload: parsed.payload,
    signature: parsed.signature,
    algorithm
  };
}

function isAttenuatedCapUri(parent: string, child: string): boolean {
  return child === parent || child.startsWith(`${parent}/`);
}

function operationsAttenuated(parent: string[], child: string[]): boolean {
  const allowed = new Set(parent);
  return child.every((operation) => allowed.has(operation));
}

export async function verifyCapabilityGrantChain(
  tokens: readonly Uint8Array[],
  verifiers: readonly DeviceSignatureVerifier[],
  options: VerifyCapabilityGrantChainOptions = {}
): Promise<VerifiedCapabilityGrant[]> {
  if (tokens.length !== verifiers.length) {
    fail('chain-mismatch', 'each grant token requires a verifier');
  }
  if (tokens.length === 0) fail('chain-mismatch', 'grant chain is empty');
  if (tokens.length > CAPABILITY_CHAIN_MAX_DEPTH) {
    fail('chain-too-deep', 'grant chain exceeds the maximum depth');
  }

  const verified: VerifiedCapabilityGrant[] = [];
  for (let index = 0; index < tokens.length; index += 1) {
    verified.push(
      await verifyCapabilityGrant(tokens[index]!, verifiers[index]!, {
        ...(options.now === undefined ? {} : { now: options.now }),
        ...(options.expectedAudience === undefined
          ? {}
          : { expectedAudience: options.expectedAudience }),
        ...(options.expectedEpochId === undefined
          ? {}
          : { expectedEpochId: options.expectedEpochId })
      })
    );
  }

  const root = verified[0]!;
  if (root.claims.parent !== undefined) {
    fail('chain-mismatch', 'root grant must not have a parent');
  }
  if (
    options.expectedRootIssuer !== undefined &&
    root.claims.iss !== options.expectedRootIssuer
  ) {
    fail('issuer-mismatch', 'root grant issuer is not approved');
  }

  for (let index = 1; index < verified.length; index += 1) {
    const parent = verified[index - 1]!;
    const child = verified[index]!;
    if (child.claims.iss !== parent.claims.sub) {
      fail('chain-mismatch', 'delegated grant issuer does not match the parent subject');
    }
    if (child.claims.parent !== bytesToBase64Url(parent.tokenHash)) {
      fail('parent-mismatch', 'delegated grant parent hash mismatch');
    }
    if (child.claims.aud !== parent.claims.aud) {
      fail('attenuation-widened', 'delegated grant audience changed');
    }
    if (child.claims.epoch_id !== parent.claims.epoch_id) {
      fail('attenuation-widened', 'delegated grant epoch changed');
    }
    if (child.claims.nbf < parent.claims.nbf || child.claims.exp > parent.claims.exp) {
      fail('attenuation-widened', 'delegated grant validity widened');
    }
    if (!isAttenuatedCapUri(parent.claims.cap_uri, child.claims.cap_uri)) {
      fail('attenuation-widened', 'delegated grant capability widened');
    }
    if (!operationsAttenuated(parent.claims.op, child.claims.op)) {
      fail('attenuation-widened', 'delegated grant operations widened');
    }
  }

  return verified;
}

export function createCapabilityLease(
  grant: VerifiedCapabilityGrant,
  input: CreateCapabilityLeaseInput
): CapabilityLease {
  if (
    !Number.isSafeInteger(input.issuedAt) ||
    !Number.isSafeInteger(input.expiresAt) ||
    input.expiresAt <= input.issuedAt
  ) {
    fail('lease-invalid', 'invalid lease validity');
  }
  if (input.expiresAt > grant.claims.exp) {
    fail('lease-invalid', 'lease cannot outlive its grant');
  }
  if (input.issuedAt < grant.claims.nbf) {
    fail('lease-invalid', 'lease cannot precede its grant');
  }
  let operations: string[];
  try {
    operations = parseOperations(input.operations);
  } catch {
    fail('lease-invalid', 'invalid lease operations');
  }
  if (!operationsAttenuated(grant.claims.op, operations)) {
    fail('lease-invalid', 'lease operations exceed the grant');
  }
  for (const value of [
    input.leaseId,
    input.workspaceId,
    input.applicationId,
    input.requesterDeviceId,
    input.sessionId,
    input.auditId
  ]) {
    if (!value || value.length > MAX_IDENTIFIER) {
      fail('lease-invalid', 'invalid lease identifier');
    }
  }

  return {
    leaseId: input.leaseId,
    grantJti: grant.claims.jti,
    capUri: grant.claims.cap_uri,
    workspaceId: input.workspaceId,
    applicationId: input.applicationId,
    requesterDeviceId: input.requesterDeviceId,
    sessionId: input.sessionId,
    operations,
    issuedAt: input.issuedAt,
    expiresAt: input.expiresAt,
    epochId: grant.claims.epoch_id,
    auditId: input.auditId
  };
}

export function validateCapabilityLease(
  lease: CapabilityLease,
  grant: VerifiedCapabilityGrant,
  options: ValidateCapabilityLeaseOptions = {}
): void {
  const now = options.now ?? Date.now();
  if (lease.grantJti !== grant.claims.jti) {
    fail('lease-invalid', 'lease does not match the grant');
  }
  if (lease.capUri !== grant.claims.cap_uri) {
    fail('lease-invalid', 'lease capability does not match the grant');
  }
  if (lease.epochId !== grant.claims.epoch_id) {
    fail('epoch-mismatch', 'lease epoch does not match the grant');
  }
  if (now < lease.issuedAt) fail('not-yet-valid', 'lease is not yet valid');
  if (now >= lease.expiresAt) fail('expired', 'lease has expired');
  if (lease.expiresAt > grant.claims.exp) {
    fail('lease-invalid', 'lease outlives its grant');
  }
  if (lease.issuedAt < grant.claims.nbf) {
    fail('lease-invalid', 'lease precedes its grant');
  }
  if (!operationsAttenuated(grant.claims.op, lease.operations)) {
    fail('lease-invalid', 'lease operations exceed the grant');
  }
  if (
    options.workspaceId !== undefined &&
    lease.workspaceId !== options.workspaceId
  ) {
    fail('lease-invalid', 'lease workspace mismatch');
  }
  if (
    options.applicationId !== undefined &&
    lease.applicationId !== options.applicationId
  ) {
    fail('lease-invalid', 'lease application mismatch');
  }
  if (
    options.requesterDeviceId !== undefined &&
    lease.requesterDeviceId !== options.requesterDeviceId
  ) {
    fail('lease-invalid', 'lease requester mismatch');
  }
  if (
    options.sessionId !== undefined &&
    lease.sessionId !== options.sessionId
  ) {
    fail('lease-invalid', 'lease session mismatch');
  }
}
