import { asBufferSource, bytesToHex, sha256 } from './encoding';

export type DeviceIdentityAlgorithm = 'Ed25519' | 'P-256';

export interface PersistedBrowserIdentity {
  version: 1;
  algorithm: DeviceIdentityAlgorithm;
  privateKey: CryptoKey;
  publicKey: CryptoKey;
  publicKeySpki: Uint8Array;
  createdAt: number;
}

export interface KeyStore {
  load(): Promise<PersistedBrowserIdentity | null>;
  save(identity: PersistedBrowserIdentity): Promise<void>;
  clear(): Promise<void>;
}

export class MemoryKeyStore implements KeyStore {
  private identity: PersistedBrowserIdentity | null;

  constructor(identity: PersistedBrowserIdentity | null = null) {
    this.identity = identity ? cloneIdentity(identity) : null;
  }

  async load(): Promise<PersistedBrowserIdentity | null> {
    return this.identity ? cloneIdentity(this.identity) : null;
  }

  async save(identity: PersistedBrowserIdentity): Promise<void> {
    this.identity = cloneIdentity(identity);
  }

  async clear(): Promise<void> {
    this.identity = null;
  }
}

export class IdentityExistsError extends Error {
  constructor() {
    super('browser identity already exists');
    this.name = 'IdentityExistsError';
  }
}

export class BrowserIdentityLostError extends Error {
  readonly reason: string;

  constructor(reason: string) {
    super(`browser identity lost: ${reason}`);
    this.name = 'BrowserIdentityLostError';
    this.reason = reason;
  }
}

export class BrowserIdentityAbsentError extends Error {
  constructor() {
    super('browser identity has not been provisioned');
    this.name = 'BrowserIdentityAbsentError';
  }
}

export interface DeviceSignatureVerifier {
  deviceId: string;
  algorithm: DeviceIdentityAlgorithm;
  publicKeySpki: Uint8Array;
  verify(data: Uint8Array, signature: Uint8Array): Promise<boolean>;
}

export interface BrowserDeviceIdentity extends DeviceSignatureVerifier {
  sign(data: Uint8Array): Promise<Uint8Array>;
}

export interface BrowserIdentityKeyMaterial {
  algorithm: DeviceIdentityAlgorithm;
  privateKeyPkcs8: Uint8Array;
  publicKeySpki: Uint8Array;
}

export type BrowserIdentityLoad =
  | { state: 'ready'; identity: BrowserDeviceIdentity }
  | { state: 'absent' }
  | { state: 'lost'; reason: string };

export interface BrowserIdentityOptions {
  store: KeyStore;
  subtle?: SubtleCrypto;
  now?: () => number;
  previouslyProvisioned?: boolean;
}

export interface CreateBrowserIdentityOptions extends BrowserIdentityOptions {
  replace?: boolean;
}

export interface LoadOrCreateBrowserIdentityOptions extends BrowserIdentityOptions {
  allowCreate?: boolean;
}

function cloneIdentity(identity: PersistedBrowserIdentity): PersistedBrowserIdentity {
  return { ...identity, publicKeySpki: new Uint8Array(identity.publicKeySpki) };
}

function generateKeyPair(
  subtle: SubtleCrypto,
  algorithm: DeviceIdentityAlgorithm
): Promise<CryptoKeyPair> {
  if (algorithm === 'Ed25519') {
    return subtle.generateKey({ name: 'Ed25519' }, false, ['sign', 'verify']) as Promise<CryptoKeyPair>;
  }
  return subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign', 'verify']
  ) as Promise<CryptoKeyPair>;
}

function signAlgorithm(algorithm: DeviceIdentityAlgorithm): AlgorithmIdentifier {
  return algorithm === 'Ed25519'
    ? { name: 'Ed25519' }
    : ({ name: 'ECDSA', hash: 'SHA-256' } as AlgorithmIdentifier);
}

function keyImportAlgorithm(algorithm: DeviceIdentityAlgorithm): AlgorithmIdentifier {
  return algorithm === 'Ed25519'
    ? { name: 'Ed25519' }
    : ({ name: 'ECDSA', namedCurve: 'P-256' } as AlgorithmIdentifier);
}

const ED25519_SPKI_OID = new Uint8Array([0x06, 0x03, 0x2b, 0x65, 0x70]);
const P256_SPKI_OID = new Uint8Array([
  0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07
]);

function containsBytes(haystack: Uint8Array, needle: Uint8Array): boolean {
  if (needle.length === 0 || haystack.length < needle.length) return false;
  outer: for (let index = 0; index <= haystack.length - needle.length; index += 1) {
    for (let offset = 0; offset < needle.length; offset += 1) {
      if (haystack[index + offset] !== needle[offset]) continue outer;
    }
    return true;
  }
  return false;
}

export function detectDeviceIdentityAlgorithm(
  publicKeySpki: Uint8Array
): DeviceIdentityAlgorithm | null {
  if (containsBytes(publicKeySpki, ED25519_SPKI_OID)) return 'Ed25519';
  if (containsBytes(publicKeySpki, P256_SPKI_OID)) return 'P-256';
  return null;
}

export async function selectIdentityAlgorithm(
  subtle: SubtleCrypto = crypto.subtle
): Promise<DeviceIdentityAlgorithm> {
  try {
    await subtle.generateKey({ name: 'Ed25519' }, false, ['sign', 'verify']);
    return 'Ed25519';
  } catch {
    await subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign', 'verify']);
    return 'P-256';
  }
}

export async function deriveDeviceId(
  publicKeySpki: Uint8Array,
  subtle: SubtleCrypto = crypto.subtle
): Promise<string> {
  return `ad-device:${bytesToHex(await sha256(publicKeySpki, subtle))}`;
}

export async function createDeviceSignatureVerifier(
  publicKeySpki: Uint8Array,
  algorithm: DeviceIdentityAlgorithm,
  subtle: SubtleCrypto = crypto.subtle
): Promise<DeviceSignatureVerifier> {
  if (publicKeySpki.length === 0) throw new Error('device public key is missing');
  const publicKey = await subtle.importKey(
    'spki',
    asBufferSource(publicKeySpki),
    keyImportAlgorithm(algorithm),
    true,
    ['verify']
  );
  return {
    deviceId: await deriveDeviceId(publicKeySpki, subtle),
    algorithm,
    publicKeySpki: new Uint8Array(publicKeySpki),
    async verify(data: Uint8Array, signature: Uint8Array): Promise<boolean> {
      if (signature.length === 0) return false;
      return subtle.verify(
        signAlgorithm(algorithm),
        publicKey,
        asBufferSource(signature),
        asBufferSource(data)
      );
    }
  };
}

export async function importBrowserIdentity(
  material: BrowserIdentityKeyMaterial,
  options: BrowserIdentityOptions
): Promise<BrowserDeviceIdentity> {
  const subtle = options.subtle ?? crypto.subtle;
  const algorithm = material.algorithm;
  if (algorithm !== 'Ed25519' && algorithm !== 'P-256') {
    throw new Error('unsupported identity algorithm');
  }
  if (material.publicKeySpki.length === 0) throw new Error('identity public key missing');

  const privateKey = await subtle.importKey(
    'pkcs8',
    asBufferSource(material.privateKeyPkcs8),
    keyImportAlgorithm(algorithm),
    false,
    ['sign']
  );
  const publicKey = await subtle.importKey(
    'spki',
    asBufferSource(material.publicKeySpki),
    keyImportAlgorithm(algorithm),
    true,
    ['verify']
  );
  const record: PersistedBrowserIdentity = {
    version: 1,
    algorithm,
    privateKey,
    publicKey,
    publicKeySpki: new Uint8Array(material.publicKeySpki),
    createdAt: options.now?.() ?? Date.now()
  };
  await options.store.save(record);
  return identityFromRecord(record, subtle);
}

async function identityFromRecord(
  record: PersistedBrowserIdentity,
  subtle: SubtleCrypto
): Promise<BrowserDeviceIdentity> {
  if (record.version !== 1) throw new Error('unsupported identity record');
  if (record.algorithm !== 'Ed25519' && record.algorithm !== 'P-256') {
    throw new Error('unsupported identity algorithm');
  }
  if (!record.privateKey || !record.publicKey) throw new Error('identity key material missing');

  const publicKeySpki = new Uint8Array(record.publicKeySpki);
  if (publicKeySpki.length === 0) throw new Error('identity public key missing');

  return {
    deviceId: await deriveDeviceId(publicKeySpki, subtle),
    algorithm: record.algorithm,
    publicKeySpki,
    async sign(data: Uint8Array): Promise<Uint8Array> {
      return new Uint8Array(
        await subtle.sign(
          signAlgorithm(record.algorithm),
          record.privateKey,
          asBufferSource(data)
        )
      );
    },
    async verify(data: Uint8Array, signature: Uint8Array): Promise<boolean> {
      return subtle.verify(
        signAlgorithm(record.algorithm),
        record.publicKey,
        asBufferSource(signature),
        asBufferSource(data)
      );
    }
  };
}

export async function createBrowserIdentity(
  options: CreateBrowserIdentityOptions
): Promise<BrowserDeviceIdentity> {
  const subtle = options.subtle ?? crypto.subtle;
  const existing = await options.store.load();
  if (existing && !options.replace) throw new IdentityExistsError();

  const algorithm = await selectIdentityAlgorithm(subtle);
  const keyPair = await generateKeyPair(subtle, algorithm);
  const publicKeySpki = new Uint8Array(await subtle.exportKey('spki', keyPair.publicKey));
  const record: PersistedBrowserIdentity = {
    version: 1,
    algorithm,
    privateKey: keyPair.privateKey,
    publicKey: keyPair.publicKey,
    publicKeySpki,
    createdAt: options.now?.() ?? Date.now()
  };

  await options.store.save(record);
  return identityFromRecord(record, subtle);
}

export async function loadBrowserIdentity(
  options: BrowserIdentityOptions
): Promise<BrowserIdentityLoad> {
  const subtle = options.subtle ?? crypto.subtle;
  let record: PersistedBrowserIdentity | null;

  try {
    record = await options.store.load();
  } catch (error) {
    return {
      state: 'lost',
      reason: error instanceof Error ? error.message : 'identity-store-unreadable'
    };
  }

  if (!record) {
    return options.previouslyProvisioned
      ? { state: 'lost', reason: 'identity-missing' }
      : { state: 'absent' };
  }

  try {
    return { state: 'ready', identity: await identityFromRecord(record, subtle) };
  } catch (error) {
    return {
      state: 'lost',
      reason: error instanceof Error ? error.message : 'identity-record-invalid'
    };
  }
}

export async function loadOrCreateBrowserIdentity(
  options: LoadOrCreateBrowserIdentityOptions
): Promise<BrowserDeviceIdentity> {
  const loaded = await loadBrowserIdentity(options);
  if (loaded.state === 'ready') return loaded.identity;
  if (loaded.state === 'lost') throw new BrowserIdentityLostError(loaded.reason);
  if (!options.allowCreate) throw new BrowserIdentityAbsentError();
  return createBrowserIdentity(options);
}
