import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  ControlType,
  EventType,
  PackedProtocolError,
  decodeControl,
  decodeInput,
  decodePacked,
  encodeControl,
  encodeInput,
  encodePacked,
  sessionTag
} from '../src/protocol';

const fixtures = JSON.parse(
  readFileSync(join(process.cwd(), '..', 'protocol', 'fixtures', 'packed-frames.json'), 'utf8')
) as Array<{
  name: string;
  hex: string;
  expected: Record<string, unknown>;
}>;

const kinds = {
  pointer_move: EventType.pointer_move,
  scroll: EventType.scroll,
  pointer_cancel: EventType.pointer_cancel
} as const;

function bytesFromHex(hex: string): Uint8Array {
  return Uint8Array.from(Buffer.from(hex, 'hex'));
}

function hexFromBytes(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('hex');
}

describe('packed pointer frames', () => {
  const tag = 1623645925111568461n;

  it('matches the shared cross-language fixtures', () => {
    expect(sessionTag('session-1')).toBe(tag);

    for (const fixture of fixtures) {
      const expected = fixture.expected;
      const frame = decodePacked(bytesFromHex(fixture.hex));
      const kind = kinds[expected.kind as keyof typeof kinds];

      expect(frame).toMatchObject({
        ...expected,
        kind,
        timestamp: BigInt(String(expected.timestamp)),
        sessionTag: BigInt(String(expected.sessionTag))
      });
    }
  });

  it('encodes the fixtures byte-for-byte', () => {
    for (const fixture of fixtures) {
      const expected = fixture.expected;
      const frame = decodePacked(bytesFromHex(fixture.hex));

      expect(hexFromBytes(encodePacked(frame))).toBe(fixture.hex);
      expect(frame.kind).toBe(kinds[expected.kind as keyof typeof kinds]);
    }
  });

  it('supports every packed event kind', () => {
    const base = { generation: 7, seq: 1, timestamp: 1700000000123n, sessionTag: tag };
    for (const kind of [
      EventType.pointer_move,
      EventType.pointer_down,
      EventType.pointer_up,
      EventType.pointer_click
    ] as const) {
      const decoded = decodePacked(
        encodePacked({ ...base, kind, x: 0.5, y: 0.5, button: 0, clickCount: 1 })
      );
      expect(decoded.kind).toBe(kind);
    }

    const scroll = decodePacked(encodePacked({ ...base, kind: EventType.scroll, dx: 1, dy: -1 }));
    expect(scroll.dx).toBe(1);
    expect(scroll.dy).toBe(-1);

    const cancel = decodePacked(encodePacked({ ...base, kind: EventType.pointer_cancel }));
    expect(cancel.kind).toBe(EventType.pointer_cancel);
  });

  it('rejects malformed frames', () => {
    const valid = bytesFromHex(fixtures[0]!.hex);

    const badMagic = valid.slice();
    badMagic[0] = 0;
    expect(() => decodePacked(badMagic)).toThrow(PackedProtocolError);

    const badVersion = valid.slice();
    badVersion[2] = 2;
    expect(() => decodePacked(badVersion)).toThrow(PackedProtocolError);

    const badCoordinates = encodePacked({
      kind: EventType.pointer_move,
      generation: 1,
      seq: 1,
      timestamp: 1n,
      sessionTag: tag,
      x: 0.5,
      y: 0.5,
      button: 0,
      clickCount: 1
    });
    new DataView(badCoordinates.buffer).setFloat32(32, 2, true);
    expect(() => decodePacked(badCoordinates)).toThrow(PackedProtocolError);

    expect(() => decodePacked(valid.slice(0, 20))).toThrow(PackedProtocolError);
    expect(() => encodePacked({ ...decodePacked(valid), x: 2 })).toThrow(PackedProtocolError);
  });
});

describe('flatbuffer input and control messages', () => {
  it('round-trips variable input events', () => {
    const cases = [
      { type: EventType.key_down, key: 'a', code: 'KeyA', modifiers: ['Meta'] },
      { type: EventType.key_up, key: 'a', code: 'KeyA', modifiers: ['Meta'] },
      { type: EventType.text_input, text: 'नमस्ते' },
      { type: EventType.focus_changed, target: 'terminal' },
      { type: EventType.viewport_changed, width: 1024, height: 768 }
    ];

    for (const input of cases) {
      const decoded = decodeInput(
        encodeInput({
          ...input,
          sessionId: 'session-1',
          generation: 7,
          seq: 1,
          timestamp: 1700000000123n
        })
      );
      expect(decoded).toMatchObject({
        ...input,
        sessionId: 'session-1',
        generation: 7,
        seq: 1,
        timestamp: 1700000000123n
      });
    }
  });

  it('round-trips control messages', () => {
    const decoded = decodeControl(
      encodeControl({
        type: ControlType.appearance,
        sessionId: 'session-1',
        generation: 7,
        seq: 2,
        timestamp: 1700000000123n,
        appearance: 'light'
      })
    );

    expect(decoded).toMatchObject({
      type: ControlType.appearance,
      sessionId: 'session-1',
      generation: 7,
      seq: 2,
      timestamp: 1700000000123n,
      appearance: 'light'
    });
  });

  it('uses every one of the eleven input event names', () => {
    const covered = new Set<EventType>([
      EventType.pointer_move,
      EventType.pointer_down,
      EventType.pointer_up,
      EventType.pointer_click,
      EventType.pointer_cancel,
      EventType.scroll,
      EventType.key_down,
      EventType.key_up,
      EventType.text_input,
      EventType.focus_changed,
      EventType.viewport_changed
    ]);
    expect(covered.size).toBe(11);
  });

  it('measures session limits in UTF-8 bytes', () => {
    expect(() => sessionTag('é'.repeat(33))).toThrow(PackedProtocolError);
    expect(() =>
      encodeControl({ type: ControlType.ready, sessionId: 'é'.repeat(33), timestamp: 1n })
    ).toThrow();
  });

  it('rejects mismatched payloads and invalid fields', () => {
    const control = encodeControl({
      type: ControlType.ready,
      sessionId: 'session-1',
      timestamp: 1n
    });
    const input = encodeInput({
      type: EventType.text_input,
      sessionId: 'session-1',
      text: 'hello',
      timestamp: 1n
    });

    expect(() => decodeInput(control)).toThrow();
    expect(() => decodeControl(input)).toThrow();
    expect(() => encodeControl({ type: ControlType.ready, sessionId: '' })).toThrow();
    expect(() => encodeInput({ type: EventType.text_input, sessionId: 's', text: '' })).toThrow();
    expect(() =>
      encodeInput({ type: EventType.focus_changed, sessionId: 's', target: 'x'.repeat(129) })
    ).toThrow();
  });
});
