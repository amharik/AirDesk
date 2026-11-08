import { utf8 } from './encoding';
import type { BrowserDeviceIdentity } from './identity';
import type { PairingChannelBinding } from './pairing-payload';
import type { PairingCodeMode } from './pairing-code';
import type { DeviceRegistry } from './registry';
import { AdPairCoordinator } from './pairing-coordinator';
import type { AdPairResult } from './pairing';
import { derivePairingWorkspaceSyncKey } from '../sync/envelope';
import {
  decodePairingWireMessage,
  encodePairingWireMessage,
  pairingWireInitiatorFinish,
  pairingWireResponderFinish,
  pairingWireResponse,
  pairingWireShare,
  pairingWireVerifierResponse
} from './pairing-wire';

export type AdPairLiveRole = 'initiator' | 'responder';

export type AdPairLiveState =
  | 'idle'
  | 'waiting-for-response'
  | 'awaiting-share'
  | 'awaiting-verifier-response'
  | 'awaiting-initiator-finish'
  | 'awaiting-sas'
  | 'completed'
  | 'failed';

export interface AdPairLiveOptions {
  expiresIn?: number;
  endpointHint?: string;
  capabilities?: readonly string[];
}

export type PairingLiveErrorCode = 'invalid-state' | 'sas-mismatch';

export class PairingLiveError extends Error {
  readonly code: PairingLiveErrorCode;

  constructor(code: PairingLiveErrorCode, message: string) {
    super(message);
    this.name = 'PairingLiveError';
    this.code = code;
  }
}

export class AdPairLiveSession {
  readonly role: AdPairLiveRole;

  private readonly coordinator: AdPairCoordinator;
  private readonly registry: DeviceRegistry | undefined;
  private currentState: AdPairLiveState = 'idle';
  private serializedCode: string | undefined;
  private personalIdentificationNumber: string | undefined;
  private sas: string | undefined;
  private peer: string | undefined;
  private pairingResult: AdPairResult | undefined;
  private errorMessage: string | undefined;

  constructor(
    role: AdPairLiveRole,
    identity: BrowserDeviceIdentity,
    options: { now?: () => number; registry?: DeviceRegistry } = {}
  ) {
    this.role = role;
    this.registry = options.registry;
    this.coordinator = new AdPairCoordinator(
      role === 'initiator' ? 'initiator' : 'responder',
      identity,
      {
        ...(options.now === undefined ? {} : { now: options.now }),
        ...(options.registry === undefined ? {} : { registry: options.registry })
      }
    );
  }

  get state(): AdPairLiveState {
    return this.currentState;
  }

  get code(): string | undefined {
    return this.serializedCode;
  }

  get pin(): string | undefined {
    return this.personalIdentificationNumber;
  }

  get shortAuthenticationString(): string | undefined {
    return this.sas;
  }

  get peerDeviceId(): string | undefined {
    return this.peer;
  }

  get result(): AdPairResult | undefined {
    return this.pairingResult;
  }

  get lastError(): string | undefined {
    return this.errorMessage;
  }

  startInitiator(
    mode: PairingCodeMode,
    channelBinding: PairingChannelBinding,
    options: AdPairLiveOptions = {}
  ): { code: string; pin?: string } {
    if (this.role !== 'initiator' || this.currentState !== 'idle') {
      throw this.fail(new PairingLiveError('invalid-state', 'pairing host is not idle'));
    }
    try {
      const start = this.coordinator.startInitiator(
        mode,
        channelBinding,
        options.expiresIn ?? 60_000,
        options.endpointHint,
        options.capabilities ?? []
      );
      this.serializedCode = start.challenge.serialized;
      this.personalIdentificationNumber = start.challenge.pin;
      this.currentState = 'waiting-for-response';
      return {
        code: start.challenge.serialized,
        ...(start.challenge.pin === undefined ? {} : { pin: start.challenge.pin })
      };
    } catch (error) {
      throw this.fail(error);
    }
  }

  async joinResponder(
    code: string,
    pin?: string,
    options: AdPairLiveOptions = {}
  ): Promise<Uint8Array> {
    if (this.role !== 'responder' || this.currentState !== 'idle') {
      throw this.fail(new PairingLiveError('invalid-state', 'pairing controller is not idle'));
    }
    try {
      const join = await this.coordinator.joinResponder(
        code,
        pin,
        options.expiresIn ?? 60_000,
        options.endpointHint,
        options.capabilities ?? []
      );
      this.peer = join.offer.deviceId;
      this.currentState = 'awaiting-share';
      return encodePairingWireMessage(pairingWireResponse(utf8(join.responseData)));
    } catch (error) {
      throw this.fail(error);
    }
  }

  async receive(data: Uint8Array): Promise<Uint8Array[]> {
    try {
      const message = decodePairingWireMessage(data);
      if (this.role === 'initiator') {
        return await this.receiveInitiator(message);
      }
      return await this.receiveResponder(message);
    } catch (error) {
      throw this.fail(error);
    }
  }

  confirmShortAuthenticationString(entered: string): AdPairResult {
    if (this.currentState !== 'awaiting-sas' || !this.pairingResult) {
      throw this.fail(new PairingLiveError('invalid-state', 'pairing is not awaiting verification'));
    }
    if (entered.trim() !== this.pairingResult.shortAuthenticationString) {
      throw this.fail(
        new PairingLiveError('sas-mismatch', 'pairing verification code does not match')
      );
    }
    if (this.registry && this.peer) this.registry.trust(this.peer);
    this.currentState = 'completed';
    return this.pairingResult;
  }

  async workspaceSyncKey(): Promise<CryptoKey> {
    if (this.currentState !== 'completed' || !this.pairingResult) {
      throw new PairingLiveError('invalid-state', 'pairing is not verified');
    }
    return derivePairingWorkspaceSyncKey(this.pairingResult.sessionKeys.transport.bytes);
  }

  cancel(): void {
    this.currentState = 'idle';
    this.serializedCode = undefined;
    this.personalIdentificationNumber = undefined;
    this.sas = undefined;
    this.peer = undefined;
    this.pairingResult = undefined;
    this.errorMessage = undefined;
  }

  private async receiveInitiator(
    message: ReturnType<typeof decodePairingWireMessage>
  ): Promise<Uint8Array[]> {
    if (message.kind === 'response' && this.currentState === 'waiting-for-response') {
      if (!message.response) throw new PairingLiveError('invalid-state', 'response payload missing');
      const response = this.coordinator.state === 'offer-created'
        ? this.peerFromResponse(message.response)
        : undefined;
      const share = await this.coordinator.acceptResponse(message.response);
      this.peer = response;
      this.currentState = 'awaiting-verifier-response';
      return [encodePairingWireMessage(pairingWireShare(share))];
    }
    if (message.kind === 'verifier-response' && this.currentState === 'awaiting-verifier-response') {
      if (!message.share || !message.confirmation || !message.signature) {
        throw new PairingLiveError('invalid-state', 'verifier response is incomplete');
      }
      const completion = await this.coordinator.finishInitiator(
        message.share,
        message.confirmation,
        message.signature
      );
      this.complete(completion.result);
      return [
        encodePairingWireMessage(
          pairingWireInitiatorFinish(completion.confirmation, completion.signature)
        )
      ];
    }
    if (message.kind === 'responder-finish') {
      return [];
    }
    throw new PairingLiveError('invalid-state', 'pairing message is not expected');
  }

  private async receiveResponder(
    message: ReturnType<typeof decodePairingWireMessage>
  ): Promise<Uint8Array[]> {
    if (message.kind === 'share' && this.currentState === 'awaiting-share') {
      if (!message.share) throw new PairingLiveError('invalid-state', 'share payload missing');
      const response = await this.coordinator.respond(message.share);
      this.currentState = 'awaiting-initiator-finish';
      return [
        encodePairingWireMessage(
          pairingWireVerifierResponse(
            response.share,
            response.confirmation,
            response.signature
          )
        )
      ];
    }
    if (message.kind === 'initiator-finish' && this.currentState === 'awaiting-initiator-finish') {
      if (!message.confirmation || !message.signature) {
        throw new PairingLiveError('invalid-state', 'initiator finish is incomplete');
      }
      const completion = await this.coordinator.finishResponder(
        message.confirmation,
        message.signature
      );
      this.complete(completion.result);
      return [
        encodePairingWireMessage(
          pairingWireResponderFinish(completion.confirmation, completion.signature)
        )
      ];
    }
    throw new PairingLiveError('invalid-state', 'pairing message is not expected');
  }

  private complete(result: AdPairResult): void {
    const peer = this.role === 'initiator' ? result.response : result.offer;
    this.pairingResult = result;
    this.sas = result.shortAuthenticationString;
    this.peer = peer.deviceId;
    this.registry?.enrollPending({
      deviceId: peer.deviceId,
      publicKey: peer.publicKey
    });
    this.currentState = 'awaiting-sas';
  }

  private peerFromResponse(response: Uint8Array): string | undefined {
    try {
      const payload = JSON.parse(new TextDecoder().decode(response)) as { deviceId?: unknown };
      return typeof payload.deviceId === 'string' ? payload.deviceId : undefined;
    } catch {
      return undefined;
    }
  }

  private fail(error: unknown): Error {
    const value = error instanceof Error ? error : new Error(String(error));
    this.errorMessage = value.message;
    this.currentState = 'failed';
    return value;
  }
}

