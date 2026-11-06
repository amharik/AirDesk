import { base64UrlToBytes, bytesEqual, concatBytes, sha256, utf8 } from './encoding';
import { PairingValidationError } from './pairing-payload';
import type { PairingPayload } from './pairing-payload';
import type { Spake2PlusEvidence } from './pake';

export const AD_PAIR_TRANSCRIPT_DOMAIN = 'AD-PAIR-1';
export const AD_PAIR_SAS_DOMAIN = 'AD-PAIR-1-SAS';

export interface PairingTranscriptInput {
  offer: PairingPayload;
  response: PairingPayload;
  pake: Spake2PlusEvidence;
}

interface CanonicalPayload {
  type: string;
  deviceId: string;
  publicKey: string;
  nonce: string;
  replyTo: string | null;
  expiresAt: number;
  endpointHint: string | null;
  relayHint: string | null;
  capabilities: string[];
  channelBinding: { kind: string; value: string };
}

function canonicalPayload(payload: PairingPayload): CanonicalPayload {
  return {
    type: payload.type,
    deviceId: payload.deviceId,
    publicKey: payload.publicKey,
    nonce: payload.nonce,
    replyTo: payload.replyTo ?? null,
    expiresAt: payload.expiresAt,
    endpointHint: payload.endpointHint ?? null,
    relayHint: payload.relayHint ?? null,
    capabilities: [...payload.capabilities].sort(),
    channelBinding: {
      kind: payload.channelBinding.kind,
      value: payload.channelBinding.value
    }
  };
}

function evidenceValue(value: string, name: string): string {
  let bytes: Uint8Array;
  try {
    bytes = base64UrlToBytes(value);
  } catch {
    throw new PairingValidationError('invalid-pake-evidence', `invalid ${name}`);
  }
  if (bytes.length < 16 || bytes.length > 1024) {
    throw new PairingValidationError('invalid-pake-evidence', `${name} length out of range`);
  }
  return value;
}

export function normalizedPakeEvidence(pake: Spake2PlusEvidence): Spake2PlusEvidence {
  return {
    initiatorShare: evidenceValue(pake.initiatorShare, 'initiator share'),
    responderShare: evidenceValue(pake.responderShare, 'responder share'),
    initiatorConfirmation: evidenceValue(pake.initiatorConfirmation, 'initiator confirmation'),
    responderConfirmation: evidenceValue(pake.responderConfirmation, 'responder confirmation')
  };
}

export function canonicalPairingTranscript(input: PairingTranscriptInput): Uint8Array {
  const pake = normalizedPakeEvidence(input.pake);
  const canonical = {
    domain: AD_PAIR_TRANSCRIPT_DOMAIN,
    protocol: input.offer.protocol,
    version: input.offer.version,
    offer: canonicalPayload(input.offer),
    response: canonicalPayload(input.response),
    pake: {
      initiatorShare: pake.initiatorShare,
      responderShare: pake.responderShare,
      initiatorConfirmation: pake.initiatorConfirmation,
      responderConfirmation: pake.responderConfirmation
    }
  };
  return concatBytes(utf8(`${AD_PAIR_TRANSCRIPT_DOMAIN}\n`), utf8(JSON.stringify(canonical)));
}

export async function computePairingTranscriptHash(
  input: PairingTranscriptInput,
  subtle: SubtleCrypto = crypto.subtle
): Promise<Uint8Array> {
  return sha256(canonicalPairingTranscript(input), subtle);
}

export async function deriveShortAuthenticationString(
  transcriptHash: Uint8Array,
  subtle: SubtleCrypto = crypto.subtle
): Promise<string> {
  const digest = await sha256(
    concatBytes(utf8(`${AD_PAIR_SAS_DOMAIN}\n`), transcriptHash),
    subtle
  );
  const view = new DataView(digest.buffer, digest.byteOffset, digest.byteLength);
  return (view.getUint32(0, false) % 1_000_000).toString().padStart(6, '0');
}

export function assertTranscriptHash(
  expected: Uint8Array,
  actual: Uint8Array
): void {
  if (!bytesEqual(expected, actual)) {
    throw new PairingValidationError('transcript-mismatch', 'pairing transcript mismatch');
  }
}

export function combineRequestedCapabilities(
  offer: PairingPayload,
  response: PairingPayload
): string[] {
  return [...new Set([...offer.capabilities, ...response.capabilities])].sort();
}
