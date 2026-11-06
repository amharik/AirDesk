import { asBufferSource, bytesToHex, utf8 } from './encoding';
import { PairingValidationError } from './pairing-payload';
import type { PairingChannelBinding } from './pairing-payload';
import { requireChannelBinding } from './transcript';

export const AD_PAIR_KEY_SCHEDULE_VERSION = 1 as const;
export const AD_PAIR_KEY_SCHEDULE_DOMAIN = 'AD-PAIR-1-KS';
export const AD_PAIR_SESSION_KEY_BYTES = 32;

export type AdPairSessionKeyPurpose =
  | 'initiator-to-responder'
  | 'responder-to-initiator'
  | 'transport';

export interface AdPairSessionKey {
  readonly version: typeof AD_PAIR_KEY_SCHEDULE_VERSION;
  readonly purpose: AdPairSessionKeyPurpose;
  readonly algorithm: 'HKDF-SHA256';
  readonly label: string;
  readonly bytes: Uint8Array;
}

export interface AdPairSessionKeys {
  readonly version: typeof AD_PAIR_KEY_SCHEDULE_VERSION;
  readonly schedule: typeof AD_PAIR_KEY_SCHEDULE_DOMAIN;
  readonly channelBinding: PairingChannelBinding;
  readonly transcriptHash: Uint8Array;
  readonly initiatorToResponder: AdPairSessionKey;
  readonly responderToInitiator: AdPairSessionKey;
  readonly transport: AdPairSessionKey;
}

export interface DeriveAdPairSessionKeysInput {
  pakeSharedSecret: Uint8Array;
  transcriptHash: Uint8Array;
  channelBinding: PairingChannelBinding;
  subtle?: SubtleCrypto;
}

interface KeyLabel {
  purpose: AdPairSessionKeyPurpose;
  label: string;
}

const KEY_LABELS: readonly KeyLabel[] = Object.freeze([
  { purpose: 'initiator-to-responder', label: 'i2r' },
  { purpose: 'responder-to-initiator', label: 'r2i' },
  { purpose: 'transport', label: 'transport' }
]);

function keyInfo(
  label: string,
  channelBinding: PairingChannelBinding,
  transcriptHash: Uint8Array
): Uint8Array {
  return utf8(
    JSON.stringify({
      domain: AD_PAIR_KEY_SCHEDULE_DOMAIN,
      version: AD_PAIR_KEY_SCHEDULE_VERSION,
      label,
      channelBinding: {
        kind: channelBinding.kind,
        value: channelBinding.value
      },
      transcriptHash: bytesToHex(transcriptHash)
    })
  );
}

export async function deriveAdPairSessionKeys(
  input: DeriveAdPairSessionKeysInput
): Promise<AdPairSessionKeys> {
  if (input.pakeSharedSecret.length < 16 || input.pakeSharedSecret.length > 1024) {
    throw new PairingValidationError(
      'invalid-pake-evidence',
      'PAKE shared secret length out of range'
    );
  }
  if (input.transcriptHash.length !== 32) {
    throw new PairingValidationError(
      'transcript-mismatch',
      'AD-PAIR-1 transcript hash must be 32 bytes'
    );
  }
  const channelBinding = requireChannelBinding(input.channelBinding);
  const subtle = input.subtle ?? crypto.subtle;
  const material = await subtle.importKey(
    'raw',
    asBufferSource(input.pakeSharedSecret),
    'HKDF',
    false,
    ['deriveBits']
  );

  const derived = new Map<AdPairSessionKeyPurpose, AdPairSessionKey>();
  for (const { purpose, label } of KEY_LABELS) {
    const bits = await subtle.deriveBits(
      {
        name: 'HKDF',
        hash: 'SHA-256',
        salt: asBufferSource(input.transcriptHash),
        info: asBufferSource(keyInfo(label, channelBinding, input.transcriptHash))
      },
      material,
      AD_PAIR_SESSION_KEY_BYTES * 8
    );
    derived.set(purpose, {
      version: AD_PAIR_KEY_SCHEDULE_VERSION,
      purpose,
      algorithm: 'HKDF-SHA256',
      label,
      bytes: new Uint8Array(bits)
    });
  }

  const initiatorToResponder = derived.get('initiator-to-responder');
  const responderToInitiator = derived.get('responder-to-initiator');
  const transport = derived.get('transport');
  if (!initiatorToResponder || !responderToInitiator || !transport) {
    throw new PairingValidationError('invalid-state', 'AD-PAIR-1 key schedule incomplete');
  }

  return {
    version: AD_PAIR_KEY_SCHEDULE_VERSION,
    schedule: AD_PAIR_KEY_SCHEDULE_DOMAIN,
    channelBinding,
    transcriptHash: new Uint8Array(input.transcriptHash),
    initiatorToResponder,
    responderToInitiator,
    transport
  };
}
