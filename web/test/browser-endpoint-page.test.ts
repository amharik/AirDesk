import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { afterEach, describe, expect, it } from 'vitest';
import { readPresentationConfig, startEndpointPage } from '../src/endpoint/page';
import type {
  BrowserEndpointError,
  ControlConnectRequest,
  ControlConnection,
  ControlTransport,
  Unsubscribe
} from '../src/endpoint';

const TOKEN = `token_${'a'.repeat(32)}`;
const PAGE_HTML = readFileSync(resolve(process.cwd(), 'src/endpoint/page.html'), 'utf8');
const PAGE_URL =
  `http://127.0.0.1:51234/endpoint.html?endpoint=${encodeURIComponent('ws://127.0.0.1:51999/endpoint')}` +
  `&token=${encodeURIComponent(TOKEN)}&workspace=workspace-alpha&display=display-1`;

const openPages: Array<{ dispose(): void }> = [];

afterEach(() => {
  for (const page of openPages.splice(0)) page.dispose();
});

class FakeConnection implements ControlConnection {
  readonly sent: unknown[] = [];
  private messageHandlers: Array<(message: unknown) => void> = [];
  private closeHandlers: Array<(error?: BrowserEndpointError) => void> = [];

  send(message: unknown): void {
    this.sent.push(message);
  }

  close(): void {}

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

  onError(): Unsubscribe {
    return () => {};
  }

  emitMessage(message: unknown): void {
    for (const handler of [...this.messageHandlers]) handler(message);
  }

  emitClose(): void {
    for (const handler of [...this.closeHandlers]) handler();
  }
}

class FakeTransport implements ControlTransport {
  readonly requests: ControlConnectRequest[] = [];
  readonly connections: FakeConnection[] = [];

  async connect(request: ControlConnectRequest): Promise<ControlConnection> {
    this.requests.push(request);
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

async function settle(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function makePage(): { dom: JSDOM; transport: FakeTransport } {
  const dom = new JSDOM(PAGE_HTML, { url: PAGE_URL, pretendToBeVisual: true });
  const transport = new FakeTransport();
  const controller = startEndpointPage(dom.window as unknown as Window, transport);
  openPages.push(controller);
  return { dom, transport };
}

describe('browser endpoint presentation page', () => {
  it('reads a scoped loopback presentation link', () => {
    expect(readPresentationConfig(new URL(PAGE_URL))).toMatchObject({
      endpoint: 'ws://127.0.0.1:51999/endpoint',
      endpointPath: '/endpoint',
      port: 51999,
      token: TOKEN,
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1',
      pageOrigin: 'http://127.0.0.1:51234'
    });
  });

  it('rejects incomplete or non-loopback presentation links', () => {
    expect(() =>
      readPresentationConfig(
        new URL('http://127.0.0.1:51234/endpoint.html?endpoint=ws%3A%2F%2F127.0.0.1%3A51999')
      )
    ).toThrow('invalid session token');
    expect(() =>
      readPresentationConfig(
        new URL(
          `https://example.com/endpoint.html?endpoint=${encodeURIComponent('ws://example.com:51999')}` +
            `&token=${TOKEN}&workspace=workspace-alpha&display=display-1`
        )
      )
    ).toThrow('browser endpoint must use ws://127.0.0.1:<port>');
  });

  it('registers, reports status and reconnects the same display session', async () => {
    const { dom, transport } = makePage();
    await settle();

    expect(transport.requests[0]?.url).toBe('ws://127.0.0.1:51999/');
    expect(transport.requests[0]?.token).toBe(TOKEN);
    expect(transport.latest().sent[0]).toMatchObject({
      type: 'display.register',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1'
    });

    transport.latest().emitMessage({
      type: 'display.registered',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1'
    });
    await settle();

    const document = dom.window.document;
    expect(document.getElementById('endpoint-status')?.textContent).toBe('Connected');
    expect(document.getElementById('endpoint-workspace')?.textContent).toBe('workspace-alpha');
    expect(document.getElementById('endpoint-display')?.textContent).toBe('display-1');
    expect(document.getElementById('endpoint-url')?.textContent).toBe(
      'ws://127.0.0.1:51999/endpoint'
    );

    transport.latest().emitClose();
    await settle();
    expect(document.getElementById('endpoint-status')?.textContent).toBe('Disconnected');

    document.getElementById('endpoint-reconnect')?.click();
    await settle();

    expect(transport.requests).toHaveLength(2);
    expect(transport.latest().sent[0]).toMatchObject({
      type: 'display.register',
      workspaceId: 'workspace-alpha',
      displaySessionId: 'display-1'
    });
  });
});
