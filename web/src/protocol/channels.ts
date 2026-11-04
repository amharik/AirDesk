import { EventType } from './generated/air-desk/protocol/event-type';
import { MOVEMENT_BYTES, MOVEMENT_MAGIC } from './movement';

export enum InputChannel {
  control = 'control',
  reliableEdges = 'reliable-edges',
  movement = 'movement',
  runtime = 'runtime',
  resource = 'resource'
}

export type ClassifiedInputFrame = 'packed-movement' | 'flatbuffer-envelope';

export class InputChannelError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InputChannelError';
  }
}

export function routeInput(type: EventType): InputChannel {
  switch (type) {
    case EventType.pointer_move:
      return InputChannel.movement;
    case EventType.pointer_down:
    case EventType.pointer_up:
    case EventType.pointer_click:
    case EventType.pointer_cancel:
    case EventType.scroll:
    case EventType.key_down:
    case EventType.key_up:
    case EventType.text_input:
    case EventType.focus_changed:
      return InputChannel.reliableEdges;
    case EventType.viewport_changed:
      return InputChannel.control;
  }
}

export function validateInputOnChannel(type: EventType, channel: InputChannel): void {
  const expected = routeInput(type);
  if (expected === channel) return;
  if (channel === InputChannel.movement) {
    throw new InputChannelError('input edges cannot be sent on the movement channel');
  }
  if (expected === InputChannel.movement) {
    throw new InputChannelError('packed movement frames can only be sent on the movement channel');
  }
  throw new InputChannelError(`input was routed to ${channel}; expected ${expected}`);
}

export function isFlatBufferEnvelope(bytes: Uint8Array): boolean {
  if (bytes.length < 8) return false;
  if (bytes[4] !== 0x41 || bytes[5] !== 0x44 || bytes[6] !== 0x45 || bytes[7] !== 0x4e) {
    return false;
  }
  const root = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, true);
  return root >= 8 && root + 4 <= bytes.length;
}

export function classifyInputFrame(
  bytes: Uint8Array,
  channel: InputChannel,
  packedNegotiated = true
): ClassifiedInputFrame {
  if (channel === InputChannel.movement) {
    if (!packedNegotiated) {
      throw new InputChannelError('packed movement format was not negotiated');
    }
    if (bytes.length !== MOVEMENT_BYTES || bytes[0] !== MOVEMENT_MAGIC) {
      throw new InputChannelError('movement channel received a non-movement frame');
    }
    return 'packed-movement';
  }

  if (!isFlatBufferEnvelope(bytes)) {
    if (bytes[0] === MOVEMENT_MAGIC) {
      throw new InputChannelError('packed movement frame received on a reliable channel');
    }
    throw new InputChannelError('reliable channel received an unknown frame');
  }
  return 'flatbuffer-envelope';
}
