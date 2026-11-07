import {
  BROWSER_ENDPOINT_ROLE,
  BROWSER_ENDPOINT_TRANSPORT,
  BrowserEndpointError,
  assertBrowserTransport,
  parseLoopbackEndpoint,
  validateSessionToken
} from './loopback';
import type { ControlConnectRequest, ControlConnection, ControlTransport, Unsubscribe } from './client';

export const DEFAULT_ENDPOINT_PATH = '/endpoint';

export interface WebSocketControlTransportOptions {
  path?: string;
  factory?: (url: string) => WebSocket;
}

function socketUrl(request: ControlConnectRequest, path: string): string {
  const endpoint = parseLoopbackEndpoint(request.url);
  const url = new URL(endpoint.url);
  url.pathname = path;
  url.search = '';
  url.hash = '';
  url.searchParams.set('token', request.token);
  return url.toString();
}

function closeError(event: CloseEvent): BrowserEndpointError | null {
  if (event.code === 1000) return null;
  const reason = event.reason.trim();
  return new BrowserEndpointError(
    'connection-closed',
    reason.length > 0 ? reason.slice(0, 500) : `browser endpoint closed (${event.code})`
  );
}

export class WebSocketControlTransport implements ControlTransport {
  private readonly path: string;
  private readonly factory: (url: string) => WebSocket;

  constructor(options: WebSocketControlTransportOptions = {}) {
    const path = options.path ?? DEFAULT_ENDPOINT_PATH;
    if (!path.startsWith('/') || path.includes('?') || path.includes('#')) {
      throw new BrowserEndpointError('invalid-state', 'invalid loopback endpoint path');
    }
    this.path = path;
    this.factory = options.factory ?? ((url) => new WebSocket(url));
  }

  connect(request: ControlConnectRequest): Promise<ControlConnection> {
    try {
      assertBrowserTransport(BROWSER_ENDPOINT_TRANSPORT);
      if (request.role !== BROWSER_ENDPOINT_ROLE) {
        throw new BrowserEndpointError('invalid-state', 'invalid browser endpoint role');
      }
      validateSessionToken(request.token);
    } catch (error) {
      return Promise.reject(error);
    }

    let socket: WebSocket;
    try {
      socket = this.factory(socketUrl(request, this.path));
    } catch (error) {
      return Promise.reject(
        error instanceof BrowserEndpointError
          ? error
          : new BrowserEndpointError('transport-failure', 'browser endpoint WebSocket failed')
      );
    }

    return new Promise<ControlConnection>((resolve, reject) => {
      let opened = false;
      let closed = false;
      let messageHandlers: Array<(message: unknown) => void> = [];
      let closeHandlers: Array<(error?: BrowserEndpointError) => void> = [];
      let errorHandlers: Array<(error: BrowserEndpointError) => void> = [];

      const emitError = (error: BrowserEndpointError): void => {
        for (const handler of [...errorHandlers]) {
          try {
            handler(error);
          } catch {
            // A failing observer must not break transport cleanup.
          }
        }
      };

      const emitClose = (error?: BrowserEndpointError): void => {
        for (const handler of [...closeHandlers]) {
          try {
            handler(error);
          } catch {
            // A failing observer must not break transport cleanup.
          }
        }
      };

      const detach = (): void => {
        socket.removeEventListener('message', onMessage);
        socket.removeEventListener('close', onClose);
        socket.removeEventListener('error', onError);
      };

      const onOpen = (): void => {
        if (closed) return;
        opened = true;
        socket.removeEventListener('open', onOpen);
        resolve(connection);
      };

      const onMessage = (event: MessageEvent): void => {
        if (typeof event.data !== 'string') {
          emitError(new BrowserEndpointError('protocol-error', 'browser endpoint requires text messages'));
          return;
        }
        let message: unknown;
        try {
          message = JSON.parse(event.data);
        } catch {
          emitError(new BrowserEndpointError('protocol-error', 'invalid browser endpoint message'));
          return;
        }
        for (const handler of [...messageHandlers]) {
          try {
            handler(message);
          } catch {
            emitError(new BrowserEndpointError('protocol-error', 'browser endpoint message handler failed'));
          }
        }
      };

      const onError = (): void => {
        const error = new BrowserEndpointError('transport-failure', 'browser endpoint WebSocket failed');
        if (!opened) {
          closed = true;
          detach();
          reject(error);
          return;
        }
        emitError(error);
      };

      const onClose = (event: CloseEvent): void => {
        if (closed) return;
        closed = true;
        detach();
        const error = closeError(event);
        if (!opened) {
          reject(error ?? new BrowserEndpointError('handshake-rejected', 'browser endpoint handshake failed'));
          return;
        }
        emitClose(error ?? undefined);
      };

      const connection: ControlConnection = {
        send(message: unknown): void {
          if (closed || !opened) {
            throw new BrowserEndpointError('invalid-state', 'browser endpoint is not connected');
          }
          socket.send(JSON.stringify(message));
        },
        close(code = 1000, reason = 'client-stop'): void {
          if (closed) return;
          socket.close(code, reason);
        },
        onMessage(handler: (message: unknown) => void): Unsubscribe {
          messageHandlers.push(handler);
          return () => {
            messageHandlers = messageHandlers.filter((item) => item !== handler);
          };
        },
        onClose(handler: (error?: BrowserEndpointError) => void): Unsubscribe {
          closeHandlers.push(handler);
          return () => {
            closeHandlers = closeHandlers.filter((item) => item !== handler);
          };
        },
        onError(handler: (error: BrowserEndpointError) => void): Unsubscribe {
          errorHandlers.push(handler);
          return () => {
            errorHandlers = errorHandlers.filter((item) => item !== handler);
          };
        }
      };

      socket.addEventListener('open', onOpen);
      socket.addEventListener('message', onMessage);
      socket.addEventListener('close', onClose);
      socket.addEventListener('error', onError);
    });
  }
}
