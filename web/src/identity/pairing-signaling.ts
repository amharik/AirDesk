import {
  decodePairingLinkSignal,
  encodePairingLinkSignal,
  type PairingLinkSignal,
  type RtcPairingLink
} from './pairing-webrtc';

export interface PairingSignalTransport {
  send(signal: string): void;
  onSignal(handler: (signal: string) => void): () => void;
}

export type PairingSignalErrorCode = 'not-open' | 'duplicate-signal';

export class PairingSignalError extends Error {
  readonly code: PairingSignalErrorCode;

  constructor(code: PairingSignalErrorCode, message: string) {
    super(`${code}: ${message}`);
    this.name = 'PairingSignalError';
    this.code = code;
  }
}

interface TextEventTarget {
  addEventListener(type: 'message', listener: (event: { data: unknown }) => void): void;
  removeEventListener(type: 'message', listener: (event: { data: unknown }) => void): void;
}

export interface WebSocketTextLike extends TextEventTarget {
  readyState: number;
  send(data: string): void;
}

export function webSocketPairingSignalTransport(
  socket: WebSocketTextLike
): PairingSignalTransport {
  return {
    send(signal: string): void {
      if (socket.readyState !== 1) {
        throw new PairingSignalError('not-open', 'pairing signaling WebSocket is not open');
      }
      socket.send(signal);
    },
    onSignal(handler: (signal: string) => void): () => void {
      const listener = (event: { data: unknown }): void => {
        if (typeof event.data === 'string') handler(event.data);
      };
      socket.addEventListener('message', listener);
      return () => socket.removeEventListener('message', listener);
    }
  };
}

export function sendPairingLinkSignal(
  transport: PairingSignalTransport,
  signal: PairingLinkSignal
): void {
  transport.send(encodePairingLinkSignal(signal));
}

export function attachRtcPairingLink(
  link: RtcPairingLink,
  transport: PairingSignalTransport,
  onError?: (error: unknown) => void
): () => void {
  const seen = new Set<string>();
  return transport.onSignal((raw) => {
    let signal: PairingLinkSignal;
    try {
      signal = decodePairingLinkSignal(raw);
    } catch (error) {
      onError?.(error);
      return;
    }
    if (seen.has(raw)) {
      onError?.(new PairingSignalError('duplicate-signal', 'pairing signal was already received'));
      return;
    }
    seen.add(raw);
    void link.handleSignal(signal).catch((error) => onError?.(error));
  });
}
