import {
  bytesEqual,
  bytesToBase64Url,
  sha256
} from '../identity/encoding';
import type {
  DeviceIdentityAlgorithm,
  DeviceSignatureVerifier
} from '../identity/identity';
import { encodeCbor } from './cbor';
import { CapabilityGrantError } from './grant';
import type { VerifiedCapabilityGrant } from './grant';

export const CAPABILITY_POSSESSION_DOMAIN = 'AD-CAP-POP-1';

export interface CapabilityPossessionSigner {
  algorithm: DeviceIdentityAlgorithm;
  sign(data: Uint8Array): Promise<Uint8Array>;
}

export interface CapabilityPossessionProof {
  algorithm: DeviceIdentityAlgorithm;
  signature: Uint8Array;
  nonce?: Uint8Array;
}

export interface VerifyCapabilityPossessionOptions {
  requestNonce?: Uint8Array;
}

function fail(message: string, code: 'missing-proof' | 'proof-not-required' | 'proof-mismatch' | 'confirmation-mismatch' | 'unsupported-algorithm'): never {
  throw new CapabilityGrantError(code, message);
}

export async function capabilityConfirmationThumbprint(
  publicKeySpki: Uint8Array
): Promise<string> {
  if (publicKeySpki.length === 0) {
    fail('confirmation key is missing', 'confirmation-mismatch');
  }
  return bytesToBase64Url(await sha256(publicKeySpki));
}

export function capabilityPossessionChallenge(
  grant: Pick<VerifiedCapabilityGrant, 'tokenHash'>,
  nonce?: Uint8Array
): Uint8Array {
  if (grant.tokenHash.length !== 32) {
    fail('grant token hash is invalid', 'proof-mismatch');
  }
  return encodeCbor([
    CAPABILITY_POSSESSION_DOMAIN,
    grant.tokenHash,
    nonce ?? null
  ]);
}

export async function signCapabilityPossession(
  grant: Pick<VerifiedCapabilityGrant, 'tokenHash'>,
  signer: CapabilityPossessionSigner,
  nonce?: Uint8Array
): Promise<CapabilityPossessionProof> {
  const signature = await signer.sign(capabilityPossessionChallenge(grant, nonce));
  if (signature.length === 0 || signature.length > 128) {
    fail('proof signature is invalid', 'proof-mismatch');
  }
  return {
    algorithm: signer.algorithm,
    signature,
    ...(nonce === undefined ? {} : { nonce: new Uint8Array(nonce) })
  };
}

export async function verifyCapabilityPossession(
  grant: VerifiedCapabilityGrant,
  proof: CapabilityPossessionProof,
  verifier: DeviceSignatureVerifier,
  options: VerifyCapabilityPossessionOptions = {}
): Promise<void> {
  if (grant.claims.cnf === undefined) {
    fail('grant does not require proof of possession', 'proof-not-required');
  }
  if (!(proof.signature instanceof Uint8Array) || proof.signature.length === 0) {
    fail('proof of possession is missing', 'missing-proof');
  }
  if (proof.algorithm !== verifier.algorithm) {
    fail('proof algorithm does not match the confirmation key', 'unsupported-algorithm');
  }
  if (
    options.requestNonce !== undefined &&
    proof.nonce !== undefined &&
    !bytesEqual(options.requestNonce, proof.nonce)
  ) {
    fail('proof nonce does not match the request', 'proof-mismatch');
  }

  const thumbprint = await capabilityConfirmationThumbprint(verifier.publicKeySpki);
  if (thumbprint !== grant.claims.cnf) {
    fail('confirmation key does not match the grant', 'confirmation-mismatch');
  }

  const nonce = options.requestNonce ?? proof.nonce;
  const valid = await verifier.verify(
    capabilityPossessionChallenge(grant, nonce),
    proof.signature
  );
  if (!valid) fail('proof of possession signature is invalid', 'proof-mismatch');
}
