import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { ADFPHeader } from '../src/protocol';
import {
  ADFPError,
  ADFPErrorException,
  ADFP_MAX_ENVELOPE_BYTES,
  ControlType,
  EventType,
  SenderRole,
  assertADFPEnvelopeSize,
  decodeControl,
  decodeInput,
  encodeControl,
  encodeInput,
  hasADFPIdentifier
} from '../src/protocol';

interface FixtureCase {
  name: string;
  channel: string;
  payloadType: 'InputEvent' | 'ControlMessage';
  payload: Record<string, unknown>;
  hex: string;
}

interface Fixture {
  fileIdentifier: string;
  version: number;
  maxEnvelopeBytes: number;
  nowEpochMillis: string;
  header: {
    messageId: string;
    senderDeviceId: string;
    senderRole: number;
    correlationId: string;
    idempotencyKey: string;
    expiresAt: string;
    cancellationId: string;
  };
  cases: FixtureCase[];
  invalid: Array<{ name: string; hex: string; expectedError: string }>;
}

const fixture = JSON.parse(
  readFileSync(
    join(process.cwd(), '..', 'protocol', 'fixtures', 'adfp', 'envelope-v1.json'),
    'utf8'
  )
) as Fixture;

function bytesFromHex(value: string): Uint8Array {
  return Uint8Array.from(Buffer.from(value, 'hex'));
}

function hexFromBytes(value: Uint8Array): string {
  return Buffer.from(value).toString('hex');
}

function header(): ADFPHeader {
  return {
    ...fixture.header,
    senderRole: fixture.header.senderRole as SenderRole,
    expiresAt: BigInt(fixture.header.expiresAt)
  };
}

describe('ADFP envelope v1', () => {
  it('matches the shared input fixture', () => {
    const item = fixture.cases.find((entry) => entry.name === 'input-key-down')!;
    const decoded = decodeInput(bytesFromHex(item.hex), BigInt(fixture.nowEpochMillis));

    expect(decoded).toMatchObject({
      type: EventType.key_down,
      sessionId: 'session-1',
      generation: 7,
      seq: 42,
      timestamp: 1700000000123n,
      key: 'a',
      code: 'KeyA',
      modifiers: ['Shift'],
      target: 'window-1',
      header: {
        messageId: 'message-1',
        senderDeviceId: 'device-controller-1',
        senderRole: SenderRole.controller,
        expiresAt: 4102444800000n
      }
    });

    expect(hexFromBytes(encodeInput(decoded, header()))).toBe(item.hex);
  });

  it('matches the shared control fixture', () => {
    const item = fixture.cases.find((entry) => entry.name === 'control-notice')!;
    const decoded = decodeControl(bytesFromHex(item.hex), BigInt(fixture.nowEpochMillis));

    expect(decoded).toMatchObject({
      type: ControlType.notice,
      sessionId: 'session-1',
      generation: 7,
      seq: 43,
      timestamp: 1700000000124n,
      message: 'connected',
      action: 'focus',
      header: {
        messageId: 'message-1',
        senderDeviceId: 'device-controller-1'
      }
    });

    expect(hexFromBytes(encodeControl(decoded, header()))).toBe(item.hex);
  });

  it('rejects invalid fixtures and expired headers', () => {
    for (const invalid of fixture.invalid) {
      expect(() => decodeInput(bytesFromHex(invalid.hex))).toThrow();
    }

    const item = fixture.cases.find((entry) => entry.name === 'input-key-down')!;
    expect(() =>
      decodeInput(bytesFromHex(item.hex), BigInt(fixture.header.expiresAt))
    ).toThrow(ADFPErrorException);

    expect(() => assertADFPEnvelopeSize(new Uint8Array(ADFP_MAX_ENVELOPE_BYTES + 1))).toThrow(
      ADFPErrorException
    );
  });

  it('keeps envelopes without a header decodable for legacy callers', () => {
    const decoded = decodeInput(
      encodeInput({
        type: EventType.pointer_cancel,
        sessionId: 'session-1',
        timestamp: 1700000000123n
      })
    );
    expect(decoded.header).toBeNull();
  });

  it('rejects invalid header fields', () => {
    const payload = {
      type: EventType.pointer_cancel,
      sessionId: 'session-1',
      timestamp: 1700000000123n
    };
    expect(() =>
      encodeInput(payload, { ...header(), senderRole: SenderRole.unspecified })
    ).toThrow(ADFPErrorException);
    expect(() => encodeInput(payload, { ...header(), messageId: '' })).toThrow(
      ADFPErrorException
    );
    expect(() =>
      encodeInput(payload, { ...header(), expiresAt: 1n })
    ).toThrow(ADFPErrorException);
  });

  it('detects the ADFP file identifier', () => {
    const item = fixture.cases[0]!;
    expect(hasADFPIdentifier(bytesFromHex(item.hex))).toBe(true);
    expect(hasADFPIdentifier(new TextEncoder().encode('not-adfp'))).toBe(false);
    expect(ADFPError.wrongFileIdentifier).toBe('wrong-file-identifier');
  });
});
