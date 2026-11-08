import { bytesToBase64Url, bytesToHex, sha256 } from './encoding';
import { PairingValidationError } from './pairing-payload';
import type { PairingChannelBinding } from './pairing-payload';

export interface DtlsCertificateSource {
  getRemoteCertificates(): ArrayBuffer[];
}

function bytesFrom(value: ArrayBuffer | Uint8Array): Uint8Array {
  return value instanceof Uint8Array ? value : new Uint8Array(value);
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
