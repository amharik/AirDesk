import { bytesToBase64Url, sha256, utf8 } from './encoding';
import type { BrowserDeviceIdentity } from './identity';
import type { Spake2PlusExchangeResult } from './pake';
import {
  PairingValidationError,
  createPairingPayload,
  serializePairingPayload
} from './pairing-payload';
import type { PairingChannelBinding, PairingPayload } from './pairing-payload';
import {
  createPairingPinChallenge,
  createPairingQrSecretChallenge,
  derivePairingCodeRegistration,
  parsePairingCode
} from './pairing-code';
import type { PairingChallenge, PairingCode, PairingCodeMode } from './pairing-code';
import type { DeviceRegistry } from './registry';
import { AdPairSession } from './pairing';
import type { AdPairResult } from './pairing';
import { Spake2PlusSession } from './spake2plus';
import { AD_PAIR_TRANSCRIPT_DOMAIN, canonicalPairingTranscript } from './transcript';

export type AdPairCoordinatorRole = 'initiator' | 'responder';

export type AdPairCoordinatorState =
  | 'initial'
  | 'offer-created'
  | 'joined'
  | 'awaiting-verifier-response'
  | 'awaiting-initiator'
  | 'completed';

export interface AdPairCoordinatorOptions {
  registry?: DeviceRegistry;
  now?: () => number;
}

export interface InitiatorStart {
  offer: PairingPayload;
  challenge: PairingChallenge;
}

export interface ResponderJoin {
  offer: PairingPayload;
  response: PairingPayload;
  responseData: string;
}

export interface ResponderResponse {
  share: Uint8Array;
  confirmation: Uint8Array;
  signature: Uint8Array;
}

export interface InitiatorCompletion {
  result: AdPairResult;
  share: Uint8Array;
  confirmation: Uint8Array;
  signature: Uint8Array;
}

export interface ResponderCompletion {
  result: AdPairResult;
  share: Uint8Array;
  confirmation: Uint8Array;
  signature: Uint8Array;
}

function invalidState(message: string): PairingValidationError {
  return new PairingValidationError('invalid-state', message);
}

export class AdPairCoordinator {
  readonly role: AdPairCoordinatorRole;

  private readonly identity: BrowserDeviceIdentity;
  private readonly registry: DeviceRegistry | undefined;
  private readonly now: () => number;
  private session: AdPairSession | null = null;
  private offer: PairingPayload | null = null;
  private response: PairingPayload | null = null;
  private code: PairingCode | null = null;
  private pin: string | undefined;
  private spake: Spake2PlusSession | null = null;
  private shareP: Uint8Array | null = null;
  private shareV: Uint8Array | null = null;
  private responderSignature: Uint8Array | null = null;
  private currentState: AdPairCoordinatorState = 'initial';

  constructor(
    role: AdPairCoordinatorRole,
    identity: BrowserDeviceIdentity,
    options: AdPairCoordinatorOptions = {}
  ) {
    this.role = role;
    this.identity = identity;
    this.registry = options.registry;
    this.now = options.now ?? Date.now;
  }

  get state(): AdPairCoordinatorState {
    return this.currentState;
  }

  startInitiator(
    mode: PairingCodeMode,
    channelBinding: PairingChannelBinding,
    expiresIn = 60_000,
    endpointHint?: string,
    capabilities: readonly string[] = []
  ): InitiatorStart {
    if (this.role !== 'initiator') {
      throw invalidState('only the initiator creates an offer');
    }
    if (this.currentState !== 'initial') {
      throw invalidState('pairing offer is not expected');
    }
    const now = this.now();
    const offer = createPairingPayload({
      type: 'offer',
      deviceId: this.identity.deviceId,
      publicKey: bytesToBase64Url(this.identity.publicKeySpki),
      channelBinding,
      capabilities,
      expiresAt: now + Math.max(1_000, expiresIn),
      now,
      ...(endpointHint === undefined ? {} : { endpointHint })
    });
    const challenge = mode === 'pin'
      ? createPairingPinChallenge(offer, { now })
      : createPairingQrSecretChallenge(offer, { now });
    const session = new AdPairSession({
      now: this.now,
      ...(this.registry === undefined ? {} : { registry: this.registry })
    });
    session.acceptOffer(serializePairingPayload(offer));
    this.offer = offer;
    this.code = challenge.code;
    this.pin = challenge.pin;
    this.session = session;
    this.currentState = 'offer-created';
    return { offer, challenge };
  }

  async joinResponder(
    code: string,
    pin?: string,
    expiresIn = 60_000,
    endpointHint?: string,
    capabilities: readonly string[] = []
  ): Promise<ResponderJoin> {
    if (this.role !== 'responder') {
      throw invalidState('only the responder scans a pairing code');
    }
    if (this.currentState !== 'initial') {
      throw invalidState('pairing code is not expected');
    }
    const now = this.now();
    const parsed = parsePairingCode(code, { now });
    const offer = parsed.offer;
    if (offer.deviceId === this.identity.deviceId) {
      throw new PairingValidationError('invalid-device-id', 'cannot pair with the local device');
    }
    this.assertNotRevoked(offer.deviceId);

    const session = new AdPairSession({
      now: this.now,
      ...(this.registry === undefined ? {} : { registry: this.registry })
    });
    session.acceptOffer(serializePairingPayload(offer));

    const remaining = offer.expiresAt - now;
    if (remaining <= 0) {
      throw new PairingValidationError('expired', 'pairing offer has expired');
    }
    const response = createPairingPayload({
      type: 'response',
      deviceId: this.identity.deviceId,
      publicKey: bytesToBase64Url(this.identity.publicKeySpki),
      channelBinding: offer.channelBinding,
      capabilities,
      replyTo: offer.nonce,
      expiresAt: now + Math.max(1_000, Math.min(expiresIn, remaining)),
      now,
      ...(endpointHint === undefined ? {} : { endpointHint })
    });
    const responseData = serializePairingPayload(response);
    session.acceptResponse(responseData);

    const registration = await this.registration(parsed, offer, response, pin);
    this.spake = new Spake2PlusSession({
      role: 'verifier',
      context: utf8(AD_PAIR_TRANSCRIPT_DOMAIN),
      idProver: utf8(offer.deviceId),
      idVerifier: utf8(response.deviceId),
      w0: registration.w0,
      L: registration.L
    });
    this.offer = offer;
    this.response = response;
    this.code = parsed;
    this.session = session;
    this.currentState = 'joined';
    return { offer, response, responseData };
  }

  async acceptResponse(data: string | Uint8Array): Promise<Uint8Array> {
    if (this.role !== 'initiator') {
      throw invalidState('only the initiator accepts a response');
    }
    if (
      this.currentState !== 'offer-created' ||
      !this.session ||
      !this.offer ||
      !this.code
    ) {
      throw invalidState('pairing response is not expected');
    }
    const response = this.session.acceptResponse(decodeText(data));
    if (response.deviceId === this.identity.deviceId) {
      throw new PairingValidationError('invalid-device-id', 'cannot pair with the local device');
    }
    this.assertNotRevoked(response.deviceId);

    const registration = await this.registration(this.code, this.offer, response, this.pin);
    const spake = new Spake2PlusSession({
      role: 'prover',
      context: utf8(AD_PAIR_TRANSCRIPT_DOMAIN),
      idProver: utf8(this.offer.deviceId),
      idVerifier: utf8(response.deviceId),
      w0: registration.w0,
      w1: registration.w1
    });
    const shareP = spake.proverStart();
    this.response = response;
    this.spake = spake;
    this.shareP = shareP;
    this.currentState = 'awaiting-verifier-response';
    return new Uint8Array(shareP);
  }

  async respond(shareP: Uint8Array): Promise<ResponderResponse> {
    if (this.role !== 'responder') {
      throw invalidState('only the responder responds to an initiator share');
    }
    if (this.currentState !== 'joined' || !this.offer || !this.response || !this.spake) {
      throw invalidState('responder is not awaiting an initiator share');
    }
    const reply = await this.spake.verifierRespond(shareP);
    const evidence = this.evidence(
      shareP,
      reply.share,
      reply.expectedConfirmation,
      reply.confirmation
    );
    const transcript = canonicalPairingTranscript({
      offer: this.offer,
      response: this.response,
      pake: evidence
    });
    const signature = await this.identity.sign(transcript);
    this.shareP = new Uint8Array(shareP);
    this.shareV = new Uint8Array(reply.share);
    this.responderSignature = new Uint8Array(signature);
    this.currentState = 'awaiting-initiator';
    return {
      share: new Uint8Array(reply.share),
      confirmation: new Uint8Array(reply.confirmation),
      signature: new Uint8Array(signature)
    };
  }

  async finishInitiator(
    shareV: Uint8Array,
    responderConfirmation: Uint8Array,
    responderSignature: Uint8Array
  ): Promise<InitiatorCompletion> {
    if (this.role !== 'initiator') {
      throw invalidState('only the initiator finishes the initiator exchange');
    }
    if (
      this.currentState !== 'awaiting-verifier-response' ||
      !this.session ||
      !this.offer ||
      !this.response ||
      !this.spake ||
      !this.shareP
    ) {
      throw invalidState('initiator is not awaiting a responder response');
    }
    const result = await this.spake.proverFinish(shareV, responderConfirmation);
    const evidence = this.evidence(
      this.shareP,
      shareV,
      result.confirmation,
      result.expectedConfirmation,
      new Uint8Array(result.keys.kShared)
    );
    const transcript = canonicalPairingTranscript({
      offer: this.offer,
      response: this.response,
      pake: evidence
    });
    const signature = await this.identity.sign(transcript);
    this.assertNotRevoked(this.response.deviceId);
    const pairing = await this.session.finish({
      pakeExchange: evidence,
      initiatorSignature: signature,
      responderSignature,
      expectedTranscriptHash: await this.transcriptHash(evidence)
    });
    this.currentState = 'completed';
    return {
      result: pairing,
      share: new Uint8Array(this.shareP),
      confirmation: new Uint8Array(result.confirmation),
      signature: new Uint8Array(signature)
    };
  }

  async finishResponder(
    initiatorConfirmation: Uint8Array,
    initiatorSignature: Uint8Array
  ): Promise<ResponderCompletion> {
    if (this.role !== 'responder') {
      throw invalidState('only the responder finishes the responder exchange');
    }
    if (
      this.currentState !== 'awaiting-initiator' ||
      !this.session ||
      !this.offer ||
      !this.response ||
      !this.spake ||
      !this.shareP ||
      !this.shareV ||
      !this.responderSignature
    ) {
      throw invalidState('responder is not awaiting an initiator confirmation');
    }
    const result = await this.spake.verifierFinish(initiatorConfirmation);
    const evidence = this.evidence(
      this.shareP,
      this.shareV,
      initiatorConfirmation,
      result.confirmation,
      new Uint8Array(result.keys.kShared)
    );
    this.assertNotRevoked(this.offer.deviceId);
    const pairing = await this.session.finish({
      pakeExchange: evidence,
      initiatorSignature,
      responderSignature: this.responderSignature,
      expectedTranscriptHash: await this.transcriptHash(evidence)
    });
    this.currentState = 'completed';
    return {
      result: pairing,
      share: new Uint8Array(this.shareV),
      confirmation: new Uint8Array(result.confirmation),
      signature: new Uint8Array(this.responderSignature)
    };
  }

  private async registration(
    code: PairingCode,
    offer: PairingPayload,
    response: PairingPayload,
    pin?: string
  ) {
    return derivePairingCodeRegistration({
      code,
      initiatorDeviceId: offer.deviceId,
      responderDeviceId: response.deviceId,
      ...(pin === undefined ? {} : { pin })
    });
  }

  private evidence(
    initiatorShare: Uint8Array,
    responderShare: Uint8Array,
    initiatorConfirmation: Uint8Array,
    responderConfirmation: Uint8Array,
    sharedSecret = new Uint8Array()
  ): Spake2PlusExchangeResult {
    return {
      initiatorShare: bytesToBase64Url(initiatorShare),
      responderShare: bytesToBase64Url(responderShare),
      initiatorConfirmation: bytesToBase64Url(initiatorConfirmation),
      responderConfirmation: bytesToBase64Url(responderConfirmation),
      sharedSecret: bytesToBase64Url(sharedSecret)
    };
  }

  private async transcriptHash(evidence: Spake2PlusExchangeResult): Promise<Uint8Array> {
    if (!this.offer || !this.response) {
      throw invalidState('pairing payloads are missing');
    }
    return sha256(
      canonicalPairingTranscript({
        offer: this.offer,
        response: this.response,
        pake: evidence
      })
    );
  }

  private assertNotRevoked(deviceId: string): void {
    if (this.registry?.isRevoked(deviceId)) {
      throw new PairingValidationError('revoked-device', 'pairing device has been revoked');
    }
  }
}

function decodeText(value: string | Uint8Array): string {
  return typeof value === 'string' ? value : new TextDecoder().decode(value);
}
