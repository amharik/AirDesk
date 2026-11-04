import { describe, expect, it } from 'vitest';
import {
  ControlType,
  EventType,
  InputChannel,
  InputChannelError,
  MOVEMENT_MAGIC,
  classifyInputFrame,
  encodeControl,
  encodeInput,
  encodePackedMovement,
  isFlatBufferEnvelope,
  routeInput,
  validateInputOnChannel
} from '../src/protocol';
import type { InputPayload } from '../src/protocol';

const eventPayloads: Array<Omit<InputPayload, 'sessionId'>> = [
  { type: EventType.pointer_move, x: 0.5, y: 0.5 },
  { type: EventType.pointer_down, x: 0.5, y: 0.5, button: 0 },
  { type: EventType.pointer_up, x: 0.5, y: 0.5, button: 0 },
  { type: EventType.pointer_click, x: 0.5, y: 0.5, button: 0 },
  { type: EventType.pointer_cancel },
  { type: EventType.scroll, dx: 20_000, dy: -20_000 },
  { type: EventType.key_down, key: 'a', code: 'KeyA', modifiers: ['Meta', 'Shift'] },
  { type: EventType.key_up, key: 'a', code: 'KeyA', modifiers: ['Meta', 'Shift'] },
  { type: EventType.text_input, text: 'x'.repeat(4096) },
  { type: EventType.focus_changed, target: 't'.repeat(128) },
  { type: EventType.viewport_changed, width: 20_000, height: 20_000 }
];

const controlTypes = [
  ControlType.ready,
  ControlType.ack,
  ControlType.viewport,
  ControlType.notice,
  ControlType.state,
  ControlType.error,
  ControlType.appearance,
  ControlType.action,
  ControlType.session_start,
  ControlType.session_end,
  ControlType.ping,
  ControlType.pong,
  ControlType.log
];

describe('input channel routing', () => {
  it('routes movement, edges and control separately', () => {
    expect(routeInput(EventType.pointer_move)).toBe(InputChannel.movement);
    for (const type of [
      EventType.pointer_down,
      EventType.pointer_up,
      EventType.pointer_click,
      EventType.pointer_cancel,
      EventType.scroll,
      EventType.key_down,
      EventType.key_up,
      EventType.text_input,
      EventType.focus_changed
    ]) {
      expect(routeInput(type)).toBe(InputChannel.reliableEdges);
    }
    expect(routeInput(EventType.viewport_changed)).toBe(InputChannel.control);
  });

  it('rejects edges on movement and movement on reliable channels', () => {
    expect(() => validateInputOnChannel(EventType.pointer_move, InputChannel.movement)).not.toThrow();
    expect(() => validateInputOnChannel(EventType.pointer_down, InputChannel.reliableEdges)).not.toThrow();
    expect(() => validateInputOnChannel(EventType.pointer_down, InputChannel.movement)).toThrow(
      InputChannelError
    );
    expect(() => validateInputOnChannel(EventType.pointer_move, InputChannel.reliableEdges)).toThrow(
      InputChannelError
    );
  });

  it('classifies by channel before inspecting the payload', () => {
    const movement = encodePackedMovement({
      leaseEpochLow: 1,
      seq: 1,
      x: 0.5,
      y: 0.5,
      buttonMask: 0,
      modifiers: 0
    });
    const envelope = encodeInput({
      type: EventType.key_down,
      sessionId: 'session-1',
      key: 'a',
      timestamp: 1n
    });

    expect(classifyInputFrame(movement, InputChannel.movement)).toBe('packed-movement');
    expect(classifyInputFrame(envelope, InputChannel.reliableEdges)).toBe('flatbuffer-envelope');
    expect(classifyInputFrame(envelope, InputChannel.control)).toBe('flatbuffer-envelope');
    expect(() => classifyInputFrame(movement, InputChannel.reliableEdges)).toThrow(InputChannelError);
    expect(() => classifyInputFrame(envelope, InputChannel.movement)).toThrow(InputChannelError);
    expect(() => classifyInputFrame(movement, InputChannel.movement, false)).toThrow(InputChannelError);
  });

  it('prefers the envelope identifier over a coincidental movement magic byte', () => {
    const envelope = new Uint8Array(169);
    new DataView(envelope.buffer).setUint32(0, 165, true);
    envelope.set([0x41, 0x44, 0x45, 0x4e], 4);

    expect(envelope[0]).toBe(MOVEMENT_MAGIC);
    expect(isFlatBufferEnvelope(envelope)).toBe(true);
    expect(classifyInputFrame(envelope, InputChannel.reliableEdges)).toBe('flatbuffer-envelope');
  });

  it('has no valid FlatBuffers envelope beginning with the movement magic', () => {
    const inputCorpus = eventPayloads.map((payload) =>
      encodeInput({
        ...payload,
        sessionId: 'session-1',
        generation: 0xffffffff,
        seq: 0xffffffff,
        timestamp: 0xffffffffffffffffn
      })
    );
    const controlCorpus = controlTypes.map((type) =>
      encodeControl({
        type,
        sessionId: 'session-1',
        generation: 0xffffffff,
        seq: 0xffffffff,
        timestamp: 0xffffffffffffffffn,
        appearance: 'light',
        message: 'm'.repeat(4000),
        action: 'a'.repeat(64),
        width: 20_000,
        height: 20_000,
        code: 'c'.repeat(64)
      })
    );

    for (const bytes of [...inputCorpus, ...controlCorpus]) {
      expect(bytes[0]).not.toBe(MOVEMENT_MAGIC);
      expect(isFlatBufferEnvelope(bytes)).toBe(true);
      expect(classifyInputFrame(bytes, InputChannel.reliableEdges)).toBe('flatbuffer-envelope');
    }
  });
});
