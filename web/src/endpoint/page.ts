import { BrowserEndpointClient } from './client';
import type { BrowserEndpointStatus, ControlTransport } from './client';
import {
  BrowserEndpointError,
  parseLoopbackEndpoint,
  parseLoopbackOrigin,
  validateSessionToken
} from './loopback';
import { WebSocketControlTransport } from './websocket';

const ID_PATTERN = /^[A-Za-z0-9._:-]{1,256}$/;
const MAX_AUTO_RECONNECTS = 8;

export interface PresentationConfig {
  endpoint: string;
  endpointPath: string;
  port: number;
  token: string;
  workspaceId: string;
  displaySessionId: string;
  pageOrigin: string;
}

function identifier(value: string | null, name: string): string {
  if (!value || !ID_PATTERN.test(value)) {
    throw new BrowserEndpointError('invalid-state', `invalid ${name}`);
  }
  return value;
}

export function readPresentationConfig(
  location: Pick<Location, 'origin' | 'search'>
): PresentationConfig {
  const params = new URLSearchParams(location.search);
  const endpoint = parseLoopbackEndpoint(params.get('endpoint') ?? '');
  const endpointURL = new URL(endpoint.url);
  const token = params.get('token') ?? '';
  validateSessionToken(token);
  const page = parseLoopbackOrigin(location.origin);
  return {
    endpoint: endpoint.url,
    endpointPath: endpointURL.pathname || '/endpoint',
    port: endpoint.port,
    token,
    workspaceId: identifier(params.get('workspace'), 'workspace id'),
    displaySessionId: identifier(params.get('display'), 'display session id'),
    pageOrigin: page.origin
  };
}

function statusLabel(status: BrowserEndpointStatus): string {
  switch (status) {
    case 'idle':
      return 'Idle';
    case 'connecting':
      return 'Connecting';
    case 'registering':
      return 'Registering';
    case 'connected':
      return 'Connected';
    case 'disconnected':
      return 'Disconnected';
    case 'failed':
      return 'Failed';
  }
}

function requireElement<T extends HTMLElement>(document: Document, id: string): T {
  const element = document.getElementById(id);
  if (!element) {
    throw new Error(`missing endpoint page element: ${id}`);
  }
  return element as T;
}

export interface EndpointPageController {
  readonly client: BrowserEndpointClient;
  readonly config: PresentationConfig;
  dispose(): void;
}

export function startEndpointPage(
  window: Window,
  transport?: ControlTransport
): EndpointPageController {
  const config = readPresentationConfig(window.location);
  const document = window.document;
  const client = new BrowserEndpointClient({
    port: config.port,
    pageOrigin: config.pageOrigin,
    token: config.token,
    workspaceId: config.workspaceId,
    displaySessionId: config.displaySessionId,
    transport: transport ?? new WebSocketControlTransport({ path: config.endpointPath }),
    viewport: {
      width: Math.max(1, Math.round(window.innerWidth)),
      height: Math.max(1, Math.round(window.innerHeight))
    }
  });

  const status = requireElement<HTMLElement>(document, 'endpoint-status');
  const detail = requireElement<HTMLElement>(document, 'endpoint-detail');
  const error = requireElement<HTMLElement>(document, 'endpoint-error');
  const reconnect = requireElement<HTMLButtonElement>(document, 'endpoint-reconnect');
  const workspace = requireElement<HTMLElement>(document, 'endpoint-workspace');
  const display = requireElement<HTMLElement>(document, 'endpoint-display');
  const endpoint = requireElement<HTMLElement>(document, 'endpoint-url');
  const indicator = requireElement<HTMLElement>(document, 'endpoint-indicator');

  let disposed = false;
  let reconnectTimer: number | null = null;
  let reconnectAttempts = 0;

  const update = (): void => {
    const snapshot = client.snapshot();
    status.textContent = statusLabel(snapshot.status);
    detail.textContent =
      snapshot.status === 'connected'
        ? 'Display registered. Waiting for workspace surface updates.'
        : snapshot.status === 'registering'
          ? 'Waiting for the loopback host to confirm this display session.'
          : snapshot.status === 'connecting'
            ? 'Dialing the loopback host.'
            : 'The display session is not connected.';
    error.textContent = snapshot.lastError
      ? `${snapshot.lastError.code}: ${snapshot.lastError.message}`
      : '';
    reconnect.disabled =
      snapshot.status === 'connecting' ||
      snapshot.status === 'registering' ||
      snapshot.status === 'connected';
    workspace.textContent = snapshot.workspaceId;
    display.textContent = snapshot.displaySessionId;
    endpoint.textContent = config.endpoint;
    indicator.dataset.status = snapshot.status;
  };

  const scheduleReconnect = (): void => {
    if (disposed || reconnectTimer !== null || reconnectAttempts >= MAX_AUTO_RECONNECTS) return;
    const delay = Math.min(5_000, 500 * 2 ** reconnectAttempts);
    reconnectAttempts += 1;
    reconnectTimer = window.setTimeout(() => {
      reconnectTimer = null;
      if (disposed) return;
      void client.reconnect().catch(() => {
        update();
        scheduleReconnect();
      });
    }, delay);
  };

  const reconnectNow = async (): Promise<void> => {
    if (disposed) return;
    if (reconnectTimer !== null) {
      window.clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    reconnectAttempts = 0;
    try {
      await client.reconnect();
    } catch {
      update();
      scheduleReconnect();
    }
  };

  const updateViewport = (): void => {
    try {
      client.setViewport(
        Math.max(1, Math.round(window.innerWidth)),
        Math.max(1, Math.round(window.innerHeight))
      );
    } catch {
      // Ignore transient layout races while the endpoint is transitioning.
    }
  };

  const onFocusIn = (event: FocusEvent): void => {
    const target = event.target as HTMLElement | null;
    const name =
      target?.getAttribute('data-focus-target') ??
      target?.id ??
      target?.tagName.toLowerCase() ??
      'document';
    try {
      client.setFocus(name.slice(0, 512));
    } catch {
      // Losing a transient focus update does not affect the display session.
    }
  };

  const onFocusOut = (): void => {
    try {
      client.setFocus(null);
    } catch {
      // Losing a transient focus update does not affect the display session.
    }
  };

  const onPageHide = (): void => {
    dispose();
  };

  const subscriptions = [
    client.onStatus((next) => {
      if (next === 'connected') reconnectAttempts = 0;
      update();
      if (next === 'disconnected' || next === 'failed') scheduleReconnect();
    }),
    client.onError(() => update())
  ];

  const ResizeObserverConstructor = (
    window as unknown as {
      ResizeObserver?: new (callback: ResizeObserverCallback) => ResizeObserver;
    }
  ).ResizeObserver;
  const resizeObserver =
    typeof ResizeObserverConstructor === 'function'
      ? new ResizeObserverConstructor(() => updateViewport())
      : null;
  resizeObserver?.observe(document.documentElement);
  window.addEventListener('resize', updateViewport);
  document.addEventListener('focusin', onFocusIn);
  document.addEventListener('focusout', onFocusOut);
  window.addEventListener('pagehide', onPageHide);
  reconnect.addEventListener('click', () => {
    void reconnectNow();
  });

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    if (reconnectTimer !== null) {
      window.clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    for (const unsubscribe of subscriptions) unsubscribe();
    resizeObserver?.disconnect();
    window.removeEventListener('resize', updateViewport);
    document.removeEventListener('focusin', onFocusIn);
    document.removeEventListener('focusout', onFocusOut);
    window.removeEventListener('pagehide', onPageHide);
    void client.stop();
  }

  update();
  void client.start().catch(() => {
    update();
  });

  return { client, config, dispose };
}
