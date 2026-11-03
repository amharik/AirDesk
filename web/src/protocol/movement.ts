export const MOVEMENT_MAGIC = 0xa5;
export const MOVEMENT_BYTES = 16;
export const MOVEMENT_MODIFIER_SHIFT = 1 << 0;
export const MOVEMENT_MODIFIER_OPTION = 1 << 1;
export const MOVEMENT_MODIFIER_COMMAND = 1 << 2;

export interface PackedMovement {
  leaseEpochLow: number;
  seq: number;
  x: number;
  y: number;
  buttonMask: number;
  modifiers: number;
}

export class PackedMovementError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PackedMovementError';
  }
}

function requireFinite(value: number, name: string): number {
  if (!Number.isFinite(value)) {
    throw new PackedMovementError(`${name} must be finite`);
  }
  return value;
}

function requireInteger(value: number, name: string, min: number, max: number): number {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new PackedMovementError(`${name} must be an integer in ${min}...${max}`);
  }
  return value;
}

export function encodePackedMovement(frame: PackedMovement): Uint8Array {
  const leaseEpochLow = requireInteger(frame.leaseEpochLow, 'leaseEpochLow', 0, 0xffff);
  const seq = requireInteger(frame.seq, 'seq', 0, 0xffffffff);
  const x = requireFinite(frame.x, 'x');
  const y = requireFinite(frame.y, 'y');
  if (x < 0 || x > 1 || y < 0 || y > 1) {
    throw new PackedMovementError('movement coordinates must be normalized');
  }
  const buttonMask = requireInteger(frame.buttonMask, 'buttonMask', 0, 0b111);
  const modifiers = requireInteger(frame.modifiers, 'modifiers', 0, 0b111);

  const buffer = new ArrayBuffer(MOVEMENT_BYTES);
  const view = new DataView(buffer);
  view.setUint8(0, MOVEMENT_MAGIC);
  view.setUint8(1, (buttonMask << 2) | (modifiers << 5));
  view.setUint16(2, leaseEpochLow, true);
  view.setUint32(4, seq, true);
  view.setFloat32(8, x, true);
  view.setFloat32(12, y, true);
  return new Uint8Array(buffer);
}

export function decodePackedMovement(bytes: Uint8Array): PackedMovement {
  if (bytes.length !== MOVEMENT_BYTES) {
    throw new PackedMovementError('movement frame must be exactly 16 bytes');
  }
  if (bytes[0] !== MOVEMENT_MAGIC) {
    throw new PackedMovementError('invalid movement magic');
  }

  const flags = bytes[1]!;
  if ((flags & 0b11) !== 0) {
    throw new PackedMovementError('movement frames cannot carry input edges');
  }

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const x = view.getFloat32(8, true);
  const y = view.getFloat32(12, true);
  if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
    throw new PackedMovementError('invalid movement coordinates');
  }

  return {
    leaseEpochLow: view.getUint16(2, true),
    seq: view.getUint32(4, true),
    x,
    y,
    buttonMask: (flags >> 2) & 0b111,
    modifiers: (flags >> 5) & 0b111
  };
}
