import type { AdPairLiveSession } from './pairing-live';

export interface PairingWireTransport {
  send(data: Uint8Array): void;
  onMessage(handler: (data: Uint8Array) => void): () => void;
}

interface BinaryEventTarget {
  binaryType?: string;
  addEventListener(type: 'message', listener: (event: { data: unknown }) => void): void;
  removeEventListener(type: 'message', listener: (event: { data: unknown }) => void): void;
}

export interface WebSocketLike extends BinaryEventTarget {
  readyState: number;
  send(data: ArrayBuffer | ArrayBufferView): void;
}

export interface RtcDataChannelLike extends BinaryEventTarget {
  readyState: string;
  send(data: ArrayBuffer | ArrayBufferView): void;
}

function binaryBytes(data: unknown): Uint8Array {
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (ArrayBuffer.isView(data)) {
    return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  }
  throw new Error('pairing transport requires binary messages');
}

function eventTransport(
  target: BinaryEventTarget,
  send: (data: Uint8Array) => void
): PairingWireTransport {
  target.binaryType = 'arraybuffer';
  return {
    send,
    onMessage(handler: (data: Uint8Array) => void): () => void {
      const listener = (event: { data: unknown }): void => {
        let bytes: Uint8Array;
        try {
          bytes = binaryBytes(event.data);
        } catch {
          return;
        }
        handler(bytes);
      };
      target.addEventListener('message', listener);
      return () => target.removeEventListener('message', listener);
    }
  };
}

export function webSocketPairingTransport(socket: WebSocketLike): PairingWireTransport {
  return eventTransport(socket, (data) => {
    if (socket.readyState !== 1) throw new Error('pairing WebSocket is not open');
    socket.send(data);
  });
}

export function rtcDataChannelPairingTransport(
  channel: RtcDataChannelLike
): PairingWireTransport {
  return eventTransport(channel, (data) => {
    if (channel.readyState !== 'open') throw new Error('pairing data channel is not open');
    channel.send(data);
  });
}

export function attachPairingSession(
  session: Pick<AdPairLiveSession, 'receive'>,
  transport: PairingWireTransport,
  onError?: (error: unknown) => void
): () => void {
  return transport.onMessage((data) => {
    void (async () => {
      try {
        const outbound = await session.receive(data);
        for (const message of outbound) transport.send(message);
      } catch (error) {
        onError?.(error);
      }
    })();
  });
}
