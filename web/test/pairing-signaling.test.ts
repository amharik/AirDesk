import { describe, expect, it, vi } from 'vitest';
import {
  attachRtcPairingLink,
  sendPairingLinkSignal,
  webSocketPairingSignalTransport,
  type WebSocketTextLike
} from '../src/identity/pairing-signaling';
import {
  encodePairingLinkSignal,
  type PairingLinkSignal,
  type RtcPairingLink
} from '../src/identity/pairing-webrtc';

class FakeSocket implements WebSocketTextLike {
  readyState = 1;
  readonly sent: string[] = [];
  private readonly listeners = new Set<(event: { data: unknown }) => void>();

  addEventListener(_type: 'message', listener: (event: { data: unknown }) => void): void {
    this.listeners.add(listener);
  }

  removeEventListener(_type: 'message', listener: (event: { data: unknown }) => void): void {
    this.listeners.delete(listener);
  }

  send(data: string): void {
    if (this.readyState !== 1) throw new Error('socket is not open');
    this.sent.push(data);
  }

  emit(data: unknown): void {
    for (const listener of this.listeners) listener({ data });
  }
}

describe('pairing signaling transport', () => {
  it('sends and receives encoded signals over a WebSocket', () => {
    const socket = new FakeSocket();
    const transport = webSocketPairingSignalTransport(socket);
    const received: string[] = [];
    const detach = transport.onSignal((signal) => received.push(signal));
    const signal: PairingLinkSignal = {
      kind: 'candidate',
      candidate: { candidate: 'candidate:1 1 udp 1 127.0.0.1 9 typ host', sdpMLineIndex: 0 }
    };

    sendPairingLinkSignal(transport, signal);
    socket.emit(encodePairingLinkSignal(signal));
    socket.emit(new Uint8Array([1]));

    expect(socket.sent).toEqual([encodePairingLinkSignal(signal)]);
    expect(received).toEqual([encodePairingLinkSignal(signal)]);
    detach();
    socket.emit(encodePairingLinkSignal(signal));
    expect(received).toHaveLength(1);
  });

  it('rejects closed sockets and forwards decoded link signals', async () => {
    const socket = new FakeSocket();
    socket.readyState = 0;
    expect(() =>
      webSocketPairingSignalTransport(socket).send('{}')
    ).toThrow('not open');

    const handled: PairingLinkSignal[] = [];
    const errors: unknown[] = [];
    const link = {
      handleSignal: vi.fn(async (signal: PairingLinkSignal) => {
        handled.push(signal);
        if (signal.kind === 'description' && signal.description.type === 'offer') {
          throw new Error('bad offer');
        }
      })
    } as unknown as RtcPairingLink;
    const open = new FakeSocket();
    const transport = webSocketPairingSignalTransport(open);
    const detach = attachRtcPairingLink(link, transport, (error) => errors.push(error));
    const signal: PairingLinkSignal = {
      kind: 'description',
      description: { type: 'offer', sdp: 'v=0\r\n' }
    };
    open.emit(encodePairingLinkSignal(signal));
    open.emit('not json');
    await Promise.resolve();
    expect(handled).toEqual([signal]);
    expect(errors).toHaveLength(2);
    expect(errors[0]).toBeInstanceOf(Error);
    detach();
  });

  it('reports closed signaling, malformed and duplicate signals', async () => {
    const socket = new FakeSocket();
    const transport = webSocketPairingSignalTransport(socket);
    const signal: PairingLinkSignal = {
      kind: 'candidate',
      candidate: { candidate: 'candidate:1 1 udp 1 127.0.0.1 9 typ host' }
    };

    socket.readyState = 0;
    expect(() => sendPairingLinkSignal(transport, signal)).toThrow('not open');
    socket.readyState = 1;

    const handled: PairingLinkSignal[] = [];
    const errors: unknown[] = [];
    const link = {
      handleSignal: vi.fn(async (next: PairingLinkSignal) => {
        handled.push(next);
        if (handled.length > 1) throw new Error('duplicate signal');
      })
    } as unknown as RtcPairingLink;
    const detach = attachRtcPairingLink(link, transport, (error) => errors.push(error));
    const raw = encodePairingLinkSignal(signal);
    socket.emit(raw);
    socket.emit(raw);
    socket.emit('{');
    await Promise.resolve();

    expect(handled).toEqual([signal, signal]);
    expect(errors).toHaveLength(2);
    expect(errors[0]).toBeInstanceOf(Error);
    detach();
  });
});
