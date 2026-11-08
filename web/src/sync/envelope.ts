export const SYNC_ENVELOPE_VERSION = 1;
export const SYNC_NONCE_BYTES = 12;
export const SYNC_TAG_BYTES = 16;
export const SYNC_KEY_BYTES = 32;

export interface SyncEnvelope {
  version: number;
  workspaceId: string;
  senderDeviceId: string;
  hostEpoch: number;
  syncSeq: number;
  nonce: string;
  ciphertext: string;
  aad: string;
}

export type SyncEnvelopeErrorCode =
  | 'InvalidEnvelope'
  | 'UnsupportedVersion'
  | 'WorkspaceMismatch'
  | 'EpochMismatch'
  | 'DeviceMismatch'
  | 'SenderRevoked'
  | 'StaleSequence'
  | 'TruncatedCiphertext'
  | 'AuthenticationFailed';

export class SyncEnvelopeError extends Error {
  readonly code: SyncEnvelopeErrorCode;

  constructor(code: SyncEnvelopeErrorCode, message: string) {
    super(`${code}: ${message}`);
    this.name = 'SyncEnvelopeError';
    this.code = code;
  }
}

export class SyncKeyError extends Error {
  readonly code = 'InvalidSyncKey';

  constructor(message: string) {
    super(`InvalidSyncKey: ${message}`);
    this.name = 'SyncKeyError';
  }
}

const textEncoder = new TextEncoder();

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function toBytes(value: string | Uint8Array): Uint8Array {
  return typeof value === 'string' ? textEncoder.encode(value) : value;
}

function ownedBytes(value: Uint8Array): Uint8Array<ArrayBuffer> {
  const copy = new Uint8Array(new ArrayBuffer(value.byteLength));
  copy.set(value);
  return copy;
}

function decodeBase64(value: string, label: string): Uint8Array {
  try {
    return base64ToBytes(value);
  } catch {
    throw new SyncEnvelopeError('InvalidEnvelope', `${label} is not valid base64.`);
  }
}

function envelopeAad(
  header: Pick<
    SyncEnvelope,
    'version' | 'workspaceId' | 'senderDeviceId' | 'hostEpoch' | 'syncSeq' | 'aad'
  >
): Uint8Array {
  return textEncoder.encode(
    JSON.stringify([
      header.version,
      header.workspaceId,
      header.senderDeviceId,
      header.hostEpoch,
      header.syncSeq,
      header.aad
    ])
  );
}

export async function importWorkspaceSyncKey(rawKey: Uint8Array): Promise<CryptoKey> {
  if (rawKey.length !== SYNC_KEY_BYTES) {
    throw new SyncKeyError(`a workspace sync key must be ${SYNC_KEY_BYTES} bytes.`);
  }
  return crypto.subtle.importKey('raw', ownedBytes(rawKey), { name: 'AES-GCM' }, false, [
    'encrypt',
    'decrypt'
  ]);
}

export const PAIRING_SYNC_SALT = 'airdesk.sync.v1';
export const PAIRING_SYNC_INFO = 'pairing-workspace-sync';

export async function derivePairingWorkspaceSyncKeyBytes(
  secret: Uint8Array
): Promise<Uint8Array> {
  if (secret.length < SYNC_TAG_BYTES) {
    throw new SyncKeyError('pairing sync key material is too short.');
  }

  const material = await crypto.subtle.importKey('raw', ownedBytes(secret), 'HKDF', false, [
    'deriveBits'
  ]);
  const bits = await crypto.subtle.deriveBits(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: textEncoder.encode(PAIRING_SYNC_SALT),
      info: textEncoder.encode(PAIRING_SYNC_INFO)
    },
    material,
    SYNC_KEY_BYTES * 8
  );
  return new Uint8Array(bits);
}

export async function derivePairingWorkspaceSyncKey(secret: Uint8Array): Promise<CryptoKey> {
  return importWorkspaceSyncKey(await derivePairingWorkspaceSyncKeyBytes(secret));
}

export async function deriveWorkspaceSyncKey(
  secret: Uint8Array,
  workspaceId: string
): Promise<CryptoKey> {
  if (secret.length < SYNC_TAG_BYTES) {
    throw new SyncKeyError('workspace sync key material is too short.');
  }
  if (!workspaceId) {
    throw new SyncKeyError('a workspace identifier is required.');
  }

  const material = await crypto.subtle.importKey('raw', ownedBytes(secret), 'HKDF', false, [
    'deriveKey'
  ]);
  return crypto.subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: textEncoder.encode('airdesk.sync.v1'),
      info: textEncoder.encode(`workspace:${workspaceId}`)
    },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

export interface EncryptSyncEnvelopeOptions {
  key: CryptoKey;
  workspaceId: string;
  senderDeviceId: string;
  hostEpoch: number;
  syncSeq: number;
  plaintext: string | Uint8Array;
  aad?: string | Uint8Array;
  nonce?: Uint8Array;
}

export async function encryptSyncEnvelope(
  options: EncryptSyncEnvelopeOptions
): Promise<SyncEnvelope> {
  if (!options.workspaceId || !options.senderDeviceId) {
    throw new SyncEnvelopeError('InvalidEnvelope', 'workspace and sender device are required.');
  }
  if (!Number.isInteger(options.hostEpoch) || !Number.isInteger(options.syncSeq)) {
    throw new SyncEnvelopeError('InvalidEnvelope', 'epoch and sequence must be integers.');
  }

  const nonce = options.nonce ?? crypto.getRandomValues(new Uint8Array(SYNC_NONCE_BYTES));
  if (nonce.length !== SYNC_NONCE_BYTES) {
    throw new SyncEnvelopeError(
      'InvalidEnvelope',
      `nonce must be ${SYNC_NONCE_BYTES} bytes.`
    );
  }

  const header: Omit<SyncEnvelope, 'nonce' | 'ciphertext'> = {
    version: SYNC_ENVELOPE_VERSION,
    workspaceId: options.workspaceId,
    senderDeviceId: options.senderDeviceId,
    hostEpoch: options.hostEpoch,
    syncSeq: options.syncSeq,
    aad: options.aad ? bytesToBase64(toBytes(options.aad)) : ''
  };

  const ciphertext = await crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv: ownedBytes(nonce),
      additionalData: ownedBytes(envelopeAad(header)),
      tagLength: 128
    },
    options.key,
    ownedBytes(toBytes(options.plaintext))
  );

  return {
    ...header,
    nonce: bytesToBase64(nonce),
    ciphertext: bytesToBase64(new Uint8Array(ciphertext))
  };
}

export interface SyncEnvelopeExpectations {
  workspaceId: string;
  hostEpoch: number;
  senderDeviceId?: string;
  revokedSenderDeviceIds?: readonly string[];
  lastSyncSeq?: number;
}

export interface DecryptSyncEnvelopeOptions {
  key: CryptoKey;
  envelope: SyncEnvelope;
  expected: SyncEnvelopeExpectations;
}

export interface DecryptedSyncEnvelope {
  plaintext: Uint8Array;
  envelope: SyncEnvelope;
}

export async function decryptSyncEnvelope(
  options: DecryptSyncEnvelopeOptions
): Promise<DecryptedSyncEnvelope> {
  const { envelope, expected } = options;

  if (!envelope || typeof envelope !== 'object') {
    throw new SyncEnvelopeError('InvalidEnvelope', 'an envelope object is required.');
  }
  if (envelope.version !== SYNC_ENVELOPE_VERSION) {
    throw new SyncEnvelopeError(
      'UnsupportedVersion',
      `unsupported envelope version ${String(envelope.version)}.`
    );
  }
  if (!envelope.workspaceId || !envelope.senderDeviceId) {
    throw new SyncEnvelopeError('InvalidEnvelope', 'workspace and sender device are required.');
  }
  if (!Number.isInteger(envelope.hostEpoch) || !Number.isInteger(envelope.syncSeq)) {
    throw new SyncEnvelopeError('InvalidEnvelope', 'epoch and sequence must be integers.');
  }
  if (envelope.workspaceId !== expected.workspaceId) {
    throw new SyncEnvelopeError('WorkspaceMismatch', 'envelope belongs to another workspace.');
  }
  if (envelope.hostEpoch !== expected.hostEpoch) {
    throw new SyncEnvelopeError('EpochMismatch', 'envelope belongs to another host epoch.');
  }
  if (expected.senderDeviceId && envelope.senderDeviceId !== expected.senderDeviceId) {
    throw new SyncEnvelopeError('DeviceMismatch', 'envelope sender device does not match.');
  }
  if (expected.revokedSenderDeviceIds?.includes(envelope.senderDeviceId)) {
    throw new SyncEnvelopeError('SenderRevoked', 'envelope sender device is revoked.');
  }
  if (expected.lastSyncSeq !== undefined && envelope.syncSeq <= expected.lastSyncSeq) {
    throw new SyncEnvelopeError('StaleSequence', 'envelope sequence was already applied.');
  }

  const nonce = decodeBase64(envelope.nonce, 'nonce');
  if (nonce.length !== SYNC_NONCE_BYTES) {
    throw new SyncEnvelopeError(
      'InvalidEnvelope',
      `nonce must be ${SYNC_NONCE_BYTES} bytes.`
    );
  }

  const ciphertext = decodeBase64(envelope.ciphertext, 'ciphertext');
  if (ciphertext.length < SYNC_TAG_BYTES) {
    throw new SyncEnvelopeError('TruncatedCiphertext', 'ciphertext is shorter than its tag.');
  }

  let plaintext: ArrayBuffer;
  try {
    plaintext = await crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: ownedBytes(nonce),
        additionalData: ownedBytes(envelopeAad(envelope)),
        tagLength: 128
      },
      options.key,
      ownedBytes(ciphertext)
    );
  } catch {
    throw new SyncEnvelopeError(
      'AuthenticationFailed',
      'envelope authentication failed for this key and metadata.'
    );
  }

  return { plaintext: new Uint8Array(plaintext), envelope: { ...envelope } };
}

export function decodeSyncPlaintext(value: Uint8Array): string {
  return new TextDecoder().decode(value);
}
