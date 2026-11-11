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

export interface OneEuroParameters {
  minCutoff: number;
  beta: number;
  dCutoff: number;
}

export const ONE_EURO_POINTER_PARAMETERS: Readonly<OneEuroParameters> = Object.freeze({
  minCutoff: 1.0,
  beta: 160.0,
  dCutoff: 1.0
});

export const ONE_EURO_MINIMUM_DELTA_TIME = 1 / 240;

export class OneEuroFilterError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OneEuroFilterError';
  }
}

export interface FilteredPoint {
  x: number;
  y: number;
}

class OneEuroAxis {
  private previous = 0;
  private filtered = 0;
  private derivative = 0;

  reset(): void {
    this.previous = 0;
    this.filtered = 0;
    this.derivative = 0;
  }

  seed(value: number): void {
    this.previous = value;
    this.filtered = value;
    this.derivative = 0;
  }

  filter(value: number, deltaTime: number, parameters: OneEuroParameters): number {
    const rawDerivative = (value - this.previous) / deltaTime;
    const derivativeAlpha = axisAlpha(parameters.dCutoff, deltaTime);
    this.derivative = lowPass(rawDerivative, this.derivative, derivativeAlpha);
    const cutoff = parameters.minCutoff + parameters.beta * Math.abs(this.derivative);
    const valueAlpha = axisAlpha(cutoff, deltaTime);
    const output = lowPass(value, this.filtered, valueAlpha);
    this.previous = value;
    this.filtered = output;
    return output;
  }
}

function axisAlpha(cutoff: number, deltaTime: number): number {
  if (!Number.isFinite(cutoff) || cutoff <= 0 || !Number.isFinite(deltaTime) || deltaTime <= 0) {
    return 1;
  }
  const timeConstant = 1 / (2 * Math.PI * cutoff);
  return 1 / (1 + timeConstant / deltaTime);
}

function lowPass(input: number, previous: number, alpha: number): number {
  return alpha * input + (1 - alpha) * previous;
}

export class OneEuroFilter {
  readonly parameters: OneEuroParameters;
  private readonly xAxis = new OneEuroAxis();
  private readonly yAxis = new OneEuroAxis();
  private lastTimestamp: number | undefined;

  constructor(parameters: OneEuroParameters = ONE_EURO_POINTER_PARAMETERS) {
    if (
      !Number.isFinite(parameters.minCutoff) ||
      parameters.minCutoff <= 0 ||
      !Number.isFinite(parameters.beta) ||
      parameters.beta < 0 ||
      !Number.isFinite(parameters.dCutoff) ||
      parameters.dCutoff <= 0
    ) {
      throw new OneEuroFilterError('invalid one-euro filter parameters');
    }
    this.parameters = { ...parameters };
  }

  reset(): void {
    this.xAxis.reset();
    this.yAxis.reset();
    this.lastTimestamp = undefined;
  }

  filter(x: number, y: number, timestamp: number): FilteredPoint {
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(timestamp)) {
      throw new OneEuroFilterError('filter input must be finite');
    }
    if (this.lastTimestamp === undefined) {
      this.xAxis.seed(x);
      this.yAxis.seed(y);
      this.lastTimestamp = timestamp;
      return { x, y };
    }
    const deltaTime = Math.max(timestamp - this.lastTimestamp, ONE_EURO_MINIMUM_DELTA_TIME);
    this.lastTimestamp = timestamp;
    return {
      x: this.xAxis.filter(x, deltaTime, this.parameters),
      y: this.yAxis.filter(y, deltaTime, this.parameters)
    };
  }
}
