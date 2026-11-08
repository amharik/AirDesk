import { describe, expect, it } from 'vitest';
import {
  AdPairLiveSession,
  MemoryKeyStore,
  attachPairingSession,
  createBrowserIdentity,
  exporterChannelBinding,
  rtcDataChannelPairingTransport,
  webSocketPairingTransport,
  type BrowserDeviceIdentity
} from '../src/identity';

class FakeSocket {
  binaryType = '';
  readyState = 1;
  peer: FakeSocket | undefined;
  sent: Uint8Array[] = [];
  private listeners = new Set<(event: { data: unknown }) => void>();

  send(data: ArrayBuffer | ArrayBufferView): void {
    const bytes = ArrayBuffer.isView(data)
      ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
      : new Uint8Array(data);
    this.sent.push(new Uint8Array(bytes));
    this.peer?.emit(bytes);
  }

  emit(data: unknown): void {
    for (const listener of this.listeners) listener({ data });
  }

  addEventListener(_type: 'message', listener: (event: { data: unknown }) => void): void {
    this.listeners.add(listener);
  }

  removeEventListener(_type: 'message', listener: (event: { data: unknown }) => void): void {
    this.listeners.delete(listener);
  }
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

describe('browser pairing transports', () => {
  it('drives live pairing end-to-end over linked WebSocket transports', async () => {
    const hostSocket = new FakeSocket();
    const controllerSocket = new FakeSocket();
    hostSocket.peer = controllerSocket;
    controllerSocket.peer = hostSocket;

    const host = new AdPairLiveSession('initiator', await identity());
    const controller = new AdPairLiveSession('responder', await identity());
    attachPairingSession(host, webSocketPairingTransport(hostSocket));
    const controllerTransport = webSocketPairingTransport(controllerSocket);
    attachPairingSession(controller, controllerTransport);

    const start = host.startInitiator(
      'pin',
      exporterChannelBinding(new Uint8Array(32).fill(10))
    );
    const response = await controller.joinResponder(start.code, start.pin);
    controllerTransport.send(response);

    await waitFor(() => host.state === 'awaiting-sas' && controller.state === 'awaiting-sas');
    host.confirmShortAuthenticationString(host.shortAuthenticationString!);
    controller.confirmShortAuthenticationString(controller.shortAuthenticationString!);

    expect(host.state).toBe('completed');
    expect(controller.state).toBe('completed');
    expect(hostSocket.binaryType).toBe('arraybuffer');
    expect(hostSocket.sent.length).toBeGreaterThan(0);
  });

  it('adapts an RTCDataChannel binary message and rejects sends before open', () => {
    const channel = new FakeSocket();
    const transport = rtcDataChannelPairingTransport({
      binaryType: '',
      readyState: 'connecting',
      send: (data) => channel.send(data),
      addEventListener: (type, listener) => channel.addEventListener(type, listener),
      removeEventListener: (type, listener) => channel.removeEventListener(type, listener)
    });

    expect(() => transport.send(new Uint8Array([1]))).toThrowError(
      'pairing data channel is not open'
    );

    let received: Uint8Array | undefined;
    transport.onMessage((data) => {
      received = data;
    });
    channel.emit(new Uint8Array([1, 2, 3]).buffer);
    expect(received).toEqual(new Uint8Array([1, 2, 3]));
  });

  it('ignores non-binary transport messages and reports session errors', async () => {
    const socket = new FakeSocket();
    const transport = webSocketPairingTransport(socket);
    const received: unknown[] = [];
    transport.onMessage((data) => received.push(data));
    socket.emit('not-binary');
    expect(received).toEqual([]);

    const session = new AdPairLiveSession('initiator', await identity());
    const errors: unknown[] = [];
    attachPairingSession(session, transport, (error) => errors.push(error));
    socket.emit(new Uint8Array());
    await waitFor(() => errors.length === 1);
    expect(errors[0]).toMatchObject({ code: 'malformed' });
  });
});
