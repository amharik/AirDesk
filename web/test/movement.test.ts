import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  MOVEMENT_BYTES,
  MOVEMENT_MAGIC,
  MOVEMENT_MODIFIER_SHIFT,
  ONE_EURO_POINTER_PARAMETERS,
  OneEuroFilter,
  OneEuroFilterError,
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

const oneEuroFixture = JSON.parse(
  readFileSync(join(process.cwd(), '..', 'protocol', 'fixtures', 'input', 'one-euro-v1.json'), 'utf8')
) as {
  version: number;
  name: string;
  parameters: { min_cutoff: number; beta: number; d_cutoff: number };
  cases: Array<{
    name: string;
    samples: Array<{ t: number; x: number; y: number }>;
    expected: Array<{ t: number; x: number; y: number }>;
  }>;
};

describe('one-euro pointer filter', () => {
  it('matches the shared cross-language fixture', () => {
    expect(oneEuroFixture.version).toBe(1);
    expect(oneEuroFixture.name).toBe('one-euro-v1');
    expect(oneEuroFixture.parameters).toEqual({
      min_cutoff: ONE_EURO_POINTER_PARAMETERS.minCutoff,
      beta: ONE_EURO_POINTER_PARAMETERS.beta,
      d_cutoff: ONE_EURO_POINTER_PARAMETERS.dCutoff
    });

    for (const testCase of oneEuroFixture.cases) {
      const filter = new OneEuroFilter({
        minCutoff: oneEuroFixture.parameters.min_cutoff,
        beta: oneEuroFixture.parameters.beta,
        dCutoff: oneEuroFixture.parameters.d_cutoff
      });
      testCase.samples.forEach((sample, index) => {
        const output = filter.filter(sample.x, sample.y, sample.t);
        const expected = testCase.expected[index]!;
        expect(output.x).toBeCloseTo(expected.x, 12);
        expect(output.y).toBeCloseTo(expected.y, 12);
      });
    }
  });

  it('tracks high-speed movement without material phase lag', () => {
    const testCase = oneEuroFixture.cases.find((candidate) => candidate.name === 'high-speed-tracking')!;
    const filter = new OneEuroFilter();
    const errors = testCase.samples.map((sample) => {
      const output = filter.filter(sample.x, sample.y, sample.t);
      return Math.hypot(output.x - sample.x, output.y - sample.y);
    });
    const warmup = errors.slice(10);
    expect(Math.max(...warmup)).toBeLessThan(0.005);
    expect(errors[errors.length - 1]!).toBeLessThan(0.003);
  });

  it('attenuates low-speed jitter', () => {
    const testCase = oneEuroFixture.cases.find((candidate) => candidate.name === 'low-speed-jitter')!;
    const filter = new OneEuroFilter();
    const outputs = testCase.samples.map((sample) => filter.filter(sample.x, sample.y, sample.t));
    const filteredRange = Math.max(...outputs.slice(10).map((point) => point.x))
      - Math.min(...outputs.slice(10).map((point) => point.x));
    const rawRange = Math.max(...testCase.samples.slice(10).map((sample) => sample.x))
      - Math.min(...testCase.samples.slice(10).map((sample) => sample.x));
    expect(filteredRange).toBeLessThan(rawRange * 0.2);
  });

  it('rejects invalid parameters and non-finite input', () => {
    expect(() => new OneEuroFilter({ minCutoff: 0, beta: 1, dCutoff: 1 })).toThrow(OneEuroFilterError);
    expect(() => new OneEuroFilter({ minCutoff: 1, beta: -1, dCutoff: 1 })).toThrow(OneEuroFilterError);
    expect(() => new OneEuroFilter({ minCutoff: 1, beta: 1, dCutoff: 0 })).toThrow(OneEuroFilterError);
    const filter = new OneEuroFilter();
    expect(() => filter.filter(Number.NaN, 0.5, 0)).toThrow(OneEuroFilterError);
  });

  it('restarts at the next sample after reset', () => {
    const filter = new OneEuroFilter();
    filter.filter(0.2, 0.3, 0);
    filter.filter(0.8, 0.7, 1 / 120);
    filter.reset();
    expect(filter.filter(0.6, 0.4, 2 / 120)).toEqual({ x: 0.6, y: 0.4 });
  });
});
