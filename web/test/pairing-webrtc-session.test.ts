import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  MemoryKeyStore,
  PairingLinkError,
  RtcPairingControllerSession,
  RtcPairingHostSession,
  createBrowserIdentity,
  encodePairingLinkSignal,
  waitForRtcPairingOffer,
  webSocketPairingSignalTransport,
  type BrowserDeviceIdentity,
  type RtcIceCandidateLike,
  type RtcPairingDataChannel,
  type RtcPeerConnectionLike,
  type RtcSessionDescriptionLike,
  type WebSocketTextLike
} from '../src/identity';

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

function colonized(hex: string): string {
  return hex.match(/../g)!.join(':').toUpperCase();
}

class FakeChannel {
  readyState = 'connecting';
  binaryType = 'arraybuffer';
  peer: FakeChannel | undefined;
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
    this.peer?.emit('message', { data: new Uint8Array(bytes).buffer });
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

  emitDataChannel(): void {
    for (const listener of this.dataChannelListeners) {
      listener({ channel: this.channel as unknown as RtcPairingDataChannel });
    }
  }
}

class FakeSignalSocket implements WebSocketTextLike {
  readyState = 1;
  peer: FakeSignalSocket | undefined;
  readonly sent: string[] = [];
  private readonly listeners = new Set<(event: { data: unknown }) => void>();

  addEventListener(_type: 'message', listener: (event: { data: unknown }) => void): void {
    this.listeners.add(listener);
  }

  removeEventListener(_type: 'message', listener: (event: { data: unknown }) => void): void {
    this.listeners.delete(listener);
  }

  send(data: string): void {
    if (this.readyState !== 1) throw new Error('signaling socket is not open');
    this.sent.push(data);
    this.peer?.emit(data);
  }

  emit(data: unknown): void {
    for (const listener of this.listeners) listener({ data });
  }
}

function linkedSignaling(): {
  host: FakeSignalSocket;
  controller: FakeSignalSocket;
} {
  const host = new FakeSignalSocket();
  const controller = new FakeSignalSocket();
  host.peer = controller;
  controller.peer = host;
  return { host, controller };
}

async function identity(): Promise<BrowserDeviceIdentity> {
  return createBrowserIdentity({ store: new MemoryKeyStore() });
}

async function waitFor(predicate: () => boolean, timeoutMs = 5_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error('condition timed out');
}

describe('browser WebRTC pairing session', () => {
  it('drives host and controller to a matching SAS over the data channel', async () => {
    const hostPeer = new FakePeerConnection(HOST_FINGERPRINT);
    const controllerPeer = new FakePeerConnection(CONTROLLER_FINGERPRINT);
    const signaling = linkedSignaling();
    const host = new RtcPairingHostSession({
      identity: await identity(),
      peerConnection: hostPeer as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(signaling.host)
    });
    const controller = new RtcPairingControllerSession({
      identity: await identity(),
      peerConnection: controllerPeer as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(signaling.controller)
    });

    const started = await host.start('pin');
    expect(started.binding).toEqual({ kind: 'certificate-hash', value: 'aa'.repeat(32) });
    expect(host.channelBinding).toEqual(started.binding);
    expect(host.code).toBe(started.code);
    expect(host.pin).toBe(started.pin);

    const accepted = await controller.accept(started.code, started.description, started.pin);
    expect(accepted.binding).toEqual(started.binding);
    expect(controller.channelBinding).toEqual(started.binding);
    await waitFor(() => hostPeer.remoteDescription?.type === 'answer');

    hostPeer.channel.peer = controllerPeer.channel;
    controllerPeer.channel.peer = hostPeer.channel;
    hostPeer.channel.emit('open');
    controllerPeer.emitDataChannel();
    controllerPeer.channel.emit('open');

    await waitFor(
      () => host.liveState === 'awaiting-sas' && controller.liveState === 'awaiting-sas'
    );
    expect(host.sas).toBe(controller.sas);

    host.confirmShortAuthenticationString(host.sas!);
    controller.confirmShortAuthenticationString(controller.sas!);
    expect(host.liveState).toBe('completed');
    expect(controller.liveState).toBe('completed');
    expect(host.result?.shortAuthenticationString).toBe(
      controller.result?.shortAuthenticationString
    );
  });

  it('rejects a link binding that differs from the parsed offer binding before joining', async () => {
    const hostPeer = new FakePeerConnection(HOST_FINGERPRINT);
    const controllerPeer = new FakePeerConnection(CONTROLLER_FINGERPRINT);
    const signaling = linkedSignaling();
    const host = new RtcPairingHostSession({
      identity: await identity(),
      peerConnection: hostPeer as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(signaling.host)
    });
    const controller = new RtcPairingControllerSession({
      identity: await identity(),
      peerConnection: controllerPeer as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(signaling.controller)
    });

    const started = await host.start('pin');
    const tampered: RtcSessionDescriptionLike = {
      type: 'offer',
      sdp: sdp(CONTROLLER_FINGERPRINT)
    };

    await expect(controller.accept(started.code, tampered)).rejects.toMatchObject({
      code: 'binding-mismatch'
    });
    expect(controller.state).toBe('failed');
    expect(controller.liveState).toBe('idle');
  });

  it('rejects certificate mismatches and closed signaling', async () => {
    const certificate = new Uint8Array([0x30, 0x82, 0x01, 0x0a]);
    const certificateHash = createHash('sha256').update(certificate).digest('hex');
    const hostPeer = new FakePeerConnection(colonized(certificateHash));
    const host = new RtcPairingHostSession({
      identity: await identity(),
      peerConnection: hostPeer as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(linkedSignaling().host),
      certificateSource: { getCertificates: () => [certificate.buffer] }
    });

    const started = await host.start('pin');
    expect(started.binding).toEqual({ kind: 'certificate-hash', value: certificateHash });

    const otherCertificate = new Uint8Array([0x30, 0x82, 0x02, 0x01]);
    const controllerPeer = new FakePeerConnection(HOST_FINGERPRINT);
    const controller = new RtcPairingControllerSession({
      identity: await identity(),
      peerConnection: controllerPeer as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(linkedSignaling().controller),
      certificateSource: { getRemoteCertificates: () => [otherCertificate.buffer] }
    });

    await expect(controller.accept(started.code, started.description)).rejects.toMatchObject({
      code: 'binding-mismatch'
    });
    expect(controller.liveState).toBe('idle');

    const closed = new FakeSignalSocket();
    closed.readyState = 0;
    const closedHost = new RtcPairingHostSession({
      identity: await identity(),
      peerConnection: new FakePeerConnection(HOST_FINGERPRINT) as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(closed)
    });
    await expect(closedHost.start('pin')).rejects.toThrowError('not open');
    expect(closedHost.state).toBe('failed');
  });

  it('reports malformed and duplicate signals without activating a session', async () => {
    const errors: unknown[] = [];
    const socket = new FakeSignalSocket();
    const peer = new FakePeerConnection(HOST_FINGERPRINT);
    const controller = new RtcPairingControllerSession({
      identity: await identity(),
      peerConnection: peer as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(socket),
      onError: (error) => errors.push(error)
    });

    const started = await new RtcPairingHostSession({
      identity: await identity(),
      peerConnection: new FakePeerConnection(HOST_FINGERPRINT) as unknown as RtcPeerConnectionLike,
      signaling: webSocketPairingSignalTransport(linkedSignaling().host)
    }).start('pin');

    await controller.accept(started.code, started.description, started.pin);
    socket.emit('not json');
    await waitFor(() => errors.length === 1);
    expect(errors[0]).toBeInstanceOf(PairingLinkError);
    expect(controller.liveState).toBe('awaiting-share');

    await expect(
      controller.accept(started.code, started.description, started.pin)
    ).rejects.toMatchObject({ code: 'invalid-state' });
  });

  it('waits for an offer from the signaling transport', async () => {
    const socket = new FakeSignalSocket();
    const waiting = waitForRtcPairingOffer(webSocketPairingSignalTransport(socket));
    socket.emit(
      encodePairingLinkSignal({
        kind: 'candidate',
        candidate: { candidate: 'candidate:1 1 udp 1 127.0.0.1 9 typ host' }
      })
    );
    socket.emit(
      encodePairingLinkSignal({
        kind: 'description',
        description: { type: 'offer', sdp: sdp(HOST_FINGERPRINT) }
      })
    );

    await expect(waiting).resolves.toEqual({
      type: 'offer',
      sdp: sdp(HOST_FINGERPRINT)
    });
  });
});
