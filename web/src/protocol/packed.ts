import { EventType } from './generated/air-desk/protocol/event-type';

export const PACKED_VERSION = 1;
export const PACKED_HEADER_BYTES = 32;
export const PACKED_POINTER_BYTES = 44;
export const PACKED_SCROLL_BYTES = 40;

export const PACKED_EVENT_TYPES = [
  EventType.pointer_move,
  EventType.pointer_down,
  EventType.pointer_up,
  EventType.pointer_click,
  EventType.pointer_cancel,
  EventType.scroll
] as const;

export type PackedEventType = (typeof PACKED_EVENT_TYPES)[number];

export interface PackedFrame {
  kind: PackedEventType;
  generation: number;
  seq: number;
  timestamp: bigint;
  sessionTag: bigint;
  x?: number;
  y?: number;
  button?: number;
  clickCount?: number;
  dx?: number;
  dy?: number;
}

export class PackedProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PackedProtocolError';
  }
}

const FNV_OFFSET = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const MAGIC_A = 0x41;
const MAGIC_D = 0x44;

export function sessionTag(sessionId: string): bigint {
  const bytes = new TextEncoder().encode(sessionId);
  if (bytes.length === 0 || bytes.length > 64) {
    throw new PackedProtocolError('invalid session id');
  }
  let hash = FNV_OFFSET;
  for (const byte of bytes) {
    hash = BigInt.asUintN(64, (hash ^ BigInt(byte)) * FNV_PRIME);
  }
  return hash;
}

function isPackedKind(value: number): value is PackedEventType {
  return (PACKED_EVENT_TYPES as readonly number[]).includes(value);
}

function isPointerKind(kind: PackedEventType): boolean {
  return (
    kind === EventType.pointer_move ||
    kind === EventType.pointer_down ||
    kind === EventType.pointer_up ||
    kind === EventType.pointer_click
  );
}

function requireFinite(value: number | undefined, name: string): number {
  if (value === undefined || !Number.isFinite(value)) {
    throw new PackedProtocolError(`${name} must be finite`);
  }
  return value;
}

function requireInteger(value: number | undefined, name: string, min: number, max: number): number {
  if (value === undefined || !Number.isInteger(value) || value < min || value > max) {
    throw new PackedProtocolError(`${name} must be an integer in ${min}...${max}`);
  }
  return value;
}

export function encodePacked(frame: PackedFrame): Uint8Array {
  if (!isPackedKind(frame.kind)) throw new PackedProtocolError('unsupported packed event type');
  if (!Number.isInteger(frame.generation) || frame.generation < 0 || frame.generation > 0xffffffff) {
    throw new PackedProtocolError('generation must be a uint32');
  }
  if (!Number.isInteger(frame.seq) || frame.seq < 0 || frame.seq > 0xffffffff) {
    throw new PackedProtocolError('seq must be a uint32');
  }
  if (frame.timestamp <= 0n || frame.timestamp > 0xffffffffffffffffn) {
    throw new PackedProtocolError('timestamp must be a positive uint64');
  }
  if (frame.sessionTag < 0n || frame.sessionTag > 0xffffffffffffffffn) {
    throw new PackedProtocolError('sessionTag must be a uint64');
  }

  const length = isPointerKind(frame.kind)
    ? PACKED_POINTER_BYTES
    : frame.kind === EventType.scroll
      ? PACKED_SCROLL_BYTES
      : PACKED_HEADER_BYTES;
  const buffer = new ArrayBuffer(length);
  const view = new DataView(buffer);

  view.setUint8(0, MAGIC_A);
  view.setUint8(1, MAGIC_D);
  view.setUint8(2, PACKED_VERSION);
  view.setUint8(3, frame.kind);
  view.setUint8(4, 0);
  view.setUint8(5, 0);
  view.setUint8(6, 0);
  view.setUint8(7, 0);
  view.setUint32(8, frame.generation, true);
  view.setUint32(12, frame.seq, true);
  view.setBigUint64(16, frame.timestamp, true);
  view.setBigUint64(24, frame.sessionTag, true);

  if (isPointerKind(frame.kind)) {
    const x = requireFinite(frame.x, 'x');
    const y = requireFinite(frame.y, 'y');
    if (x < 0 || x > 1 || y < 0 || y > 1) {
      throw new PackedProtocolError('pointer coordinates must be normalized');
    }
    view.setFloat32(32, x, true);
    view.setFloat32(36, y, true);
    view.setUint8(40, requireInteger(frame.button, 'button', 0, 4));
    view.setUint8(41, requireInteger(frame.clickCount, 'clickCount', 1, 3));
    view.setUint16(42, 0, true);
  } else if (frame.kind === EventType.scroll) {
    const dx = requireFinite(frame.dx, 'dx');
    const dy = requireFinite(frame.dy, 'dy');
    if (Math.abs(dx) > 20_000 || Math.abs(dy) > 20_000) {
      throw new PackedProtocolError('scroll delta is too large');
    }
    view.setFloat32(32, dx, true);
    view.setFloat32(36, dy, true);
  }

  return new Uint8Array(buffer);
}

export function decodePacked(bytes: Uint8Array): PackedFrame {
  if (bytes.length < PACKED_HEADER_BYTES) throw new PackedProtocolError('frame is too short');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint8(0) !== MAGIC_A || view.getUint8(1) !== MAGIC_D) {
    throw new PackedProtocolError('invalid magic');
  }
  if (view.getUint8(2) !== PACKED_VERSION) throw new PackedProtocolError('unsupported version');
  if (view.getUint8(4) !== 0 || view.getUint8(5) !== 0 || view.getUint8(6) !== 0 || view.getUint8(7) !== 0) {
    throw new PackedProtocolError('unsupported flags');
  }

  const kind = view.getUint8(3);
  if (!isPackedKind(kind)) throw new PackedProtocolError('unsupported packed event type');

  const frame: PackedFrame = {
    kind,
    generation: view.getUint32(8, true),
    seq: view.getUint32(12, true),
    timestamp: view.getBigUint64(16, true),
    sessionTag: view.getBigUint64(24, true)
  };

  if (frame.timestamp === 0n) throw new PackedProtocolError('timestamp must be positive');

  if (isPointerKind(kind)) {
    if (bytes.length !== PACKED_POINTER_BYTES) throw new PackedProtocolError('invalid pointer frame length');
    frame.x = view.getFloat32(32, true);
    frame.y = view.getFloat32(36, true);
    frame.button = view.getUint8(40);
    frame.clickCount = view.getUint8(41);
    if (!Number.isFinite(frame.x) || !Number.isFinite(frame.y) || frame.x < 0 || frame.x > 1 || frame.y < 0 || frame.y > 1) {
      throw new PackedProtocolError('invalid pointer coordinates');
    }
    if (frame.button > 4) throw new PackedProtocolError('invalid button');
    if (frame.clickCount < 1 || frame.clickCount > 3) throw new PackedProtocolError('invalid click count');
    if (view.getUint16(42, true) !== 0) throw new PackedProtocolError('invalid pointer reserved bytes');
  } else if (kind === EventType.scroll) {
    if (bytes.length !== PACKED_SCROLL_BYTES) throw new PackedProtocolError('invalid scroll frame length');
    frame.dx = view.getFloat32(32, true);
    frame.dy = view.getFloat32(36, true);
    if (!Number.isFinite(frame.dx) || !Number.isFinite(frame.dy) || Math.abs(frame.dx) > 20_000 || Math.abs(frame.dy) > 20_000) {
      throw new PackedProtocolError('invalid scroll delta');
    }
  } else if (bytes.length !== PACKED_HEADER_BYTES) {
    throw new PackedProtocolError('invalid cancel frame length');
  }

  return frame;
}
