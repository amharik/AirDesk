import type { BrowserDeviceIdentity } from './identity';
import { parsePairingCode, type PairingCodeMode } from './pairing-code';
import type { PairingChannelBinding } from './pairing-payload';
import {
  AdPairLiveSession,
  type AdPairLiveOptions,
  type AdPairLiveState
} from './pairing-live';
import type { AdPairResult } from './pairing';
import type { DeviceRegistry } from './registry';
import { attachPairingSession } from './pairing-transport';
import {
  attachRtcPairingLink,
  sendPairingLinkSignal,
  type PairingSignalTransport
} from './pairing-signaling';
import {
  PairingLinkError,
  RtcPairingLink,
  acquireRtcCertificateBinding,
  assertRtcChannelBinding,
  decodePairingLinkSignal,
  rtcCertificateSource,
  type PairingLinkSignal,
  type RtcCertificateSource,
  type RtcPeerConnectionLike,
  type RtcSessionDescriptionLike
} from './pairing-webrtc';

export type RtcPairingSessionState =
  | 'idle'
  | 'starting'
  | 'connecting'
  | 'open'
  | 'closed'
  | 'failed';

export interface RtcPairingSessionOptions {
  identity: BrowserDeviceIdentity;
  peerConnection: RtcPeerConnectionLike;
  signaling: PairingSignalTransport;
  channelLabel?: string;
  registry?: DeviceRegistry;
  now?: () => number;
  certificateSource?: RtcCertificateSource;
  subtle?: SubtleCrypto;
  onError?: (error: unknown) => void;
}

export interface RtcPairingHostStart {
  code: string;
  pin?: string;
  binding: PairingChannelBinding;
  description: RtcSessionDescriptionLike;
}

export interface RtcPairingControllerAccept {
  response: Uint8Array;
  binding: PairingChannelBinding;
  description: RtcSessionDescriptionLike;
}

export interface RtcPairingOfferWaitOptions {
  timeoutMs?: number;
}

export function waitForRtcPairingOffer(
  signaling: PairingSignalTransport,
  options: RtcPairingOfferWaitOptions = {}
): Promise<RtcSessionDescriptionLike> {
  return new Promise((resolve, reject) => {
    let detach = (): void => {};
    let timer: ReturnType<typeof setTimeout> | undefined;
    const settle = (error?: unknown, offer?: RtcSessionDescriptionLike): void => {
      if (timer !== undefined) clearTimeout(timer);
      detach();
      if (error !== undefined) reject(error);
      else if (offer !== undefined) resolve(offer);
    };
    if (options.timeoutMs !== undefined) {
      timer = setTimeout(() => {
        settle(new PairingLinkError('invalid-signal', 'timed out waiting for a pairing offer'));
      }, options.timeoutMs);
    }
    detach = signaling.onSignal((raw) => {
      try {
        const signal = decodePairingLinkSignal(raw);
        if (signal.kind === 'description' && signal.description.type === 'offer') {
          settle(undefined, signal.description);
        }
      } catch (error) {
        settle(error);
      }
    });
  });
}

function automaticCertificateSource(
  role: 'initiator' | 'responder',
  peerConnection: RtcPeerConnectionLike
): RtcCertificateSource | undefined {
  const source = rtcCertificateSource(peerConnection);
  if (!source) return undefined;
  if (role === 'initiator') {
    return source.getCertificates ? source : undefined;
  }
  return source.getRemoteCertificates ? source : undefined;
}

abstract class RtcPairingSessionBase {
  readonly session: AdPairLiveSession;

  protected readonly options: RtcPairingSessionOptions;
  protected readonly certificateSource: RtcCertificateSource | undefined;
  protected readonly certificatePreference: 'local' | 'remote';
  protected rtcLink: RtcPairingLink | undefined;
  protected currentState: RtcPairingSessionState = 'idle';
  protected currentBinding: PairingChannelBinding | undefined;

  private detachSignaling: (() => void) | undefined;
  private detachSession: (() => void) | undefined;
  private currentError: unknown;

  protected constructor(
    role: 'initiator' | 'responder',
    options: RtcPairingSessionOptions
  ) {
    this.options = options;
    this.certificateSource =
      options.certificateSource ?? automaticCertificateSource(role, options.peerConnection);
    this.certificatePreference = role === 'initiator' ? 'local' : 'remote';
    this.session = new AdPairLiveSession(role, options.identity, {
      ...(options.now === undefined ? {} : { now: options.now }),
      ...(options.registry === undefined ? {} : { registry: options.registry })
    });
  }

  get state(): RtcPairingSessionState {
    return this.currentState;
  }

  get liveState(): AdPairLiveState {
    return this.session.state;
  }

  get channelBinding(): PairingChannelBinding | undefined {
    return this.currentBinding;
  }

  get link(): RtcPairingLink | undefined {
    return this.rtcLink;
  }

  get shortAuthenticationString(): string | undefined {
    return this.session.shortAuthenticationString;
  }

  get sas(): string | undefined {
    return this.session.shortAuthenticationString;
  }

  get peerDeviceId(): string | undefined {
    return this.session.peerDeviceId;
  }

  get result(): AdPairResult | undefined {
    return this.session.result;
  }

  get lastError(): string | undefined {
    if (this.currentError instanceof Error) return this.currentError.message;
    if (this.currentError !== undefined) return String(this.currentError);
    return this.session.lastError;
  }

  confirmShortAuthenticationString(entered: string): ReturnType<
    AdPairLiveSession['confirmShortAuthenticationString']
  > {
    return this.session.confirmShortAuthenticationString(entered);
  }

  workspaceSyncKey(): ReturnType<AdPairLiveSession['workspaceSyncKey']> {
    return this.session.workspaceSyncKey();
  }

  cancel(): void {
    this.detachSignaling?.();
    this.detachSignaling = undefined;
    this.detachSession?.();
    this.detachSession = undefined;
    this.rtcLink?.close();
    this.rtcLink = undefined;
    this.session.cancel();
    this.currentState = 'idle';
    this.currentBinding = undefined;
    this.currentError = undefined;
  }

  close(): void {
    this.detachSignaling?.();
    this.detachSignaling = undefined;
    this.detachSession?.();
    this.detachSession = undefined;
    this.rtcLink?.close();
    this.rtcLink = undefined;
    this.currentState = 'closed';
  }

  protected markStarting(): void {
    if (this.currentState !== 'idle') {
      throw new PairingLinkError('invalid-state', 'pairing session is not idle');
    }
    this.currentState = 'starting';
    this.currentError = undefined;
  }

  protected attachLink(link: RtcPairingLink): void {
    this.rtcLink = link;
    this.detachSignaling = attachRtcPairingLink(link, this.options.signaling, (error) => {
      this.handleError(error);
    });
  }

  protected sendSignal(signal: PairingLinkSignal): void {
    try {
      sendPairingLinkSignal(this.options.signaling, signal);
    } catch (error) {
      this.handleError(error);
      throw error;
    }
  }

  protected async wireChannel(
    link: RtcPairingLink,
    expected: PairingChannelBinding,
    initial?: Uint8Array
  ): Promise<void> {
    try {
      const transport = await link.waitForTransport();
      if (this.rtcLink !== link) return;
      await this.verifyCertificateBinding(expected);
      if (this.rtcLink !== link) return;
      this.detachSession = attachPairingSession(this.session, transport, (error) => {
        this.handleError(error);
      });
      if (initial) transport.send(initial);
      this.currentState = 'open';
    } catch (error) {
      if (this.rtcLink === link) this.handleError(error);
    }
  }

  protected async verifyCertificateBinding(expected: PairingChannelBinding): Promise<void> {
    if (!this.certificateSource) return;
    const certificate = await acquireRtcCertificateBinding(this.certificateSource, {
      prefer: this.certificatePreference,
      ...(this.options.subtle === undefined ? {} : { subtle: this.options.subtle })
    });
    if (certificate) assertRtcChannelBinding(expected, certificate);
  }

  protected handleError(error: unknown): void {
    this.currentError = error;
    this.currentState = 'failed';
    this.options.onError?.(error);
  }
}

export class RtcPairingHostSession extends RtcPairingSessionBase {
  readonly role = 'host' as const;

  private currentCode: string | undefined;
  private currentPin: string | undefined;

  constructor(options: RtcPairingSessionOptions) {
    super('initiator', options);
  }

  get code(): string | undefined {
    return this.currentCode;
  }

  get pin(): string | undefined {
    return this.currentPin;
  }

  async start(
    mode: PairingCodeMode,
    liveOptions: AdPairLiveOptions = {}
  ): Promise<RtcPairingHostStart> {
    this.markStarting();
    try {
      const link = new RtcPairingLink({
        role: 'host',
        peerConnection: this.options.peerConnection,
        ...(this.options.channelLabel === undefined
          ? {}
          : { channelLabel: this.options.channelLabel }),
        onSignal: (signal) => this.sendSignal(signal)
      });
      this.attachLink(link);
      const offer = await link.startHost();
      const binding = await this.resolveHostBinding(offer.binding);
      this.currentBinding = binding;
      const started = this.session.startInitiator(mode, binding, liveOptions);
      this.currentCode = started.code;
      this.currentPin = started.pin;
      this.currentState = 'connecting';
      void this.wireChannel(link, binding);
      return {
        code: started.code,
        ...(started.pin === undefined ? {} : { pin: started.pin }),
        binding,
        description: offer.description
      };
    } catch (error) {
      this.rtcLink?.close();
      this.rtcLink = undefined;
      this.handleError(error);
      throw error;
    }
  }

  startHost(
    mode: PairingCodeMode,
    liveOptions: AdPairLiveOptions = {}
  ): Promise<RtcPairingHostStart> {
    return this.start(mode, liveOptions);
  }

  private async resolveHostBinding(
    sdpBinding: PairingChannelBinding
  ): Promise<PairingChannelBinding> {
    if (!this.certificateSource) return sdpBinding;
    const certificate = await acquireRtcCertificateBinding(this.certificateSource, {
      prefer: 'local',
      ...(this.options.subtle === undefined ? {} : { subtle: this.options.subtle })
    });
    if (!certificate) return sdpBinding;
    assertRtcChannelBinding(sdpBinding, certificate);
    return certificate;
  }
}

export class RtcPairingControllerSession extends RtcPairingSessionBase {
  readonly role = 'controller' as const;

  constructor(options: RtcPairingSessionOptions) {
    super('responder', options);
  }

  async accept(
    code: string,
    offer: RtcSessionDescriptionLike,
    pin?: string,
    liveOptions: AdPairLiveOptions = {}
  ): Promise<RtcPairingControllerAccept> {
    this.markStarting();
    try {
      const parsed = parsePairingCode(code, {
        ...(this.options.now === undefined ? {} : { now: this.options.now() })
      });
      const expected = parsed.offer.channelBinding;
      const link = new RtcPairingLink({
        role: 'controller',
        peerConnection: this.options.peerConnection,
        ...(this.options.channelLabel === undefined
          ? {}
          : { channelLabel: this.options.channelLabel }),
        onSignal: (signal) => this.sendSignal(signal)
      });
      this.attachLink(link);
      const accepted = await link.acceptOffer(offer);
      await this.verifyExpectedBinding(link, expected);
      this.currentBinding = expected;
      const response = await this.session.joinResponder(code, pin, liveOptions);
      this.currentState = 'connecting';
      void this.wireChannel(link, expected, response);
      return { response, binding: expected, description: accepted.description };
    } catch (error) {
      this.rtcLink?.close();
      this.rtcLink = undefined;
      this.handleError(error);
      throw error;
    }
  }

  acceptOffer(
    code: string,
    offer: RtcSessionDescriptionLike,
    pin?: string,
    liveOptions: AdPairLiveOptions = {}
  ): Promise<RtcPairingControllerAccept> {
    return this.accept(code, offer, pin, liveOptions);
  }

  async acceptFromSignal(
    code: string,
    pin?: string,
    liveOptions: AdPairLiveOptions = {}
  ): Promise<RtcPairingControllerAccept> {
    const offer = await waitForRtcPairingOffer(this.options.signaling);
    return this.accept(code, offer, pin, liveOptions);
  }

  private async verifyExpectedBinding(
    link: RtcPairingLink,
    expected: PairingChannelBinding
  ): Promise<void> {
    assertRtcChannelBinding(expected, link.channelBinding);
    if (!this.certificateSource) return;
    const certificate = await acquireRtcCertificateBinding(this.certificateSource, {
      prefer: 'remote',
      ...(this.options.subtle === undefined ? {} : { subtle: this.options.subtle })
    });
    if (certificate) assertRtcChannelBinding(expected, certificate);
  }
}

export type PairingWebRtcSession = RtcPairingHostSession | RtcPairingControllerSession;

export function createRtcPairingHost(
  options: RtcPairingSessionOptions
): RtcPairingHostSession {
  return new RtcPairingHostSession(options);
}

export function createRtcPairingController(
  options: RtcPairingSessionOptions
): RtcPairingControllerSession {
  return new RtcPairingControllerSession(options);
}

export function createRtcPairingHostSession(
  options: RtcPairingSessionOptions
): RtcPairingHostSession {
  return new RtcPairingHostSession(options);
}

export function createRtcPairingControllerSession(
  options: RtcPairingSessionOptions
): RtcPairingControllerSession {
  return new RtcPairingControllerSession(options);
}

export {
  RtcPairingHostSession as RtcPairingHost,
  RtcPairingControllerSession as RtcPairingController,
  RtcPairingHostSession as PairingWebRtcHostSession,
  RtcPairingControllerSession as PairingWebRtcControllerSession
};
