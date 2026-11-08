import { bytesToBase64Url, bytesToHex, sha256 } from './encoding';
import { PairingValidationError } from './pairing-payload';
import type { PairingChannelBinding } from './pairing-payload';

export interface DtlsCertificateSource {
  getRemoteCertificates(): ArrayBuffer[];
}

export interface WebTransportHash {
  algorithm: string;
  value: ArrayBuffer | ArrayBufferView;
}

function bytesFrom(value: ArrayBuffer | ArrayBufferView): Uint8Array {
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  return new Uint8Array(value);
}

export function exporterChannelBinding(
  exporter: ArrayBuffer | Uint8Array
): PairingChannelBinding {
  const value = bytesFrom(exporter);
  if (value.length < 16) {
    throw new PairingValidationError('invalid-binding', 'exporter binding is too short');
  }
  return { kind: 'exporter', value: bytesToBase64Url(value) };
}

export async function certificateHashChannelBinding(
  certificate: ArrayBuffer | Uint8Array,
  subtle: SubtleCrypto = crypto.subtle
): Promise<PairingChannelBinding> {
  const value = bytesFrom(certificate);
  if (value.length === 0) {
    throw new PairingValidationError('invalid-binding', 'certificate is empty');
  }
  return { kind: 'certificate-hash', value: bytesToHex(await sha256(value, subtle)) };
}

export async function dtlsCertificateChannelBinding(
  transport: DtlsCertificateSource,
  subtle: SubtleCrypto = crypto.subtle
): Promise<PairingChannelBinding> {
  const certificates = transport.getRemoteCertificates();
  if (certificates.length === 0) {
    throw new PairingValidationError(
      'missing-binding',
      'DTLS transport has no remote certificate'
    );
  }
  return certificateHashChannelBinding(certificates[0]!, subtle);
}

export function webTransportHashChannelBinding(
  hashes: readonly WebTransportHash[]
): PairingChannelBinding {
  if (hashes.length === 0) {
    throw new PairingValidationError(
      'missing-binding',
      'WebTransport configuration has no server certificate hash'
    );
  }
  if (hashes.length !== 1) {
    throw new PairingValidationError(
      'invalid-binding',
      'WebTransport server certificate hash is ambiguous'
    );
  }
  const hash = hashes[0]!;
  if (hash.algorithm.toLowerCase() !== 'sha-256') {
    throw new PairingValidationError(
      'invalid-binding',
      'WebTransport certificate hash must use SHA-256'
    );
  }
  const value = bytesFrom(hash.value);
  if (value.length !== 32) {
    throw new PairingValidationError(
      'invalid-binding',
      'WebTransport certificate hash must be 32 bytes'
    );
  }
  return { kind: 'certificate-hash', value: bytesToHex(value) };
}

export function dtlsFingerprintChannelBinding(sdp: string): PairingChannelBinding {
  const pattern = /^a=fingerprint:([A-Za-z0-9-]+)[ \t]+([0-9A-Fa-f:]+)[ \t]*$/gim;
  const hashes = new Set<string>();
  for (const match of sdp.matchAll(pattern)) {
    const algorithm = match[1]!.toLowerCase();
    if (algorithm !== 'sha-256') {
      throw new PairingValidationError(
        'invalid-binding',
        'DTLS fingerprint must use SHA-256'
      );
    }
    const value = match[2]!.replace(/:/g, '').toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(value)) {
      throw new PairingValidationError('invalid-binding', 'invalid DTLS fingerprint');
    }
    hashes.add(value);
  }
  if (hashes.size === 0) {
    throw new PairingValidationError('missing-binding', 'SDP has no DTLS fingerprint');
  }
  if (hashes.size !== 1) {
    throw new PairingValidationError(
      'invalid-binding',
      'SDP has conflicting DTLS fingerprints'
    );
  }
  return { kind: 'certificate-hash', value: [...hashes][0]! };
}
