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
      if (socket.readyState !== 1) throw new Error('pairing signaling WebSocket is not open');
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
  return transport.onSignal((raw) => {
    let signal: PairingLinkSignal;
    try {
      signal = decodePairingLinkSignal(raw);
    } catch (error) {
      onError?.(error);
      return;
    }
    void link.handleSignal(signal).catch((error) => onError?.(error));
  });
}
