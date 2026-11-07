import { describe, expect, it } from 'vitest';
import { WebSocketControlTransport } from '../src/endpoint';
import type { ControlConnectRequest } from '../src/endpoint';

const TOKEN = `token_${'a'.repeat(32)}`;
const REQUEST: ControlConnectRequest = {
  url: 'ws://127.0.0.1:51234/',
  origin: 'http://127.0.0.1:51234',
  token: TOKEN,
  role: 'display'
};

type Listener = (event: never) => void;

class FakeSocket {
  readonly sent: string[] = [];
  readonly listeners = new Map<string, Set<Listener>>();
  closed: { code?: number; reason?: string } | null = null;

  constructor(readonly url: string) {}

  addEventListener(type: string, listener: Listener): void {
    const listeners = this.listeners.get(type) ?? new Set<Listener>();
    listeners.add(listener);
    this.listeners.set(type, listeners);
  }

  removeEventListener(type: string, listener: Listener): void {
    this.listeners.get(type)?.delete(listener);
  }

  send(data: string): void {
    this.sent.push(data);
  }

  close(code?: number, reason?: string): void {
    this.closed = { code, reason };
  }

  emit(type: string, event: unknown = {}): void {
    for (const listener of [...(this.listeners.get(type) ?? [])]) {
      (listener as (event: unknown) => void)(event);
    }
  }
}

function transportFor(socket: FakeSocket): WebSocketControlTransport {
  return new WebSocketControlTransport({
    factory: (url) => {
      expect(url).toBe(socket.url);
      return socket as unknown as WebSocket;
    }
  });
}

describe('loopback WebSocket transport', () => {
  it('connects to the endpoint path with the session token and exchanges text messages', async () => {
    const socket = new FakeSocket(
      `ws://127.0.0.1:51234/endpoint?token=${encodeURIComponent(TOKEN)}`
    );
    const transport = transportFor(socket);
    const pending = transport.connect(REQUEST);
    socket.emit('open');
    const connection = await pending;

    const messages: unknown[] = [];
    connection.onMessage((message) => messages.push(message));
    connection.send({ type: 'display.register', workspaceId: 'workspace-alpha' });

    expect(socket.sent).toEqual([
      JSON.stringify({ type: 'display.register', workspaceId: 'workspace-alpha' })
    ]);

    socket.emit('message', { data: JSON.stringify({ type: 'display.registered' }) });
    expect(messages).toEqual([{ type: 'display.registered' }]);

    connection.close(1000, 'done');
    expect(socket.closed).toEqual({ code: 1000, reason: 'done' });
  });

  it('rejects a failed handshake before the socket opens', async () => {
    const socket = new FakeSocket(
      `ws://127.0.0.1:51234/endpoint?token=${encodeURIComponent(TOKEN)}`
    );
    const pending = transportFor(socket).connect(REQUEST);
    socket.emit('close', { code: 1008, reason: 'origin-mismatch' });

    await expect(pending).rejects.toMatchObject({
      code: 'connection-closed',
      message: 'origin-mismatch'
    });
  });

  it('surfaces an abnormal close after registration', async () => {
    const socket = new FakeSocket(
      `ws://127.0.0.1:51234/endpoint?token=${encodeURIComponent(TOKEN)}`
    );
    const pending = transportFor(socket).connect(REQUEST);
    socket.emit('open');
    const connection = await pending;
    const closed: Array<{ code?: string } | undefined> = [];
    connection.onClose((error) => closed.push(error));

    socket.emit('close', { code: 1008, reason: 'token-expired' });
    expect(closed).toEqual([expect.objectContaining({ code: 'connection-closed', message: 'token-expired' })]);
  });

  it('rejects remote URLs and invalid tokens before creating a socket', async () => {
    let created = 0;
    const transport = new WebSocketControlTransport({
      factory: () => {
        created += 1;
        return new FakeSocket('') as unknown as WebSocket;
      }
    });

    await expect(
      transport.connect({ ...REQUEST, url: 'ws://relay.example.com:51234/' })
    ).rejects.toMatchObject({ code: 'invalid-loopback-url' });
    await expect(transport.connect({ ...REQUEST, token: 'short' })).rejects.toMatchObject({
      code: 'invalid-token'
    });
    expect(created).toBe(0);
  });
});
