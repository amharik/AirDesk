import {
  PairingValidationError,
  parsePairingJson,
  validatePairingPayload
} from './pairing-payload';
import type {
  PairingChannelBinding,
  PairingParseOptions,
  PairingPayload
} from './pairing-payload';
import { base64UrlToBytes, bytesEqual } from './encoding';
import {
  createDeviceSignatureVerifier,
  deriveDeviceId,
  detectDeviceIdentityAlgorithm
} from './identity';
import type { DeviceSignatureVerifier } from './identity';
import type { Spake2PlusExchangeResult, Spake2PlusPrimitive } from './pake';
import { NonceReplayGuard } from './replay';
import type { DeviceRegistry } from './registry';
import { deriveAdPairSessionKeys } from './session-keys';
import type { AdPairSessionKeys } from './session-keys';
import {
  assertMatchingChannelBinding,
  assertTranscriptHash,
  canonicalPairingTranscript,
  combineRequestedCapabilities,
  computePairingTranscriptHash,
  deriveShortAuthenticationString,
  normalizedPakeEvidence,
  requireChannelBinding,
  verifyPairingTranscriptSignature
} from './transcript';

export type AdPairState =
  | 'initial'
  | 'offer-accepted'
  | 'response-accepted'
  | 'completed'
  | 'failed';

export interface PairingGrantBoundary {
  trusted: true;
  workspaceOwnership: false;
  workspaceMembership: false;
  controllerRole: false;
  grantedCapabilities: readonly string[];
}

export const PAIRING_GRANT_BOUNDARY: PairingGrantBoundary = Object.freeze({
  trusted: true,
  workspaceOwnership: false,
  workspaceMembership: false,
  controllerRole: false,
  grantedCapabilities: Object.freeze([]) as readonly string[]
});

export interface AdPairSessionOptions {
  pake?: Spake2PlusPrimitive;
  pakeExchange?: Spake2PlusExchangeResult;
  now?: () => number;
  replayGuard?: NonceReplayGuard;
  registry?: DeviceRegistry;
  subtle?: SubtleCrypto;
  initiatorVerifier?: DeviceSignatureVerifier;
  responderVerifier?: DeviceSignatureVerifier;
}

export interface AdPairFinishInput {
  secret?: Uint8Array;
  expectedTranscriptHash?: Uint8Array;
  initiatorSignature?: Uint8Array;
  responderSignature?: Uint8Array;
}

export interface AdPairSignatures {
  initiator: Uint8Array;
  responder: Uint8Array;
}

export interface AdPairResult {
  state: 'completed';
  offer: PairingPayload;
  response: PairingPayload;
  transcript: Uint8Array;
  transcriptHash: Uint8Array;
  shortAuthenticationString: string;
  channelBinding: PairingChannelBinding;
  requestedCapabilities: readonly string[];
  signatures: AdPairSignatures;
  sessionKeys: AdPairSessionKeys;
  keyScheduleVersion: AdPairSessionKeys['version'];
  grants: PairingGrantBoundary;
}

function parseRaw(raw: string | unknown, options: PairingParseOptions): PairingPayload {
  return typeof raw === 'string'
    ? parsePairingJson(raw, options)
    : validatePairingPayload(raw, options);
}

function sameBinding(left: PairingChannelBinding, right: PairingChannelBinding): boolean {
  return left.kind === right.kind && left.value === right.value;
}

async function resolveVerifier(
  role: 'initiator' | 'responder',
  payload: PairingPayload,
  verifier: DeviceSignatureVerifier | undefined,
  subtle: SubtleCrypto
): Promise<DeviceSignatureVerifier> {
  let publicKeySpki: Uint8Array;
  try {
    publicKeySpki = base64UrlToBytes(payload.publicKey);
  } catch {
    throw new PairingValidationError('invalid-public-key', `${role} public key is invalid`);
  }

  const expectedDeviceId = await deriveDeviceId(publicKeySpki, subtle);
  if (expectedDeviceId !== payload.deviceId) {
    throw new PairingValidationError(
      'signature-device-mismatch',
      `${role} device id does not match its public key`
    );
  }

  if (verifier) {
    if (
      verifier.deviceId !== expectedDeviceId ||
      !bytesEqual(new Uint8Array(verifier.publicKeySpki), publicKeySpki)
    ) {
      throw new PairingValidationError(
        'signature-device-mismatch',
        `${role} verifier does not match the pairing payload`
      );
    }
    return verifier;
  }

  const algorithm = detectDeviceIdentityAlgorithm(publicKeySpki);
  if (!algorithm) {
    throw new PairingValidationError(
      'invalid-public-key',
      `${role} public key algorithm is unsupported`
    );
  }
  return createDeviceSignatureVerifier(publicKeySpki, algorithm, subtle);
}

function requireSignature(value: Uint8Array | undefined, role: string): Uint8Array {
  if (!value || value.length === 0) {
    throw new PairingValidationError('missing-signature', `${role} signature is required`);
  }
  return value;
}

function decodePakeSharedSecret(value: string): Uint8Array {
  let bytes: Uint8Array;
  try {
    bytes = base64UrlToBytes(value);
  } catch {
    throw new PairingValidationError('invalid-pake-evidence', 'invalid PAKE shared secret');
  }
  if (bytes.length < 16 || bytes.length > 1024) {
    throw new PairingValidationError(
      'invalid-pake-evidence',
      'PAKE shared secret length out of range'
    );
  }
  return bytes;
}

function validatePakeExchange(value: Spake2PlusExchangeResult): Spake2PlusExchangeResult {
  const evidence = normalizedPakeEvidence(value);
  decodePakeSharedSecret(value.sharedSecret);
  for (const confirmation of [
    evidence.initiatorConfirmation,
    evidence.responderConfirmation
  ]) {
    let bytes: Uint8Array;
    try {
      bytes = base64UrlToBytes(confirmation);
    } catch {
      throw new PairingValidationError(
        'invalid-pake-evidence',
        'invalid PAKE confirmation'
      );
    }
    if (bytes.length !== 32) {
      throw new PairingValidationError(
        'invalid-pake-evidence',
        'PAKE confirmation must be 32 bytes'
      );
    }
  }
  return {
    ...evidence,
    sharedSecret: value.sharedSecret
  };
}

export class AdPairSession {
  private currentState: AdPairState = 'initial';
  private offerPayload: PairingPayload | null = null;
  private responsePayload: PairingPayload | null = null;
  private readonly options: AdPairSessionOptions;
  private readonly now: () => number;
  private readonly replayGuard: NonceReplayGuard;

  constructor(options: AdPairSessionOptions) {
    this.options = options;
    this.now = options.now ?? Date.now;
    this.replayGuard =
      options.replayGuard ?? new NonceReplayGuard({ now: this.now });
  }

  get state(): AdPairState {
    return this.currentState;
  }

  get offer(): PairingPayload | null {
    return this.offerPayload;
  }

  get response(): PairingPayload | null {
    return this.responsePayload;
  }

  acceptOffer(raw: string | unknown): PairingPayload {
    if (this.currentState !== 'initial') {
      throw new PairingValidationError('invalid-state', 'pairing offer is not expected');
    }

    try {
      const offer = parseRaw(raw, {
        now: this.now(),
        expectedType: 'offer',
        replayGuard: this.replayGuard
      });
      if (this.options.registry?.isRevoked(offer.deviceId)) {
        throw new PairingValidationError('revoked-device', 'offer device has been revoked');
      }
      this.offerPayload = offer;
      this.currentState = 'offer-accepted';
      return offer;
    } catch (error) {
      this.currentState = 'failed';
      throw error;
    }
  }

  acceptResponse(raw: string | unknown): PairingPayload {
    if (this.currentState !== 'offer-accepted' || !this.offerPayload) {
      throw new PairingValidationError('invalid-state', 'pairing response is not expected');
    }

    try {
      const offer = this.offerPayload;
      const response = parseRaw(raw, {
        now: this.now(),
        expectedType: 'response',
        replayGuard: this.replayGuard
      });
      if (response.replyTo !== offer.nonce) {
        throw new PairingValidationError('offer-nonce-mismatch', 'response does not match offer');
      }
      if (!sameBinding(offer.channelBinding, response.channelBinding)) {
        throw new PairingValidationError(
          'channel-binding-mismatch',
          'pairing channel binding mismatch'
        );
      }
      if (this.options.registry?.isRevoked(response.deviceId)) {
        throw new PairingValidationError('revoked-device', 'response device has been revoked');
      }
      this.responsePayload = response;
      this.currentState = 'response-accepted';
      return response;
    } catch (error) {
      this.currentState = 'failed';
      throw error;
    }
  }

  async finish(input: AdPairFinishInput): Promise<AdPairResult> {
    if (
      this.currentState !== 'response-accepted' ||
      !this.offerPayload ||
      !this.responsePayload
    ) {
      throw new PairingValidationError('invalid-state', 'pairing is not ready to finish');
    }

    try {
      const offer = this.offerPayload;
      const response = this.responsePayload;
      const subtle = this.options.subtle ?? crypto.subtle;

      if (this.options.registry?.isRevoked(offer.deviceId)) {
        throw new PairingValidationError('revoked-device', 'offer device has been revoked');
      }
      if (this.options.registry?.isRevoked(response.deviceId)) {
        throw new PairingValidationError('revoked-device', 'response device has been revoked');
      }

      const channelBinding = requireChannelBinding(offer.channelBinding);
      assertMatchingChannelBinding(channelBinding, requireChannelBinding(response.channelBinding));

      let pake: Spake2PlusExchangeResult;
      if (this.options.pakeExchange) {
        pake = validatePakeExchange(this.options.pakeExchange);
      } else {
        if (!this.options.pake) {
          throw new PairingValidationError('invalid-state', 'PAKE provider is required');
        }
        if (!input.secret || input.secret.length === 0) {
          throw new PairingValidationError('invalid-state', 'pairing secret is required');
        }
        pake = await this.options.pake.exchange({
          protocolVersion: offer.version,
          secret: input.secret,
          initiatorDeviceId: offer.deviceId,
          responderDeviceId: response.deviceId
        });
      }
      const transcriptInput = { offer, response, pake };
      const transcript = canonicalPairingTranscript(transcriptInput);
      const transcriptHash = await computePairingTranscriptHash(transcriptInput, subtle);
      if (input.expectedTranscriptHash) {
        assertTranscriptHash(input.expectedTranscriptHash, transcriptHash);
      }

      const initiatorVerifier = await resolveVerifier(
        'initiator',
        offer,
        this.options.initiatorVerifier,
        subtle
      );
      const responderVerifier = await resolveVerifier(
        'responder',
        response,
        this.options.responderVerifier,
        subtle
      );
      const initiatorSignature = requireSignature(input.initiatorSignature, 'initiator');
      const responderSignature = requireSignature(input.responderSignature, 'responder');
      if (
        !(await verifyPairingTranscriptSignature(
          initiatorVerifier,
          transcript,
          initiatorSignature
        ))
      ) {
        throw new PairingValidationError(
          'invalid-signature',
          'initiator transcript signature is invalid'
        );
      }
      if (
        !(await verifyPairingTranscriptSignature(
          responderVerifier,
          transcript,
          responderSignature
        ))
      ) {
        throw new PairingValidationError(
          'invalid-signature',
          'responder transcript signature is invalid'
        );
      }

      const shortAuthenticationString = await deriveShortAuthenticationString(
        transcriptHash,
        subtle
      );
      const requestedCapabilities = Object.freeze(
        combineRequestedCapabilities(offer, response)
      );
      const sessionKeys = await deriveAdPairSessionKeys({
        pakeSharedSecret: decodePakeSharedSecret(pake.sharedSecret),
        transcriptHash,
        channelBinding,
        subtle
      });
      this.currentState = 'completed';

      return {
        state: 'completed',
        offer,
        response,
        transcript,
        transcriptHash,
        shortAuthenticationString,
        channelBinding,
        requestedCapabilities,
        signatures: {
          initiator: new Uint8Array(initiatorSignature),
          responder: new Uint8Array(responderSignature)
        },
        sessionKeys,
        keyScheduleVersion: sessionKeys.version,
        grants: PAIRING_GRANT_BOUNDARY
      };
    } catch (error) {
      this.currentState = 'failed';
      throw error;
    }
  }
}
