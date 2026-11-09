import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  PairingLinkError,
  RtcPairingLink,
  acquireRtcCertificateBinding,
  assertRtcChannelBinding,
  decodePairingLinkSignal,
  encodePairingLinkSignal,
  rtcCertificateSource,
  verifyRtcChannelBinding,
  type PairingLinkSignal,
  type RtcIceCandidateLike,
  type RtcPairingDataChannel,
  type RtcPeerConnectionLike,
  type RtcSessionDescriptionLike
} from '../src/identity/pairing-webrtc';

const HOST_FINGERPRINT = 'AA:'.repeat(31) + 'AA';
const CONTROLLER_FINGERPRINT = 'BB:'.repeat(31) + 'BB';

function sdp(fingerprint: string): string {
  return [
    'v=0',
    'o=- 1 1 IN IP4 127.0.0.1',
    's=-',
    't=0 0',
    'a=group:BUNDLE 0',
    'm=application 9 UDP/DTLS/SCTP webrtc-datachannel',
    'a=setup:actpass',
    `a=fingerprint:sha-256 ${fingerprint}`,
    'a=ice-ufrag:test',
    'a=ice-pwd:test'
  ].join('\r\n');
}

class FakeChannel {
  readyState = 'connecting';
  binaryType = 'arraybuffer';
  readonly sent: Uint8Array[] = [];
  private readonly listeners = new Map<string, Set<(event?: unknown) => void>>();

  addEventListener(type: string, listener: (event?: unknown) => void): void {
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener);
    this.listeners.set(type, listeners);
  }

  removeEventListener(type: string, listener: (event?: unknown) => void): void {
    this.listeners.get(type)?.delete(listener);
  }

  send(data: ArrayBuffer | ArrayBufferView): void {
    if (this.readyState !== 'open') throw new Error('channel is not open');
    const bytes = data instanceof ArrayBuffer
      ? new Uint8Array(data)
      : new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    this.sent.push(new Uint8Array(bytes));
  }

  emit(type: string, event?: unknown): void {
    if (type === 'open') this.readyState = 'open';
    if (type === 'close') this.readyState = 'closed';
    for (const listener of this.listeners.get(type) ?? []) listener(event);
  }
}

class FakePeerConnection {
  localDescription: RtcSessionDescriptionLike | null = null;
  remoteDescription: RtcSessionDescriptionLike | null = null;
  readonly channel = new FakeChannel();
  readonly fingerprint: string;
  readonly iceListeners = new Set<(event: { candidate: RtcIceCandidateLike | null }) => void>();
  readonly dataChannelListeners = new Set<(event: { channel: RtcPairingDataChannel }) => void>();
  closed = false;

  constructor(fingerprint: string) {
    this.fingerprint = fingerprint;
  }

  createDataChannel(): RtcPairingDataChannel {
    return this.channel as unknown as RtcPairingDataChannel;
  }

  async createOffer(): Promise<RtcSessionDescriptionLike> {
    return { type: 'offer', sdp: sdp(this.fingerprint) };
  }

  async createAnswer(): Promise<RtcSessionDescriptionLike> {
    return { type: 'answer', sdp: sdp(this.fingerprint) };
  }

  async setLocalDescription(description: RtcSessionDescriptionLike): Promise<void> {
    this.localDescription = description;
  }

  async setRemoteDescription(description: RtcSessionDescriptionLike): Promise<void> {
    this.remoteDescription = description;
  }

  async addIceCandidate(): Promise<void> {}

  close(): void {
    this.closed = true;
  }

  addEventListener(type: string, listener: (event?: unknown) => void): void {
    if (type === 'icecandidate') {
      this.iceListeners.add(listener as (event: { candidate: RtcIceCandidateLike | null }) => void);
    }
    if (type === 'datachannel') {
      this.dataChannelListeners.add(listener as (event: { channel: RtcPairingDataChannel }) => void);
    }
  }

  removeEventListener(type: string, listener: (event?: unknown) => void): void {
    if (type === 'icecandidate') {
      this.iceListeners.delete(listener as (event: { candidate: RtcIceCandidateLike | null }) => void);
    }
    if (type === 'datachannel') {
      this.dataChannelListeners.delete(listener as (event: { channel: RtcPairingDataChannel }) => void);
    }
  }

  emitIce(candidate: RtcIceCandidateLike | null): void {
    for (const listener of this.iceListeners) listener({ candidate });
  }

  emitDataChannel(): void {
    for (const listener of this.dataChannelListeners) listener({ channel: this.channel as unknown as RtcPairingDataChannel });
  }
}

function linkedPair() {
  const hostPeer = new FakePeerConnection(HOST_FINGERPRINT);
  const controllerPeer = new FakePeerConnection(CONTROLLER_FINGERPRINT);
  const hostSignals: PairingLinkSignal[] = [];
  const controllerSignals: PairingLinkSignal[] = [];
  const host = new RtcPairingLink({
    role: 'host',
    peerConnection: hostPeer as unknown as RtcPeerConnectionLike,
    onSignal: (signal) => hostSignals.push(signal)
  });
  const controller = new RtcPairingLink({
    role: 'controller',
    peerConnection: controllerPeer as unknown as RtcPeerConnectionLike,
    onSignal: (signal) => controllerSignals.push(signal)
  });
  return { host, controller, hostPeer, controllerPeer, hostSignals, controllerSignals };
}

describe('browser WebRTC pairing link', () => {
  it('exchanges offer/answer and binds both peers to the host fingerprint', async () => {
    const { host, controller, controllerPeer, hostSignals } = linkedPair();

    const offer = await host.startHost();
    expect(host.state).toBe('awaiting-answer');
    expect(offer.binding).toEqual({
      kind: 'certificate-hash',
      value: 'aa'.repeat(32)
    });
    expect(hostSignals[0]).toMatchObject({ kind: 'description' });

    const accepted = await controller.acceptOffer(offer.description);
    expect(accepted.binding).toEqual(offer.binding);
    expect(controller.channelBinding).toEqual(offer.binding);
    expect(controllerPeer.remoteDescription?.type).toBe('offer');

    controllerPeer.emitDataChannel();
    controllerPeer.channel.emit('open');
    expect(controller.state).toBe('open');
    expect(() => controller.transport()).not.toThrow();
  });

  it('accepts the answer, ICE candidates and rejects replayed signals', async () => {
    const { host, controller, hostPeer, controllerPeer, controllerSignals } = linkedPair();
    const offer = await host.startHost();
    const answer = await controller.acceptOffer(offer.description);

    const encoded = controllerSignals[0];
    expect(encoded?.kind).toBe('description');
    const decoded = decodePairingLinkSignal(
      encodePairingLinkSignal({ kind: 'description', description: answer.description })
    );
    expect(decoded).toEqual({ kind: 'description', description: answer.description });

    await host.handleSignal(decoded);
    expect(hostPeer.remoteDescription?.type).toBe('answer');

    const candidate = { candidate: 'candidate:1 1 udp 1 127.0.0.1 5000 typ host', sdpMid: '0' };
    await host.handleSignal({ kind: 'candidate', candidate });
    expect(decodePairingLinkSignal(encodePairingLinkSignal({ kind: 'candidate', candidate }))).toEqual({
      kind: 'candidate',
      candidate
    });

    hostPeer.channel.emit('open');
    expect(host.state).toBe('open');
    expect(() => host.transport().send(new Uint8Array([1, 2, 3]))).not.toThrow();
    expect(hostPeer.channel.sent).toHaveLength(1);

    await expect(host.handleSignal(decoded)).rejects.toMatchObject({ code: 'invalid-state' });
    expect(host.state).toBe('failed');
    controllerPeer.emitDataChannel();
    controllerPeer.channel.emit('close');
    expect(controller.state).toBe('closed');
  });

  it('fails closed without a SHA-256 fingerprint and validates signaling messages', async () => {
    const peer = new FakePeerConnection(HOST_FINGERPRINT);
    const link = new RtcPairingLink({ role: 'host', peerConnection: peer as unknown as RtcPeerConnectionLike, onSignal: () => {} });
    const bad = { type: 'offer' as const, sdp: 'v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel' };

    await expect(link.acceptOffer(bad)).rejects.toMatchObject({ code: 'invalid-state' });
    expect(() => decodePairingLinkSignal('{')).toThrowError(PairingLinkError);
    expect(() => decodePairingLinkSignal('{"kind":"candidate","candidate":{}}')).toThrowError(
      PairingLinkError
    );

    const controller = new RtcPairingLink({
      role: 'controller',
      peerConnection: peer as unknown as RtcPeerConnectionLike,
      onSignal: () => {}
    });
    await expect(controller.acceptOffer(bad)).rejects.toMatchObject({ code: 'missing-fingerprint' });
    expect(controller.state).toBe('failed');
    expect(() => controller.transport()).toThrowError(PairingLinkError);
  });

  it('rejects out-of-order descriptions and keeps duplicate signals fail-closed', async () => {
    const { host } = linkedPair();
    const answer: RtcSessionDescriptionLike = {
      type: 'answer',
      sdp: sdp(CONTROLLER_FINGERPRINT)
    };

    await expect(
      host.handleSignal({ kind: 'description', description: answer })
    ).rejects.toMatchObject({ code: 'invalid-state' });
    expect(host.state).toBe('failed');
  });

  it('acquires certificate fingerprints and rejects binding mismatches', async () => {
    const certificate = {
      getFingerprints: () => [{ algorithm: 'sha-256', value: HOST_FINGERPRINT }]
    };
    const binding = await acquireRtcCertificateBinding({
      getCertificates: () => [certificate]
    });
    expect(binding).toEqual({ kind: 'certificate-hash', value: 'aa'.repeat(32) });

    expect(rtcCertificateSource({ getCertificates: () => [] })).toBeDefined();
    expect(rtcCertificateSource({})).toBeUndefined();
    expect(() =>
      assertRtcChannelBinding(
        { kind: 'certificate-hash', value: 'bb'.repeat(32) },
        binding
      )
    ).toThrowError(expect.objectContaining({ code: 'binding-mismatch' }));
  });

  it('falls back to the SDP fingerprint only after comparing it with the expected binding', async () => {
    const { host } = linkedPair();
    const offer = await host.startHost();

    await expect(
      verifyRtcChannelBinding(host, { kind: 'certificate-hash', value: 'bb'.repeat(32) })
    ).rejects.toMatchObject({ code: 'binding-mismatch' });
    await expect(verifyRtcChannelBinding(host, offer.binding)).resolves.toEqual(offer.binding);
  });

  it('rejects a certificate whose SHA-256 hash does not match the expected binding', async () => {
    const certificate = new Uint8Array([0x30, 0x82, 0x03, 0x01]);
    const certificateHash = createHash('sha256').update(certificate).digest('hex');
    const { host } = linkedPair();
    const offer = await host.startHost();

    expect(certificateHash).not.toBe(offer.binding.value);
    await expect(
      verifyRtcChannelBinding(host, offer.binding, {
        certificateSource: { getCertificates: () => [certificate.buffer] }
      })
    ).rejects.toMatchObject({ code: 'binding-mismatch' });
  });
});
