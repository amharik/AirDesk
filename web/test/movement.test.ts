import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  MOVEMENT_BYTES,
  MOVEMENT_MAGIC,
  MOVEMENT_MODIFIER_SHIFT,
  PackedMovementError,
  decodePackedMovement,
  encodePackedMovement
} from '../src/protocol/movement';

const fixture = JSON.parse(
  readFileSync(join(process.cwd(), '..', 'protocol', 'fixtures', 'movement-v12.json'), 'utf8')
)[0] as {
  name: string;
  hex: string;
  expected: {
    leaseEpochLow: number;
    seq: number;
    x: number;
    y: number;
    buttonMask: number;
    modifiers: string[];
  };
};

function bytesFromHex(hex: string): Uint8Array {
  return Uint8Array.from(Buffer.from(hex, 'hex'));
}

function hexFromBytes(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('hex');
}

describe('packed movement frames', () => {
  it('matches the shared cross-language fixture', () => {
    const frame = decodePackedMovement(bytesFromHex(fixture.hex));
    expect(frame).toEqual({
      leaseEpochLow: fixture.expected.leaseEpochLow,
      seq: fixture.expected.seq,
      x: fixture.expected.x,
      y: fixture.expected.y,
      buttonMask: fixture.expected.buttonMask,
      modifiers: MOVEMENT_MODIFIER_SHIFT
    });
  });

  it('encodes the fixture byte-for-byte', () => {
    const encoded = encodePackedMovement(decodePackedMovement(bytesFromHex(fixture.hex)));
    expect(hexFromBytes(encoded)).toBe(fixture.hex);
    expect(encoded[0]).toBe(MOVEMENT_MAGIC);
    expect(encoded.length).toBe(MOVEMENT_BYTES);
  });

  it('rejects malformed and edge-bearing frames', () => {
    expect(() => decodePackedMovement(new Uint8Array(MOVEMENT_BYTES))).toThrow(PackedMovementError);

    const edge = bytesFromHex(fixture.hex);
    edge[1] = 0b01;
    expect(() => decodePackedMovement(edge)).toThrow(PackedMovementError);

    const coordinates = bytesFromHex(fixture.hex);
    new DataView(coordinates.buffer).setFloat32(8, 2, true);
    expect(() => decodePackedMovement(coordinates)).toThrow(PackedMovementError);

    expect(() =>
      encodePackedMovement({ leaseEpochLow: 1, seq: 1, x: 0.5, y: 0.5, buttonMask: 8, modifiers: 0 })
    ).toThrow(PackedMovementError);
  });
});
