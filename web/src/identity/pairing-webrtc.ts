import {
  certificateHashChannelBinding,
  dtlsFingerprintChannelBinding
} from './channel-binding';
import type { PairingChannelBinding } from './pairing-payload';
import {
  rtcDataChannelPairingTransport,
  type PairingWireTransport
} from './pairing-transport';

export type RtcPairingRole = 'host' | 'controller';

export type RtcPairingState =
  | 'idle'
  | 'creating-offer'
  | 'awaiting-answer'
  | 'awaiting-offer'
  | 'connecting'
  | 'open'
  | 'closed'
  | 'failed';

export interface RtcSessionDescriptionLike {
  type: 'offer' | 'answer';
  sdp: string;
}

export interface RtcIceCandidateLike {
  candidate: string;
  sdpMid?: string | null;
  sdpMLineIndex?: number | null;
  usernameFragment?: string | null;
}

export interface RtcPairingDataChannel {
  readyState: string;
  binaryType?: string;
  send(data: ArrayBuffer | ArrayBufferView): void;
  addEventListener(type: 'message', listener: (event: { data: unknown }) => void): void;
  addEventListener(type: 'open' | 'close' | 'error', listener: () => void): void;
  removeEventListener(type: 'message', listener: (event: { data: unknown }) => void): void;
  removeEventListener(type: 'open' | 'close' | 'error', listener: () => void): void;
}

export interface RtcPeerConnectionLike {
  readonly localDescription: RtcSessionDescriptionLike | null;
  readonly remoteDescription: RtcSessionDescriptionLike | null;
  createDataChannel(label: string): RtcPairingDataChannel;
  createOffer(): Promise<RtcSessionDescriptionLike>;
  createAnswer(): Promise<RtcSessionDescriptionLike>;
  setLocalDescription(description: RtcSessionDescriptionLike): Promise<void>;
  setRemoteDescription(description: RtcSessionDescriptionLike): Promise<void>;
  addIceCandidate(candidate: RtcIceCandidateLike): Promise<void>;
  close(): void;
  addEventListener(
    type: 'icecandidate',
    listener: (event: { candidate: RtcIceCandidateLike | null }) => void
  ): void;
  addEventListener(
    type: 'datachannel',
    listener: (event: { channel: RtcPairingDataChannel }) => void
  ): void;
  addEventListener(type: 'connectionstatechange', listener: () => void): void;
  removeEventListener(
    type: 'icecandidate',
    listener: (event: { candidate: RtcIceCandidateLike | null }) => void
  ): void;
  removeEventListener(
    type: 'datachannel',
    listener: (event: { channel: RtcPairingDataChannel }) => void
  ): void;
}

export type PairingLinkSignal =
  | { kind: 'description'; description: RtcSessionDescriptionLike }
  | { kind: 'candidate'; candidate: RtcIceCandidateLike };

export type PairingLinkErrorCode =
  | 'invalid-signal'
  | 'invalid-state'
  | 'missing-fingerprint'
  | 'binding-mismatch'
  | 'invalid-certificate'
  | 'channel-not-open';

export class PairingLinkError extends Error {
  readonly code: PairingLinkErrorCode;

  constructor(code: PairingLinkErrorCode, message: string) {
    super(`${code}: ${message}`);
    this.name = 'PairingLinkError';
    this.code = code;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseDescription(value: unknown): RtcSessionDescriptionLike {
  if (!isRecord(value) || (value.type !== 'offer' && value.type !== 'answer')) {
    throw new PairingLinkError('invalid-signal', 'description must be an offer or answer');
  }
  if (typeof value.sdp !== 'string' || value.sdp.length === 0 || value.sdp.length > 1_000_000) {
    throw new PairingLinkError('invalid-signal', 'description SDP is invalid');
  }
  return { type: value.type, sdp: value.sdp };
}

function parseCandidate(value: unknown): RtcIceCandidateLike {
  if (!isRecord(value) || typeof value.candidate !== 'string' || value.candidate.length === 0) {
    throw new PairingLinkError('invalid-signal', 'ICE candidate is invalid');
  }
  const candidate: RtcIceCandidateLike = { candidate: value.candidate };
  if (value.sdpMid !== undefined && value.sdpMid !== null) {
    if (typeof value.sdpMid !== 'string') {
      throw new PairingLinkError('invalid-signal', 'ICE sdpMid is invalid');
    }
    candidate.sdpMid = value.sdpMid;
  }
  if (value.sdpMLineIndex !== undefined && value.sdpMLineIndex !== null) {
    if (!Number.isSafeInteger(value.sdpMLineIndex) || (value.sdpMLineIndex as number) < 0) {
      throw new PairingLinkError('invalid-signal', 'ICE sdpMLineIndex is invalid');
    }
    candidate.sdpMLineIndex = value.sdpMLineIndex as number;
  }
  if (value.usernameFragment !== undefined && value.usernameFragment !== null) {
    if (typeof value.usernameFragment !== 'string') {
      throw new PairingLinkError('invalid-signal', 'ICE usernameFragment is invalid');
    }
    candidate.usernameFragment = value.usernameFragment;
  }
  return candidate;
}

export function encodePairingLinkSignal(signal: PairingLinkSignal): string {
  if (signal.kind === 'description') {
    return JSON.stringify({ kind: 'description', description: signal.description });
  }
  return JSON.stringify({ kind: 'candidate', candidate: signal.candidate });
}

export function decodePairingLinkSignal(raw: string): PairingLinkSignal {
  if (raw.length === 0 || raw.length > 1_500_000) {
    throw new PairingLinkError('invalid-signal', 'signaling message is too large');
  }
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new PairingLinkError('invalid-signal', 'signaling message is not JSON');
  }
  if (!isRecord(value)) {
    throw new PairingLinkError('invalid-signal', 'signaling message must be an object');
  }
  if (value.kind === 'description') {
    return { kind: 'description', description: parseDescription(value.description) };
  }
  if (value.kind === 'candidate') {
    return { kind: 'candidate', candidate: parseCandidate(value.candidate) };
  }
  throw new PairingLinkError('invalid-signal', 'unknown signaling message kind');
}

function requireFingerprint(description: RtcSessionDescriptionLike | null): PairingChannelBinding {
  if (!description) {
    throw new PairingLinkError('missing-fingerprint', 'description is not available');
  }
  try {
    return dtlsFingerprintChannelBinding(description.sdp);
  } catch {
    throw new PairingLinkError('missing-fingerprint', 'description has no SHA-256 DTLS fingerprint');
  }
}

export interface RtcCertificateFingerprintLike {
  algorithm: string;
  value: string;
}

export interface RtcCertificateLike {
  getFingerprints?(): readonly RtcCertificateFingerprintLike[];
}

export type RtcCertificateValue = ArrayBuffer | ArrayBufferView | RtcCertificateLike;

export interface RtcCertificateSource {
  getCertificates?():
    | RtcCertificateValue
    | readonly RtcCertificateValue[]
    | Promise<RtcCertificateValue | readonly RtcCertificateValue[]>;
  getRemoteCertificates?():
    | RtcCertificateValue
    | readonly RtcCertificateValue[];
}

export interface RtcCertificateAcquisitionOptions {
  prefer?: 'local' | 'remote';
  subtle?: SubtleCrypto;
}

function certificateValues(
  value: RtcCertificateValue | readonly RtcCertificateValue[]
): readonly RtcCertificateValue[] {
  if (Array.isArray(value)) return value;
  return [value as RtcCertificateValue];
}

async function certificateBindingFromValue(
  value: RtcCertificateValue,
  subtle: SubtleCrypto
): Promise<PairingChannelBinding | undefined> {
  if (value instanceof ArrayBuffer) {
    return certificateHashChannelBinding(new Uint8Array(value), subtle);
  }
  if (ArrayBuffer.isView(value)) {
    return certificateHashChannelBinding(
      new Uint8Array(value.buffer, value.byteOffset, value.byteLength),
      subtle
    );
  }
  const fingerprints = (value as RtcCertificateLike).getFingerprints?.();
  if (!fingerprints) return undefined;
  const sha256 = fingerprints.find(
    (fingerprint) => fingerprint.algorithm.toLowerCase() === 'sha-256'
  );
  if (!sha256) {
    throw new PairingLinkError('missing-fingerprint', 'certificate has no SHA-256 fingerprint');
  }
  const hash = sha256.value.replace(/:/g, '').toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(hash)) {
    throw new PairingLinkError('invalid-certificate', 'certificate fingerprint is invalid');
  }
  return { kind: 'certificate-hash', value: hash };
}

export async function acquireRtcCertificateBinding(
  source: RtcCertificateSource,
  options: RtcCertificateAcquisitionOptions = {}
): Promise<PairingChannelBinding | undefined> {
  const subtle = options.subtle ?? crypto.subtle;
  const prefer = options.prefer ?? 'remote';
  const readers = prefer === 'remote'
    ? [source.getRemoteCertificates?.bind(source), source.getCertificates?.bind(source)]
    : [source.getCertificates?.bind(source), source.getRemoteCertificates?.bind(source)];
  for (const read of readers) {
    if (!read) continue;
    let value: RtcCertificateValue | readonly RtcCertificateValue[];
    try {
      value = await read();
    } catch {
      continue;
    }
    for (const certificate of certificateValues(value)) {
      const binding = await certificateBindingFromValue(certificate, subtle);
      if (binding) return binding;
    }
  }
  return undefined;
}

function sameChannelBinding(
  left: PairingChannelBinding,
  right: PairingChannelBinding
): boolean {
  if (left.kind !== right.kind) return false;
  return left.kind === 'certificate-hash'
    ? left.value.toLowerCase() === right.value.toLowerCase()
    : left.value === right.value;
}

export function assertRtcChannelBinding(
  expected: PairingChannelBinding,
  actual: PairingChannelBinding | undefined
): asserts actual is PairingChannelBinding {
  if (!actual || !sameChannelBinding(expected, actual)) {
    throw new PairingLinkError(
      'binding-mismatch',
      'pairing channel binding does not match the negotiated transport'
    );
  }
}

export function rtcCertificateSource(value: unknown): RtcCertificateSource | undefined {
  if (typeof value !== 'object' || value === null) return undefined;
  const source = value as Record<string, unknown>;
  const hasLocal = typeof source.getCertificates === 'function';
  const hasRemote = typeof source.getRemoteCertificates === 'function';
  if (!hasLocal && !hasRemote) return undefined;
  return value as RtcCertificateSource;
}

export interface RtcPairingLinkOptions {
  role: RtcPairingRole;
  peerConnection: RtcPeerConnectionLike;
  channelLabel?: string;
  onSignal: (signal: PairingLinkSignal) => void;
}

export class RtcPairingLink {
  readonly role: RtcPairingRole;

  private readonly peerConnection: RtcPeerConnectionLike;
  private readonly channelLabel: string;
  private readonly onSignal: (signal: PairingLinkSignal) => void;
  private channel: RtcPairingDataChannel | undefined;
  private binding: PairingChannelBinding | undefined;
  private currentState: RtcPairingState = 'idle';
  private readonly transportWaiters: Array<{
    resolve: (transport: PairingWireTransport) => void;
    reject: (error: unknown) => void;
  }> = [];
  private readonly iceHandler = (event: { candidate: RtcIceCandidateLike | null }): void => {
    if (event.candidate) this.onSignal({ kind: 'candidate', candidate: event.candidate });
  };
  private readonly dataChannelHandler = (event: { channel: RtcPairingDataChannel }): void => {
    if (this.role !== 'controller' || this.channel) return;
    this.installChannel(event.channel);
  };

  constructor(options: RtcPairingLinkOptions) {
    this.role = options.role;
    this.peerConnection = options.peerConnection;
    this.channelLabel = options.channelLabel ?? 'airdesk-pairing';
    this.onSignal = options.onSignal;
    this.peerConnection.addEventListener('icecandidate', this.iceHandler);
    if (this.role === 'controller') {
      this.peerConnection.addEventListener('datachannel', this.dataChannelHandler);
    }
  }

  get state(): RtcPairingState {
    return this.currentState;
  }

  get channelBinding(): PairingChannelBinding | undefined {
    return this.binding;
  }

  get dataChannel(): RtcPairingDataChannel | undefined {
    return this.channel;
  }

  async startHost(): Promise<{ description: RtcSessionDescriptionLike; binding: PairingChannelBinding }> {
    if (this.role !== 'host' || this.currentState !== 'idle') {
      throw new PairingLinkError('invalid-state', 'pairing link cannot create an offer');
    }
    this.currentState = 'creating-offer';
    try {
      this.installChannel(this.peerConnection.createDataChannel(this.channelLabel));
      const description = await this.peerConnection.createOffer();
      await this.peerConnection.setLocalDescription(description);
      this.binding = requireFingerprint(this.peerConnection.localDescription ?? description);
      this.currentState = 'awaiting-answer';
      this.onSignal({ kind: 'description', description });
      return { description, binding: this.binding };
    } catch (error) {
      this.fail(error);
      throw error;
    }
  }

  async acceptOffer(
    description: RtcSessionDescriptionLike
  ): Promise<{ description: RtcSessionDescriptionLike; binding: PairingChannelBinding }> {
    if (this.role !== 'controller' || this.currentState !== 'idle') {
      throw new PairingLinkError('invalid-state', 'pairing link cannot accept an offer');
    }
    this.currentState = 'awaiting-offer';
    try {
      await this.peerConnection.setRemoteDescription(description);
      this.binding = requireFingerprint(this.peerConnection.remoteDescription ?? description);
      const answer = await this.peerConnection.createAnswer();
      await this.peerConnection.setLocalDescription(answer);
      this.currentState = 'connecting';
      this.onSignal({ kind: 'description', description: answer });
      return { description: answer, binding: this.binding };
    } catch (error) {
      this.fail(error);
      throw error;
    }
  }

  async handleSignal(signal: PairingLinkSignal): Promise<void> {
    try {
      if (signal.kind === 'candidate') {
        await this.peerConnection.addIceCandidate(signal.candidate);
        return;
      }
      if (this.role === 'host' && signal.description.type === 'answer' &&
          this.currentState === 'awaiting-answer') {
        await this.peerConnection.setRemoteDescription(signal.description);
        this.currentState = 'connecting';
        return;
      }
      throw new PairingLinkError('invalid-state', 'description is not expected');
    } catch (error) {
      this.fail(error);
      throw error;
    }
  }

  transport(): PairingWireTransport {
    if (!this.channel || this.channel.readyState !== 'open' || this.currentState !== 'open') {
      throw new PairingLinkError('channel-not-open', 'pairing data channel is not open');
    }
    return rtcDataChannelPairingTransport(this.channel);
  }

  waitForTransport(): Promise<PairingWireTransport> {
    if (this.channel?.readyState === 'open' && this.currentState === 'open') {
      return Promise.resolve(this.transport());
    }
    if (this.currentState === 'closed' || this.currentState === 'failed') {
      return Promise.reject(
        new PairingLinkError('invalid-state', 'pairing link is not connectable')
      );
    }
    return new Promise((resolve, reject) => {
      this.transportWaiters.push({ resolve, reject });
    });
  }

  close(): void {
    this.peerConnection.removeEventListener('icecandidate', this.iceHandler);
    if (this.role === 'controller') {
      this.peerConnection.removeEventListener('datachannel', this.dataChannelHandler);
    }
    this.peerConnection.close();
    this.currentState = 'closed';
    this.rejectTransportWaiters(
      new PairingLinkError('invalid-state', 'pairing link was closed')
    );
  }

  private installChannel(channel: RtcPairingDataChannel): void {
    if (this.channel) return;
    this.channel = channel;
    channel.addEventListener('open', () => {
      this.currentState = 'open';
      this.resolveTransportWaiters();
    });
    channel.addEventListener('close', () => {
      this.currentState = 'closed';
      this.rejectTransportWaiters(
        new PairingLinkError('invalid-state', 'pairing data channel was closed')
      );
    });
    channel.addEventListener('error', () => {
      this.currentState = 'failed';
      this.rejectTransportWaiters(
        new PairingLinkError('invalid-state', 'pairing data channel failed')
      );
    });
    if (channel.readyState === 'open') {
      this.currentState = 'open';
      this.resolveTransportWaiters();
    } else if (this.currentState !== 'creating-offer') {
      this.currentState = 'connecting';
    }
  }

  private resolveTransportWaiters(): void {
    if (this.currentState !== 'open') return;
    const waiters = this.transportWaiters.splice(0);
    for (const waiter of waiters) {
      try {
        waiter.resolve(this.transport());
      } catch (error) {
        waiter.reject(error);
      }
    }
  }

  private rejectTransportWaiters(error: unknown): void {
    const waiters = this.transportWaiters.splice(0);
    for (const waiter of waiters) waiter.reject(error);
  }

  private fail(error: unknown): void {
    this.currentState = 'failed';
    this.rejectTransportWaiters(error);
    if (error instanceof PairingLinkError) return;
    throw error;
  }
}

export interface RtcChannelBindingVerificationOptions extends RtcCertificateAcquisitionOptions {
  certificateSource?: RtcCertificateSource;
}

export async function verifyRtcChannelBinding(
  link: RtcPairingLink,
  expected: PairingChannelBinding,
  options: RtcChannelBindingVerificationOptions = {}
): Promise<PairingChannelBinding> {
  assertRtcChannelBinding(expected, link.channelBinding);
  const certificate = options.certificateSource
    ? await acquireRtcCertificateBinding(options.certificateSource, options)
    : undefined;
  if (certificate) assertRtcChannelBinding(expected, certificate);
  return certificate ?? link.channelBinding;
}
