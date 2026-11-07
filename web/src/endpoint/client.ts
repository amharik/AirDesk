import {
  BROWSER_ENDPOINT_ROLE,
  BROWSER_ENDPOINT_TRANSPORT,
  BrowserEndpointError,
  assertBrowserTransport,
  parseLoopbackEndpoint,
  parseLoopbackOrigin,
  validateSessionToken
} from './loopback';
import type { BrowserEndpointErrorCode } from './loopback';

export interface ControlConnectRequest {
  url: string;
  origin: string;
  token: string;
  role: typeof BROWSER_ENDPOINT_ROLE;
}

export type Unsubscribe = () => void;

export interface ControlConnection {
  send(message: unknown): void;
  close(code?: number, reason?: string): void;
  onMessage(handler: (message: unknown) => void): Unsubscribe;
  onClose(handler: (error?: BrowserEndpointError) => void): Unsubscribe;
  onError(handler: (error: BrowserEndpointError) => void): Unsubscribe;
}

export interface ControlTransport {
  connect(request: ControlConnectRequest): Promise<ControlConnection>;
}

export type BrowserEndpointStatus =
  | 'idle'
  | 'connecting'
  | 'registering'
  | 'connected'
  | 'disconnected'
  | 'failed';

export interface DisplayViewport {
  width: number;
  height: number;
}

export interface BrowserDisplayState {
  workspaceId: string;
  displaySessionId: string;
  viewport: DisplayViewport;
  focusTarget: string | null;
  generation: number;
}

export interface BrowserEndpointSnapshot extends BrowserDisplayState {
  status: BrowserEndpointStatus;
  role: typeof BROWSER_ENDPOINT_ROLE;
  connected: boolean;
  registered: boolean;
  lastError: BrowserEndpointError | null;
}

export interface BrowserEndpointOptions {
  port: number;
  pageOrigin: string;
  token: string;
  workspaceId: string;
  displaySessionId: string;
  transport: ControlTransport;
  viewport?: DisplayViewport;
  focusTarget?: string | null;
  generation?: number;
}

const ID_PATTERN = /^[A-Za-z0-9._:-]{1,256}$/;

const ENDPOINT_ERROR_CODES = new Set<BrowserEndpointErrorCode>([
  'unsupported-transport',
  'invalid-loopback-url',
  'invalid-port',
  'invalid-origin',
  'invalid-token',
  'invalid-state',
  'transport-failure',
  'handshake-rejected',
  'protocol-error',
  'workspace-mismatch',
  'display-session-mismatch',
  'connection-closed',
  'remote-asset-rejected'
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function validViewport(value: unknown): value is DisplayViewport {
  return (
    isRecord(value) &&
    typeof value.width === 'number' &&
    Number.isFinite(value.width) &&
    value.width > 0 &&
    typeof value.height === 'number' &&
    Number.isFinite(value.height) &&
    value.height > 0
  );
}

function validIdentifier(value: string): boolean {
  return ID_PATTERN.test(value);
}

function toEndpointError(error: unknown): BrowserEndpointError {
  if (error instanceof BrowserEndpointError) return error;
  if (error instanceof Error) {
    return new BrowserEndpointError('transport-failure', error.message);
  }
  return new BrowserEndpointError('transport-failure', 'browser endpoint transport failed');
}

function errorCode(value: unknown): BrowserEndpointErrorCode {
  return typeof value === 'string' &&
    ENDPOINT_ERROR_CODES.has(value as BrowserEndpointErrorCode)
    ? (value as BrowserEndpointErrorCode)
    : 'protocol-error';
}

export class BrowserEndpointClient {
  readonly role = BROWSER_ENDPOINT_ROLE;

  private readonly options: BrowserEndpointOptions;
  private readonly state: BrowserDisplayState;
  private status: BrowserEndpointStatus = 'idle';
  private lastError: BrowserEndpointError | null = null;
  private registered = false;
  private connection: ControlConnection | null = null;
  private unsubscribers: Unsubscribe[] = [];
  private readonly statusHandlers = new Set<(status: BrowserEndpointStatus) => void>();
  private readonly errorHandlers = new Set<(error: BrowserEndpointError) => void>();
  private readonly displayHandlers = new Set<(message: Record<string, unknown>) => void>();

  constructor(options: BrowserEndpointOptions) {
    this.options = options;
    this.state = {
      workspaceId: options.workspaceId,
      displaySessionId: options.displaySessionId,
      viewport: {
        width: options.viewport?.width ?? 0,
        height: options.viewport?.height ?? 0
      },
      focusTarget: options.focusTarget ?? null,
      generation: options.generation ?? 0
    };
  }

  snapshot(): BrowserEndpointSnapshot {
    return {
      status: this.status,
      role: this.role,
      workspaceId: this.state.workspaceId,
      displaySessionId: this.state.displaySessionId,
      viewport: { ...this.state.viewport },
      focusTarget: this.state.focusTarget,
      generation: this.state.generation,
      connected: this.status === 'connected',
      registered: this.registered,
      lastError: this.lastError
    };
  }

  onStatus(handler: (status: BrowserEndpointStatus) => void): Unsubscribe {
    this.statusHandlers.add(handler);
    return () => this.statusHandlers.delete(handler);
  }

  onError(handler: (error: BrowserEndpointError) => void): Unsubscribe {
    this.errorHandlers.add(handler);
    return () => this.errorHandlers.delete(handler);
  }

  onDisplayMessage(handler: (message: Record<string, unknown>) => void): Unsubscribe {
    this.displayHandlers.add(handler);
    return () => this.displayHandlers.delete(handler);
  }

  async start(): Promise<void> {
    if (
      this.status === 'connecting' ||
      this.status === 'registering' ||
      this.status === 'connected'
    ) {
      throw new BrowserEndpointError('invalid-state', 'browser endpoint is already active');
    }
    await this.connect();
  }

  async reconnect(): Promise<void> {
    if (this.status === 'connecting' || this.status === 'registering') {
      throw new BrowserEndpointError('invalid-state', 'browser endpoint is already connecting');
    }
    if (this.connection) {
      const connection = this.connection;
      this.detach();
      this.connection = null;
      try {
        connection.close(1000, 'reconnect');
      } catch {
        this.lastError = null;
      }
    }
    this.state.generation += 1;
    await this.connect();
  }

  async stop(): Promise<void> {
    const connection = this.connection;
    this.detach();
    this.connection = null;
    this.registered = false;
    this.lastError = null;
    if (connection) {
      try {
        connection.close(1000, 'client-stop');
      } catch {
        this.lastError = null;
      }
    }
    this.setStatus('idle');
  }

  setViewport(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      throw new BrowserEndpointError('invalid-state', 'invalid viewport');
    }
    this.state.viewport = { width: Math.round(width), height: Math.round(height) };
    this.state.generation += 1;
    this.sendDisplayState('display.viewport');
  }

  setFocus(target: string | null): void {
    if (target !== null && (target.length === 0 || target.length > 512)) {
      throw new BrowserEndpointError('invalid-state', 'invalid focus target');
    }
    this.state.focusTarget = target;
    this.state.generation += 1;
    this.sendDisplayState('display.focus');
  }

  private async connect(): Promise<void> {
    this.lastError = null;
    this.registered = false;
    this.setStatus('connecting');

    try {
      if (!validIdentifier(this.state.workspaceId)) {
        throw new BrowserEndpointError('invalid-state', 'invalid workspace id');
      }
      if (!validIdentifier(this.state.displaySessionId)) {
        throw new BrowserEndpointError('invalid-state', 'invalid display session id');
      }
      assertBrowserTransport(BROWSER_ENDPOINT_TRANSPORT);
      validateSessionToken(this.options.token);
      const target = parseLoopbackEndpoint({ port: this.options.port });
      const page = parseLoopbackOrigin(this.options.pageOrigin);
      const connection = await this.options.transport.connect({
        url: target.url,
        origin: page.origin,
        token: this.options.token,
        role: BROWSER_ENDPOINT_ROLE
      });

      this.connection = connection;
      this.unsubscribers = [
        connection.onMessage((message) => this.handleMessage(message)),
        connection.onClose((error) => this.handleClose(error)),
        connection.onError((error) => this.fail(error))
      ];
      this.setStatus('registering');
      connection.send(this.registrationMessage());
    } catch (error) {
      const endpointError = toEndpointError(error);
      this.fail(endpointError);
      throw endpointError;
    }
  }

  private registrationMessage(): Record<string, unknown> {
    return {
      type: 'display.register',
      role: BROWSER_ENDPOINT_ROLE,
      authority: 'none',
      workspaceId: this.state.workspaceId,
      displaySessionId: this.state.displaySessionId,
      viewport: { ...this.state.viewport },
      focusTarget: this.state.focusTarget,
      generation: this.state.generation,
      canWriteWorkspace: false
    };
  }

  private sendDisplayState(type: 'display.viewport' | 'display.focus'): void {
    if (this.status !== 'connected' || !this.connection) return;
    this.connection.send({
      type,
      role: BROWSER_ENDPOINT_ROLE,
      authority: 'none',
      workspaceId: this.state.workspaceId,
      displaySessionId: this.state.displaySessionId,
      viewport: { ...this.state.viewport },
      focusTarget: this.state.focusTarget,
      generation: this.state.generation,
      canWriteWorkspace: false
    });
  }

  private handleMessage(message: unknown): void {
    if (!isRecord(message) || typeof message.type !== 'string') {
      this.fail(new BrowserEndpointError('protocol-error', 'invalid control message'));
      return;
    }

    if (message.type === 'display.registered') {
      if (message.workspaceId !== this.state.workspaceId) {
        this.fail(new BrowserEndpointError('workspace-mismatch', 'workspace mismatch'));
        return;
      }
      if (message.displaySessionId !== this.state.displaySessionId) {
        this.fail(
          new BrowserEndpointError('display-session-mismatch', 'display session mismatch')
        );
        return;
      }
      if (message.authority !== undefined && message.authority !== 'none') {
        this.fail(new BrowserEndpointError('protocol-error', 'display authority escalated'));
        return;
      }
      this.registered = true;
      this.setStatus('connected');
      return;
    }

    if (message.type === 'display.error') {
      this.fail(
        new BrowserEndpointError(
          errorCode(message.code),
          String(message.message ?? 'display session rejected').slice(0, 500)
        )
      );
      return;
    }

    if (!message.type.startsWith('display.')) {
      this.fail(new BrowserEndpointError('protocol-error', 'unexpected control message'));
      return;
    }

    if (message.type === 'display.surface') {
      if (message.workspaceId !== this.state.workspaceId) {
        this.fail(new BrowserEndpointError('workspace-mismatch', 'workspace mismatch'));
        return;
      }
      if (message.displaySessionId !== this.state.displaySessionId) {
        this.fail(
          new BrowserEndpointError('display-session-mismatch', 'display session mismatch')
        );
        return;
      }
      if (
        (message.mimeType !== 'image/jpeg' && message.mimeType !== 'image/png') ||
        typeof message.data !== 'string' ||
        message.data.length === 0 ||
        message.data.length > 11_000_000 ||
        typeof message.revision !== 'number' ||
        !Number.isSafeInteger(message.revision) ||
        message.revision < 0
      ) {
        this.fail(new BrowserEndpointError('protocol-error', 'invalid surface frame'));
        return;
      }
    }

    if (message.type === 'display.update') {
      if (
        message.workspaceId !== undefined &&
        message.workspaceId !== this.state.workspaceId
      ) {
        this.fail(new BrowserEndpointError('workspace-mismatch', 'workspace mismatch'));
        return;
      }
      if (
        message.displaySessionId !== undefined &&
        message.displaySessionId !== this.state.displaySessionId
      ) {
        this.fail(
          new BrowserEndpointError('display-session-mismatch', 'display session mismatch')
        );
        return;
      }
      if (validViewport(message.viewport)) {
        this.state.viewport = {
          width: Math.round(message.viewport.width),
          height: Math.round(message.viewport.height)
        };
      }
      if (message.focusTarget === null || typeof message.focusTarget === 'string') {
        this.state.focusTarget = message.focusTarget;
      }
      if (
        typeof message.generation === 'number' &&
        Number.isSafeInteger(message.generation) &&
        message.generation >= 0
      ) {
        this.state.generation = message.generation;
      }
    }

    for (const handler of this.displayHandlers) {
      try {
        handler(message);
      } catch {
        this.fail(new BrowserEndpointError('protocol-error', 'display handler failed'));
      }
    }
  }

  private handleClose(error?: BrowserEndpointError): void {
    this.detach();
    this.connection = null;
    this.registered = false;
    if (this.status === 'failed') return;
    this.lastError = error ?? null;
    this.setStatus('disconnected');
    if (error) this.emitError(error);
  }

  private fail(error: BrowserEndpointError): void {
    const connection = this.connection;
    this.detach();
    this.connection = null;
    this.registered = false;
    this.lastError = error;
    this.setStatus('failed');
    this.emitError(error);
    if (connection) {
      try {
        connection.close(1008, error.code);
      } catch {
        this.lastError = error;
      }
    }
  }

  private detach(): void {
    for (const unsubscribe of this.unsubscribers) unsubscribe();
    this.unsubscribers = [];
  }

  private emitStatus(status: BrowserEndpointStatus): void {
    for (const handler of this.statusHandlers) {
      try {
        handler(status);
      } catch {
        this.lastError = new BrowserEndpointError('protocol-error', 'status handler failed');
      }
    }
  }

  private emitError(error: BrowserEndpointError): void {
    for (const handler of this.errorHandlers) {
      try {
        handler(error);
      } catch {
        this.lastError = error;
      }
    }
  }

  private setStatus(status: BrowserEndpointStatus): void {
    if (this.status === status) return;
    this.status = status;
    this.emitStatus(status);
  }
}
