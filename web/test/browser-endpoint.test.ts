import { describe, expect, it } from 'vitest';
import {
  BrowserEndpointClient,
  BrowserEndpointError,
  assertBrowserTransport,
  parseLoopbackEndpoint,
  parseLoopbackOrigin,
  validateLocalAssetRequest
} from '../src/endpoint';
import type {
  ControlConnectRequest,
  ControlConnection,
  ControlTransport,
  Unsubscribe
} from '../src/endpoint';

const TOKEN = `token_${'a'.repeat(32)}`;
const PAGE_ORIGIN = 'http://127.0.0.1:51234';

class FakeConnection implements ControlConnection {
  readonly sent: unknown[] = [];
  closed = false;
  private messageHandlers: Array<(message: unknown) => void> = [];
  private closeHandlers: Array<(error?: BrowserEndpointError) => void> = [];
  private errorHandlers: Array<(error: BrowserEndpointError) => void> = [];

  send(message: unknown): void {
    this.sent.push(message);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    for (const handler of this.closeHandlers) handler();
  }

  onMessage(handler: (message: unknown) => void): Unsubscribe {
    this.messageHandlers.push(handler);
    return () => {
      this.messageHandlers = this.messageHandlers.filter((item) => item !== handler);
    };
  }

  onClose(handler: (error?: BrowserEndpointError) => void): Unsubscribe {
    this.closeHandlers.push(handler);
    return () => {
      this.closeHandlers = this.closeHandlers.filter((item) => item !== handler);
    };
  }

  onError(handler: (error: BrowserEndpointError) => void): Unsubscribe {
    this.errorHandlers.push(handler);
    return () => {
      this.errorHandlers = this.errorHandlers.filter((item) => item !== handler);
    };
  }

  emitMessage(message: unknown): void {
    for (const handler of [...this.messageHandlers]) handler(message);
  }

  emitClose(error?: BrowserEndpointError): void {
    for (const handler of [...this.closeHandlers]) handler(error);
  }

  emitError(error: BrowserEndpointError): void {
    for (const handler of [...this.errorHandlers]) handler(error);
  }
}

class FakeTransport implements ControlTransport {
  readonly requests: ControlConnectRequest[] = [];
  readonly connections: FakeConnection[] = [];
  rejectWith: BrowserEndpointError | null = null;

  async connect(request: ControlConnectRequest): Promise<ControlConnection> {
    this.requests.push(request);
    if (this.rejectWith) throw this.rejectWith;
    const connection = new FakeConnection();
    this.connections.push(connection);
    return connection;
  }

  latest(): FakeConnection {
    const connection = this.connections[this.connections.length - 1];
    if (!connection) throw new Error('no connection');
    return connection;
  }
}

function endpointFailure(action: () => unknown): string {
  try {
    action();
  } catch (error) {
    if (error instanceof BrowserEndpointError) return error.code;
    throw error;
  }
  throw new Error('expected endpoint failure');
}

function makeClient(
  transport: FakeTransport,
  overrides: Partial<ConstructorParameters<typeof BrowserEndpointClient>[0]> = {}
): BrowserEndpointClient {
  return new BrowserEndpointClient({
    port: 51234,
    pageOrigin: PAGE_ORIGIN,
    token: TOKEN,
    workspaceId: 'workspace-alpha',
    displaySessionId: 'display-1',
    transport,
    ...overrides
  });
}

describe('loopback endpoint policy', () => {
  it('accepts only ws://127.0.0.1:<port>', () => {
    expect(parseLoopbackEndpoint('ws://127.0.0.1:51234')).toMatchObject({
      port: 51234,
      origin: 'ws://127.0.0.1:51234'
    });
    expect(parseLoopbackEndpoint({ port: 51234 }).port).toBe(51234);

    for (const url of [
      'ws://localhost:51234',
      'wss://127.0.0.1:51234',
      'ws://192.168.1.10:51234',
      'ws://10.0.0.5:51234',
      'ws://relay.example.com:51234',
      'ws://127.0.0.1',
      'ws://127.0.0.1:0',
      'ws://user@127.0.0.1:51234',
      'https://127.0.0.1:51234'
    ]) {
      expect(endpointFailure(() => parseLoopbackEndpoint(url))).toBe(
        url === 'ws://127.0.0.1' || url === 'ws://127.0.0.1:0'
          ? 'invalid-port'
          : 'invalid-loopback-url'
      );
    }
  });

  it('validates loopback page origins strictly', () => {
    expect(parseLoopbackOrigin('http://127.0.0.1:51234', 51234)).toMatchObject({
      origin: 'http://127.0.0.1:51234',
      port: 51234
    });
    expect(endpointFailure(() => parseLoopbackOrigin('http://127.0.0.1:51234', 5000))).toBe(
      'invalid-origin'
    );
    expect(endpointFailure(() => parseLoopbackOrigin('http://localhost:51234'))).toBe(
      'invalid-origin'
    );
    expect(endpointFailure(() => parseLoopbackOrigin('https://192.168.1.4:51234'))).toBe(
      'invalid-origin'
    );
  });

  it('rejects WebTransport and other non-WebSocket browser transports', () => {
    expect(() => assertBrowserTransport('websocket')).not.toThrow();
    expect(endpointFailure(() => assertBrowserTransport('webtransport'))).toBe(
      'unsupported-transport'
    );
  });
});

describe('browser endpoint display client', () => {
  it('dials loopback, registers a display sink and reconnects without recreating the workspace', async () => {
    const transport = new FakeTransport();
    const client = makeClient(transport, { viewport: { width: 1024, height: 768 } });
    const statuses: string[] = [];
    client.onStatus((status) => statuses.push(status));

    await client.start();
    expect(transport.requests).toHaveLength(1);
    expect(transport.requests[0]).toMatchObject({
      url: 'ws://127.0.0.1:51234/',
      origin: PAGE_ORIGIN,
      token: TOKEN,
      role: 'display'
    });

    const first = transport.latest();
    expect(first.sent[0]).toMatchObject({
      type: 'display.register',
      role: 'display',
      authority: 'none',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1',
      canWriteWorkspace: false,
      viewport: { width: 1024, height: 768 }
    });

    first.emitMessage({
      type: 'display.registered',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1'
    });
    expect(client.snapshot()).toMatchObject({
      status: 'connected',
      connected: true,
      registered: true,
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1'
    });

    client.setViewport(1280, 720);
    expect(first.sent[1]).toMatchObject({
      type: 'display.viewport',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1',
      viewport: { width: 1280, height: 720 }
    });

    first.emitClose();
    expect(client.snapshot().status).toBe('disconnected');

    await client.reconnect();
    expect(transport.requests).toHaveLength(2);
    expect(transport.requests[1]).toMatchObject({
      url: 'ws://127.0.0.1:51234/',
      origin: PAGE_ORIGIN,
      token: TOKEN
    });

    const second = transport.latest();
    expect(second.sent[0]).toMatchObject({
      type: 'display.register',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1',
      viewport: { width: 1280, height: 720 }
    });
    second.emitMessage({
      type: 'display.registered',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1'
    });
    expect(client.snapshot()).toMatchObject({
      status: 'connected',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1'
    });
    expect(statuses).toContain('connecting');
    expect(statuses).toContain('registering');
    expect(statuses).toContain('connected');
    expect(statuses).toContain('disconnected');
  });

  it('rejects non-loopback origins and invalid tokens before dialing', async () => {
    const lanTransport = new FakeTransport();
    const lanClient = makeClient(lanTransport, {
      pageOrigin: 'http://192.168.1.4:51234'
    });
    await expect(lanClient.start()).rejects.toMatchObject({ code: 'invalid-origin' });
    expect(lanTransport.requests).toHaveLength(0);
    expect(lanClient.snapshot()).toMatchObject({
      status: 'failed',
      lastError: { code: 'invalid-origin' }
    });

    const tokenTransport = new FakeTransport();
    const tokenClient = makeClient(tokenTransport, { token: 'short' });
    await expect(tokenClient.start()).rejects.toMatchObject({ code: 'invalid-token' });
    expect(tokenTransport.requests).toHaveLength(0);
  });

  it('fails closed on transport rejection without falling back to a relay', async () => {
    const transport = new FakeTransport();
    transport.rejectWith = new BrowserEndpointError(
      'handshake-rejected',
      'loopback agent rejected the token'
    );
    const client = makeClient(transport);

    await expect(client.start()).rejects.toMatchObject({ code: 'handshake-rejected' });
    expect(transport.requests).toHaveLength(1);
    expect(client.snapshot()).toMatchObject({
      status: 'failed',
      connected: false,
      registered: false,
      lastError: { code: 'handshake-rejected' }
    });
  });

  it('fails closed when the loopback agent reports another workspace or display session', async () => {
    const transport = new FakeTransport();
    const client = makeClient(transport);
    await client.start();
    transport.latest().emitMessage({
      type: 'display.registered',
      workspaceId: 'workspace-other',
      displaySessionId: 'display-1'
    });

    expect(client.snapshot()).toMatchObject({
      status: 'failed',
      lastError: { code: 'workspace-mismatch' }
    });
    expect(transport.latest().closed).toBe(true);

    const secondTransport = new FakeTransport();
    const secondClient = makeClient(secondTransport);
    await secondClient.start();
    secondTransport.latest().emitMessage({
      type: 'display.registered',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-other'
    });
    expect(secondClient.snapshot()).toMatchObject({
      status: 'failed',
      lastError: { code: 'display-session-mismatch' }
    });
  });
});

describe('local browser assets', () => {
  it('accepts first-party loopback assets with the session token', () => {
    const asset = validateLocalAssetRequest({
      pageOrigin: PAGE_ORIGIN,
      assetUrl: `/shell.js?token=${TOKEN}`,
      token: TOKEN,
      expectedToken: TOKEN,
      kind: 'script'
    });

    expect(asset).toMatchObject({
      origin: PAGE_ORIGIN,
      path: '/shell.js',
      kind: 'script',
      executable: true
    });
  });

  it('rejects remote assets, remote executable code, wrong origins and bad tokens', () => {
    expect(
      endpointFailure(() =>
        validateLocalAssetRequest({
          pageOrigin: PAGE_ORIGIN,
          assetUrl: `https://cdn.example.com/shell.js?token=${TOKEN}`,
          token: TOKEN,
          expectedToken: TOKEN,
          kind: 'script'
        })
      )
    ).toBe('remote-asset-rejected');

    expect(
      endpointFailure(() =>
        validateLocalAssetRequest({
          pageOrigin: PAGE_ORIGIN,
          assetUrl: `data:text/javascript,alert(1)`,
          token: TOKEN,
          expectedToken: TOKEN,
          kind: 'script'
        })
      )
    ).toBe('remote-asset-rejected');

    expect(
      endpointFailure(() =>
        validateLocalAssetRequest({
          pageOrigin: PAGE_ORIGIN,
          assetUrl: `http://127.0.0.1:51235/shell.js?token=${TOKEN}`,
          token: TOKEN,
          expectedToken: TOKEN,
          kind: 'script'
        })
      )
    ).toBe('remote-asset-rejected');

    expect(
      endpointFailure(() =>
        validateLocalAssetRequest({
          pageOrigin: PAGE_ORIGIN,
          assetUrl: '/shell.js?token=wrong',
          token: TOKEN,
          expectedToken: TOKEN,
          kind: 'script'
        })
      )
    ).toBe('invalid-token');
  });
});
