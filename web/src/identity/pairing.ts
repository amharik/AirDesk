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
import type { Spake2PlusPrimitive } from './pake';
import { NonceReplayGuard } from './replay';
import type { DeviceRegistry } from './registry';
import {
  assertTranscriptHash,
  canonicalPairingTranscript,
  combineRequestedCapabilities,
  computePairingTranscriptHash,
  deriveShortAuthenticationString
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
  pake: Spake2PlusPrimitive;
  now?: () => number;
  replayGuard?: NonceReplayGuard;
  registry?: DeviceRegistry;
  subtle?: SubtleCrypto;
}

export interface AdPairFinishInput {
  secret: Uint8Array;
  expectedTranscriptHash?: Uint8Array;
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
      if (input.secret.length === 0) {
        throw new PairingValidationError('invalid-state', 'pairing secret is required');
      }

      const offer = this.offerPayload;
      const response = this.responsePayload;
      const pake = await this.options.pake.exchange({
        protocolVersion: offer.version,
        secret: input.secret,
        initiatorDeviceId: offer.deviceId,
        responderDeviceId: response.deviceId
      });
      const transcriptInput = { offer, response, pake };
      const transcript = canonicalPairingTranscript(transcriptInput);
      const transcriptHash = await computePairingTranscriptHash(
        transcriptInput,
        this.options.subtle
      );
      if (input.expectedTranscriptHash) {
        assertTranscriptHash(input.expectedTranscriptHash, transcriptHash);
      }
      const shortAuthenticationString = await deriveShortAuthenticationString(
        transcriptHash,
        this.options.subtle
      );
      const requestedCapabilities = Object.freeze(
        combineRequestedCapabilities(offer, response)
      );
      this.currentState = 'completed';

      return {
        state: 'completed',
        offer,
        response,
        transcript,
        transcriptHash,
        shortAuthenticationString,
        channelBinding: { ...offer.channelBinding },
        requestedCapabilities,
        grants: PAIRING_GRANT_BOUNDARY
      };
    } catch (error) {
      this.currentState = 'failed';
      throw error;
    }
  }
}
