export const LOOPBACK_HOST = '127.0.0.1';
export const BROWSER_ENDPOINT_ROLE = 'display' as const;
export const BROWSER_ENDPOINT_TRANSPORT = 'websocket' as const;

export type BrowserEndpointErrorCode =
  | 'unsupported-transport'
  | 'invalid-loopback-url'
  | 'invalid-port'
  | 'invalid-origin'
  | 'invalid-token'
  | 'invalid-state'
  | 'transport-failure'
  | 'handshake-rejected'
  | 'protocol-error'
  | 'workspace-mismatch'
  | 'display-session-mismatch'
  | 'connection-closed'
  | 'remote-asset-rejected';

export class BrowserEndpointError extends Error {
  readonly code: BrowserEndpointErrorCode;

  constructor(code: BrowserEndpointErrorCode, message: string) {
    super(message);
    this.name = 'BrowserEndpointError';
    this.code = code;
  }
}

export interface LoopbackEndpoint {
  url: string;
  port: number;
  origin: string;
}

export interface LoopbackOrigin {
  origin: string;
  port: number;
  protocol: 'http:' | 'https:';
}

function validPort(port: number): boolean {
  return Number.isSafeInteger(port) && port > 0 && port <= 65_535;
}

export function parseLoopbackEndpoint(input: string | { port: number }): LoopbackEndpoint {
  let raw: string;
  if (typeof input === 'string') {
    raw = input;
  } else {
    if (!validPort(input.port)) {
      throw new BrowserEndpointError('invalid-port', 'invalid loopback port');
    }
    raw = `ws://${LOOPBACK_HOST}:${input.port}`;
  }

  const authority = /^ws:\/\/127\.0\.0\.1(?::([0-9]*))?(?=[/?#]|$)/i.exec(raw);
  if (raw.includes('\\') || !authority) {
    throw new BrowserEndpointError(
      'invalid-loopback-url',
      'browser endpoint must use ws://127.0.0.1:<port>'
    );
  }
  if (!authority[1] || !validPort(Number(authority[1]))) {
    throw new BrowserEndpointError('invalid-port', 'loopback port is required');
  }

  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new BrowserEndpointError('invalid-loopback-url', 'invalid loopback URL');
  }

  if (
    url.protocol !== 'ws:' ||
    url.hostname !== LOOPBACK_HOST ||
    url.username !== '' ||
    url.password !== '' ||
    url.hash !== ''
  ) {
    throw new BrowserEndpointError(
      'invalid-loopback-url',
      'browser endpoint must use ws://127.0.0.1:<port>'
    );
  }

  if (!validPort(Number(url.port)) || url.port === '') {
    throw new BrowserEndpointError('invalid-port', 'loopback port is required');
  }

  const port = Number(url.port);
  return {
    url: `ws://${LOOPBACK_HOST}:${port}${url.pathname}${url.search}`,
    port,
    origin: `ws://${LOOPBACK_HOST}:${port}`
  };
}

export function parseLoopbackOrigin(origin: string, expectedPort?: number): LoopbackOrigin {
  if (origin.includes('\\')) {
    throw new BrowserEndpointError('invalid-origin', 'invalid browser origin');
  }
  const prefix = /^(https?):\/\/127\.0\.0\.1:/.exec(origin);
  if (!prefix) {
    throw new BrowserEndpointError(
      'invalid-origin',
      'browser endpoint origin must be loopback'
    );
  }

  let url: URL;
  try {
    url = new URL(origin);
  } catch {
    throw new BrowserEndpointError('invalid-origin', 'invalid browser origin');
  }

  if (
    (url.protocol !== 'http:' && url.protocol !== 'https:') ||
    url.hostname !== LOOPBACK_HOST ||
    url.username !== '' ||
    url.password !== '' ||
    url.port === ''
  ) {
    throw new BrowserEndpointError(
      'invalid-origin',
      'browser endpoint origin must be loopback'
    );
  }

  const port = Number(url.port);
  if (!validPort(port)) {
    throw new BrowserEndpointError('invalid-origin', 'invalid browser origin port');
  }
  if (expectedPort !== undefined && port !== expectedPort) {
    throw new BrowserEndpointError(
      'invalid-origin',
      'browser origin does not match loopback endpoint'
    );
  }

  return {
    origin: `${url.protocol}//${LOOPBACK_HOST}:${port}`,
    port,
    protocol: url.protocol
  };
}

export function validateSessionToken(token: string): void {
  if (!/^[A-Za-z0-9._~-]{16,4096}$/.test(token)) {
    throw new BrowserEndpointError('invalid-token', 'invalid session token');
  }
}

export function assertBrowserTransport(transport: string): void {
  if (transport.toLowerCase() !== BROWSER_ENDPOINT_TRANSPORT) {
    throw new BrowserEndpointError(
      'unsupported-transport',
      'browser endpoint supports loopback WebSocket only'
    );
  }
}
