import {
  asBufferSource,
  base64ToBytes,
  bytesToBase64,
  randomBytes
} from '../identity/encoding';
import {
  SYNC_KEY_BYTES,
  SYNC_NONCE_BYTES,
  SYNC_TAG_BYTES,
  importWorkspaceSyncKey
} from './envelope';

export const WORKSPACE_KEY_ROTATION_VERSION = 1;
export const WORKSPACE_KEY_ROTATION_KIND = 'workspace-key-rotation';
export const WORKSPACE_KEY_GRANT_VERSION = 1;
export const WORKSPACE_KEY_GRANT_KIND = 'workspace-key-grant';

export interface WorkspaceKeyRotation {
  version: number;
  kind: typeof WORKSPACE_KEY_ROTATION_KIND;
  workspaceId: string;
  issuerDeviceId: string;
  generation: number;
  nonce: string;
  ciphertext: string;
}

export interface WorkspaceKeyGrant {
  version: number;
  kind: typeof WORKSPACE_KEY_GRANT_KIND;
  workspaceId: string;
  issuerDeviceId: string;
  generation: number;
  nonce: string;
  ciphertext: string;
}

export type WorkspaceKeyRotationErrorCode =
  | 'InvalidKeyRotation'
  | 'UnsupportedVersion'
  | 'WorkspaceMismatch'
  | 'GenerationReplay'
  | 'GenerationGap'
  | 'InvalidIssuer'
  | 'InvalidSyncKey'
  | 'AuthenticationFailed';

export class WorkspaceKeyRotationError extends Error {
  readonly code: WorkspaceKeyRotationErrorCode;

  constructor(code: WorkspaceKeyRotationErrorCode, message: string) {
    super(`${code}: ${message}`);
    this.name = 'WorkspaceKeyRotationError';
    this.code = code;
  }
}

export interface RotateWorkspaceSyncKeyOptions {
  currentKey: CryptoKey;
  workspaceId: string;
  issuerDeviceId: string;
  nextGeneration: number;
  newKey?: Uint8Array;
  nonce?: Uint8Array;
  subtle?: SubtleCrypto;
}

export interface RotatedWorkspaceSyncKey {
  key: CryptoKey;
  rawKey: Uint8Array;
  message: WorkspaceKeyRotation;
}

export interface AcceptWorkspaceKeyRotationOptions {
  currentKey: CryptoKey;
  message: WorkspaceKeyRotation;
  workspaceId: string;
  currentGeneration: number;
  expectedIssuerDeviceId?: string;
  subtle?: SubtleCrypto;
}

export interface AcceptedWorkspaceKeyRotation {
  key: CryptoKey;
  rawKey: Uint8Array;
  generation: number;
}

function canonicalAad(message: WorkspaceKeyRotation | WorkspaceKeyGrant): Uint8Array {
  return new TextEncoder().encode(
    JSON.stringify([
      message.version,
      message.kind,
      message.workspaceId,
      message.issuerDeviceId,
      message.generation
    ])
  );
}

function validateMessage(message: WorkspaceKeyRotation): void {
  if (!message || typeof message !== 'object') {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'a rotation object is required.');
  }
  if (message.version !== WORKSPACE_KEY_ROTATION_VERSION) {
    throw new WorkspaceKeyRotationError(
      'UnsupportedVersion',
      `unsupported key rotation version ${String(message.version)}.`
    );
  }
  if (message.kind !== WORKSPACE_KEY_ROTATION_KIND) {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'message kind is not a rotation.');
  }
  if (!message.workspaceId || !message.issuerDeviceId) {
    throw new WorkspaceKeyRotationError(
      'InvalidKeyRotation',
      'workspace and issuer device are required.'
    );
  }
  if (!Number.isSafeInteger(message.generation) || message.generation <= 0) {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'generation must be positive.');
  }
}

export function decodeWorkspaceKeyRotation(data: Uint8Array | string): WorkspaceKeyRotation {
  let value: unknown;
  try {
    value = JSON.parse(typeof data === 'string' ? data : new TextDecoder().decode(data));
  } catch {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'message is not valid JSON.');
  }
  validateMessage(value as WorkspaceKeyRotation);
  return value as WorkspaceKeyRotation;
}

export async function rotateWorkspaceSyncKey(
  options: RotateWorkspaceSyncKeyOptions
): Promise<RotatedWorkspaceSyncKey> {
  if (!options.workspaceId || !options.issuerDeviceId) {
    throw new WorkspaceKeyRotationError(
      'InvalidKeyRotation',
      'workspace and issuer device are required.'
    );
  }
  if (
    !Number.isSafeInteger(options.nextGeneration) ||
    options.nextGeneration <= 0
  ) {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'generation must be positive.');
  }

  const subtle = options.subtle ?? crypto.subtle;
  const rawKey = options.newKey
    ? new Uint8Array(options.newKey)
    : randomBytes(SYNC_KEY_BYTES);
  if (rawKey.length !== SYNC_KEY_BYTES) {
    throw new WorkspaceKeyRotationError(
      'InvalidSyncKey',
      `a workspace sync key must be ${SYNC_KEY_BYTES} bytes.`
    );
  }
  const nonce = options.nonce ? new Uint8Array(options.nonce) : randomBytes(SYNC_NONCE_BYTES);
  if (nonce.length !== SYNC_NONCE_BYTES) {
    throw new WorkspaceKeyRotationError(
      'InvalidKeyRotation',
      `nonce must be ${SYNC_NONCE_BYTES} bytes.`
    );
  }

  const header: WorkspaceKeyRotation = {
    version: WORKSPACE_KEY_ROTATION_VERSION,
    kind: WORKSPACE_KEY_ROTATION_KIND,
    workspaceId: options.workspaceId,
    issuerDeviceId: options.issuerDeviceId,
    generation: options.nextGeneration,
    nonce: bytesToBase64(nonce),
    ciphertext: ''
  };
  const ciphertext = await subtle.encrypt(
    {
      name: 'AES-GCM',
      iv: asBufferSource(nonce),
      additionalData: asBufferSource(canonicalAad(header)),
      tagLength: 128
    },
    options.currentKey,
    asBufferSource(rawKey)
  );

  return {
    key: await importWorkspaceSyncKey(rawKey),
    rawKey,
    message: {
      ...header,
      ciphertext: bytesToBase64(new Uint8Array(ciphertext))
    }
  };
}

export async function acceptWorkspaceSyncKeyRotation(
  options: AcceptWorkspaceKeyRotationOptions
): Promise<AcceptedWorkspaceKeyRotation> {
  const message = options.message;
  validateMessage(message);
  if (message.workspaceId !== options.workspaceId) {
    throw new WorkspaceKeyRotationError(
      'WorkspaceMismatch',
      'key rotation belongs to another workspace.'
    );
  }
  if (
    options.expectedIssuerDeviceId &&
    message.issuerDeviceId !== options.expectedIssuerDeviceId
  ) {
    throw new WorkspaceKeyRotationError(
      'InvalidIssuer',
      'key rotation issuer is not the expected trusted device.'
    );
  }
  if (message.generation <= options.currentGeneration) {
    throw new WorkspaceKeyRotationError(
      'GenerationReplay',
      'key rotation generation was already seen.'
    );
  }
  if (message.generation !== options.currentGeneration + 1) {
    throw new WorkspaceKeyRotationError(
      'GenerationGap',
      'key rotation skipped a generation.'
    );
  }

  const nonce = base64ToBytes(message.nonce);
  if (nonce.length !== SYNC_NONCE_BYTES) {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'nonce is not valid base64.');
  }
  const ciphertext = base64ToBytes(message.ciphertext);
  if (ciphertext.length < SYNC_TAG_BYTES + SYNC_KEY_BYTES) {
    throw new WorkspaceKeyRotationError(
      'InvalidKeyRotation',
      'ciphertext does not contain a rotated key.'
    );
  }

  const subtle = options.subtle ?? crypto.subtle;
  let rawKey: Uint8Array;
  try {
    rawKey = new Uint8Array(
      await subtle.decrypt(
        {
          name: 'AES-GCM',
          iv: asBufferSource(nonce),
          additionalData: asBufferSource(canonicalAad(message)),
          tagLength: 128
        },
        options.currentKey,
        asBufferSource(ciphertext)
      )
    );
  } catch {
    throw new WorkspaceKeyRotationError(
      'AuthenticationFailed',
      'key rotation authentication failed for this workspace key.'
    );
  }
  if (rawKey.length !== SYNC_KEY_BYTES) {
    throw new WorkspaceKeyRotationError(
      'InvalidSyncKey',
      'rotated workspace key material is invalid.'
    );
  }
  return {
    key: await importWorkspaceSyncKey(rawKey),
    rawKey,
    generation: message.generation
  };
}

export interface GrantWorkspaceSyncKeyOptions {
  rawKey: Uint8Array;
  bootstrapKey: CryptoKey;
  workspaceId: string;
  issuerDeviceId: string;
  generation: number;
  nonce?: Uint8Array;
  subtle?: SubtleCrypto;
}

export interface AcceptedWorkspaceKeyGrant {
  key: CryptoKey;
  rawKey: Uint8Array;
  generation: number;
}

export interface AcceptWorkspaceKeyGrantOptions {
  bootstrapKey: CryptoKey;
  message: WorkspaceKeyGrant;
  workspaceId: string;
  expectedIssuerDeviceId?: string;
  subtle?: SubtleCrypto;
}

function validateGrant(message: WorkspaceKeyGrant): void {
  if (!message || typeof message !== 'object') {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'a key grant object is required.');
  }
  if (message.version !== WORKSPACE_KEY_GRANT_VERSION) {
    throw new WorkspaceKeyRotationError(
      'UnsupportedVersion',
      `unsupported key grant version ${String(message.version)}.`
    );
  }
  if (message.kind !== WORKSPACE_KEY_GRANT_KIND) {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'message kind is not a key grant.');
  }
  if (!message.workspaceId || !message.issuerDeviceId) {
    throw new WorkspaceKeyRotationError(
      'InvalidKeyRotation',
      'workspace and issuer device are required.'
    );
  }
  if (!Number.isSafeInteger(message.generation) || message.generation <= 0) {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'generation must be positive.');
  }
}

export function decodeWorkspaceKeyGrant(data: Uint8Array | string): WorkspaceKeyGrant {
  let value: unknown;
  try {
    value = JSON.parse(typeof data === 'string' ? data : new TextDecoder().decode(data));
  } catch {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'message is not valid JSON.');
  }
  validateGrant(value as WorkspaceKeyGrant);
  return value as WorkspaceKeyGrant;
}

export async function grantWorkspaceSyncKey(
  options: GrantWorkspaceSyncKeyOptions
): Promise<WorkspaceKeyGrant> {
  if (!options.workspaceId || !options.issuerDeviceId) {
    throw new WorkspaceKeyRotationError(
      'InvalidKeyRotation',
      'workspace and issuer device are required.'
    );
  }
  if (!Number.isSafeInteger(options.generation) || options.generation <= 0) {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'generation must be positive.');
  }
  const rawKey = new Uint8Array(options.rawKey);
  if (rawKey.length !== SYNC_KEY_BYTES) {
    throw new WorkspaceKeyRotationError(
      'InvalidSyncKey',
      `a workspace sync key must be ${SYNC_KEY_BYTES} bytes.`
    );
  }
  const nonce = options.nonce ? new Uint8Array(options.nonce) : randomBytes(SYNC_NONCE_BYTES);
  if (nonce.length !== SYNC_NONCE_BYTES) {
    throw new WorkspaceKeyRotationError(
      'InvalidKeyRotation',
      `nonce must be ${SYNC_NONCE_BYTES} bytes.`
    );
  }
  const header: WorkspaceKeyGrant = {
    version: WORKSPACE_KEY_GRANT_VERSION,
    kind: WORKSPACE_KEY_GRANT_KIND,
    workspaceId: options.workspaceId,
    issuerDeviceId: options.issuerDeviceId,
    generation: options.generation,
    nonce: bytesToBase64(nonce),
    ciphertext: ''
  };
  const subtle = options.subtle ?? crypto.subtle;
  const ciphertext = await subtle.encrypt(
    {
      name: 'AES-GCM',
      iv: asBufferSource(nonce),
      additionalData: asBufferSource(canonicalAad(header)),
      tagLength: 128
    },
    options.bootstrapKey,
    asBufferSource(rawKey)
  );
  return {
    ...header,
    ciphertext: bytesToBase64(new Uint8Array(ciphertext))
  };
}

export async function acceptWorkspaceSyncKeyGrant(
  options: AcceptWorkspaceKeyGrantOptions
): Promise<AcceptedWorkspaceKeyGrant> {
  const message = options.message;
  validateGrant(message);
  if (message.workspaceId !== options.workspaceId) {
    throw new WorkspaceKeyRotationError(
      'WorkspaceMismatch',
      'key grant belongs to another workspace.'
    );
  }
  if (
    options.expectedIssuerDeviceId &&
    message.issuerDeviceId !== options.expectedIssuerDeviceId
  ) {
    throw new WorkspaceKeyRotationError(
      'InvalidIssuer',
      'key grant issuer is not the expected paired device.'
    );
  }
  const nonce = base64ToBytes(message.nonce);
  if (nonce.length !== SYNC_NONCE_BYTES) {
    throw new WorkspaceKeyRotationError('InvalidKeyRotation', 'nonce is not valid base64.');
  }
  const ciphertext = base64ToBytes(message.ciphertext);
  if (ciphertext.length < SYNC_TAG_BYTES + SYNC_KEY_BYTES) {
    throw new WorkspaceKeyRotationError(
      'InvalidKeyRotation',
      'ciphertext does not contain a workspace key.'
    );
  }
  const subtle = options.subtle ?? crypto.subtle;
  let rawKey: Uint8Array;
  try {
    rawKey = new Uint8Array(
      await subtle.decrypt(
        {
          name: 'AES-GCM',
          iv: asBufferSource(nonce),
          additionalData: asBufferSource(canonicalAad(message)),
          tagLength: 128
        },
        options.bootstrapKey,
        asBufferSource(ciphertext)
      )
    );
  } catch {
    throw new WorkspaceKeyRotationError(
      'AuthenticationFailed',
      'key grant is not authenticated by the pairing key.'
    );
  }
  if (rawKey.length !== SYNC_KEY_BYTES) {
    throw new WorkspaceKeyRotationError(
      'InvalidSyncKey',
      'granted workspace key material is invalid.'
    );
  }
  return {
    key: await importWorkspaceSyncKey(rawKey),
    rawKey,
    generation: message.generation
  };
}
