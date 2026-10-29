import * as flatbuffers from 'flatbuffers';
import { Envelope } from './generated/air-desk/protocol/envelope';
import { EventType } from './generated/air-desk/protocol/event-type';
import { InputEvent } from './generated/air-desk/protocol/input-event';
import { MessagePayload } from './generated/air-desk/protocol/message-payload';

export interface InputPayload {
  type: EventType;
  sessionId: string;
  generation?: number;
  seq?: number;
  timestamp?: bigint;
  x?: number;
  y?: number;
  dx?: number;
  dy?: number;
  button?: number;
  clickCount?: number;
  key?: string;
  code?: string;
  modifiers?: string[];
  text?: string;
  width?: number;
  height?: number;
  target?: string;
}

export interface DecodedInput extends InputPayload {
  timestamp: bigint;
  generation: number;
  seq: number;
  modifiers: string[];
}

export class InputProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InputProtocolError';
  }
}

const allowedModifiers = new Set(['Meta', 'Alt', 'Control', 'Shift']);

function stringOffset(builder: flatbuffers.Builder, value: string | undefined): flatbuffers.Offset {
  return value ? builder.createString(value) : 0;
}

function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length;
}

function optionalNumber(value: number | undefined, fallback = 0): number {
  return value ?? fallback;
}

function validate(payload: InputPayload): void {
  if (!payload.sessionId || utf8Length(payload.sessionId) > 64) throw new InputProtocolError('invalid session id');
  if (payload.generation !== undefined && (!Number.isInteger(payload.generation) || payload.generation < 0 || payload.generation > 0xffffffff)) {
    throw new InputProtocolError('invalid generation');
  }
  if (payload.seq !== undefined && (!Number.isInteger(payload.seq) || payload.seq < 0 || payload.seq > 0xffffffff)) {
    throw new InputProtocolError('invalid sequence');
  }
  if (payload.timestamp !== undefined && (payload.timestamp <= 0n || payload.timestamp > 0xffffffffffffffffn)) {
    throw new InputProtocolError('invalid timestamp');
  }

  switch (payload.type) {
    case EventType.pointer_move:
    case EventType.pointer_down:
    case EventType.pointer_up:
    case EventType.pointer_click: {
      if (payload.x === undefined || payload.y === undefined || !Number.isFinite(payload.x) || !Number.isFinite(payload.y) || payload.x < 0 || payload.x > 1 || payload.y < 0 || payload.y > 1) {
        throw new InputProtocolError('invalid coordinates');
      }
      if (payload.button !== undefined && (!Number.isInteger(payload.button) || payload.button < 0 || payload.button > 4)) {
        throw new InputProtocolError('invalid button');
      }
      if (payload.clickCount !== undefined && (!Number.isInteger(payload.clickCount) || payload.clickCount < 1 || payload.clickCount > 3)) {
        throw new InputProtocolError('invalid click count');
      }
      break;
    }
    case EventType.scroll:
      if (payload.dx === undefined || payload.dy === undefined || !Number.isFinite(payload.dx) || !Number.isFinite(payload.dy) || Math.abs(payload.dx) > 20_000 || Math.abs(payload.dy) > 20_000) {
        throw new InputProtocolError('invalid delta');
      }
      break;
    case EventType.key_down:
    case EventType.key_up:
      if (!payload.key || utf8Length(payload.key) > 64) throw new InputProtocolError('invalid key');
      break;
    case EventType.text_input:
      if (!payload.text || utf8Length(payload.text) > 4096 || payload.text.includes('\u0000')) {
        throw new InputProtocolError('invalid text');
      }
      break;
    case EventType.viewport_changed:
      if (payload.width === undefined || payload.height === undefined || !Number.isFinite(payload.width) || !Number.isFinite(payload.height) || payload.width <= 0 || payload.height <= 0 || payload.width > 20_000 || payload.height > 20_000) {
        throw new InputProtocolError('invalid viewport');
      }
      break;
    case EventType.pointer_cancel:
    case EventType.focus_changed:
      break;
  }

  if (payload.target !== undefined && utf8Length(payload.target) > 128) throw new InputProtocolError('target is too long');
  for (const modifier of payload.modifiers ?? []) {
    if (!allowedModifiers.has(modifier)) throw new InputProtocolError(`invalid modifier: ${modifier}`);
  }
}

export function encodeInput(payload: InputPayload): Uint8Array {
  validate(payload);
  const builder = new flatbuffers.Builder(256);
  const sessionId = builder.createString(payload.sessionId);
  const key = stringOffset(builder, payload.key);
  const code = stringOffset(builder, payload.code);
  const text = stringOffset(builder, payload.text);
  const target = stringOffset(builder, payload.target);
  const modifiers = (payload.modifiers ?? []).map((modifier) => builder.createString(modifier));
  let modifiersOffset = 0;
  if (modifiers.length) {
    InputEvent.startModifiersVector(builder, modifiers.length);
    for (let index = modifiers.length - 1; index >= 0; index--) {
      builder.addOffset(modifiers[index]!);
    }
    modifiersOffset = builder.endVector();
  }

  const input = InputEvent.createInputEvent(
    builder,
    1,
    payload.type,
    sessionId,
    payload.generation ?? 0,
    payload.seq ?? 0,
    payload.timestamp ?? BigInt(Date.now()),
    optionalNumber(payload.x),
    optionalNumber(payload.y),
    optionalNumber(payload.dx),
    optionalNumber(payload.dy),
    optionalNumber(payload.button),
    optionalNumber(payload.clickCount, 1),
    key,
    code,
    modifiersOffset,
    text,
    optionalNumber(payload.width),
    optionalNumber(payload.height),
    target
  );
  const envelope = Envelope.createEnvelope(builder, 1, MessagePayload.InputEvent, input);
  Envelope.finishEnvelopeBuffer(builder, envelope);
  return builder.asUint8Array();
}

export function decodeInput(bytes: Uint8Array): DecodedInput {
  const buffer = new flatbuffers.ByteBuffer(bytes);
  if (!Envelope.bufferHasIdentifier(buffer)) throw new InputProtocolError('missing envelope identifier');
  const envelope = Envelope.getRootAsEnvelope(buffer);
  if (envelope.version() !== 1) throw new InputProtocolError('unsupported version');
  if (envelope.payloadType() !== MessagePayload.InputEvent) throw new InputProtocolError('not an input event');
  const input = envelope.payload(new InputEvent()) as InputEvent | null;
  if (!input) throw new InputProtocolError('missing input payload');

  const sessionId = input.sessionId();
  if (!sessionId) throw new InputProtocolError('missing session id');
  const modifiers: string[] = [];
  for (let index = 0; index < input.modifiersLength(); index++) {
    const modifier = input.modifiers(index);
    if (typeof modifier === 'string') modifiers.push(modifier);
  }

  return {
    type: input.type(),
    sessionId,
    generation: input.generation(),
    seq: input.seq(),
    timestamp: input.timestamp(),
    x: input.x(),
    y: input.y(),
    dx: input.dx(),
    dy: input.dy(),
    button: input.button(),
    clickCount: input.clickCount(),
    key: input.key() ?? undefined,
    code: input.code() ?? undefined,
    modifiers,
    text: input.text() ?? undefined,
    width: input.width(),
    height: input.height(),
    target: input.target() ?? undefined
  };
}
