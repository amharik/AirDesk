import * as flatbuffers from 'flatbuffers';
import { ControlMessage } from './generated/air-desk/protocol/control-message';
import type { ControlType } from './generated/air-desk/protocol/control-type';
import { Envelope } from './generated/air-desk/protocol/envelope';
import { MessagePayload } from './generated/air-desk/protocol/message-payload';

export interface ControlPayload {
  type: ControlType;
  sessionId: string;
  generation?: number;
  seq?: number;
  timestamp?: bigint;
  appearance?: string;
  message?: string;
  action?: string;
  width?: number;
  height?: number;
  code?: string;
}

export interface DecodedControl extends ControlPayload {
  timestamp: bigint;
  generation: number;
  seq: number;
}

export class ControlProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ControlProtocolError';
  }
}

function stringOffset(builder: flatbuffers.Builder, value: string | undefined): flatbuffers.Offset {
  return value ? builder.createString(value) : 0;
}

function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length;
}

function finite(value: number | undefined, name: string, fallback = 0): number {
  if (value === undefined) return fallback;
  if (!Number.isFinite(value)) throw new ControlProtocolError(`${name} must be finite`);
  return value;
}

function validate(payload: ControlPayload): void {
  if (!payload.sessionId || utf8Length(payload.sessionId) > 64) {
    throw new ControlProtocolError('invalid session id');
  }
  if (payload.generation !== undefined && (!Number.isInteger(payload.generation) || payload.generation < 0 || payload.generation > 0xffffffff)) {
    throw new ControlProtocolError('invalid generation');
  }
  if (payload.seq !== undefined && (!Number.isInteger(payload.seq) || payload.seq < 0 || payload.seq > 0xffffffff)) {
    throw new ControlProtocolError('invalid sequence');
  }
  if (payload.timestamp !== undefined && (payload.timestamp <= 0n || payload.timestamp > 0xffffffffffffffffn)) {
    throw new ControlProtocolError('invalid timestamp');
  }
  if (payload.message !== undefined && utf8Length(payload.message) > 4000) {
    throw new ControlProtocolError('message is too long');
  }
  if (payload.action !== undefined && utf8Length(payload.action) > 64) {
    throw new ControlProtocolError('action is too long');
  }
  if (payload.appearance !== undefined && utf8Length(payload.appearance) > 16) {
    throw new ControlProtocolError('appearance is too long');
  }
  if (payload.code !== undefined && utf8Length(payload.code) > 64) {
    throw new ControlProtocolError('code is too long');
  }
  if (payload.width !== undefined) finite(payload.width, 'width');
  if (payload.height !== undefined) finite(payload.height, 'height');
}

export function encodeControl(payload: ControlPayload): Uint8Array {
  validate(payload);
  const builder = new flatbuffers.Builder(256);
  const sessionId = builder.createString(payload.sessionId);
  const appearance = stringOffset(builder, payload.appearance);
  const message = stringOffset(builder, payload.message);
  const action = stringOffset(builder, payload.action);
  const code = stringOffset(builder, payload.code);
  const control = ControlMessage.createControlMessage(
    builder,
    1,
    payload.type,
    sessionId,
    payload.generation ?? 0,
    payload.seq ?? 0,
    payload.timestamp ?? BigInt(Date.now()),
    appearance,
    message,
    action,
    finite(payload.width, 'width'),
    finite(payload.height, 'height'),
    code
  );
  const envelope = Envelope.createEnvelope(builder, 1, MessagePayload.ControlMessage, control);
  Envelope.finishEnvelopeBuffer(builder, envelope);
  return builder.asUint8Array();
}

export function decodeControl(bytes: Uint8Array): DecodedControl {
  const buffer = new flatbuffers.ByteBuffer(bytes);
  if (!Envelope.bufferHasIdentifier(buffer)) throw new ControlProtocolError('missing envelope identifier');
  const envelope = Envelope.getRootAsEnvelope(buffer);
  if (envelope.version() !== 1) throw new ControlProtocolError('unsupported version');
  if (envelope.payloadType() !== MessagePayload.ControlMessage) {
    throw new ControlProtocolError('not a control message');
  }
  const control = envelope.payload(new ControlMessage()) as ControlMessage | null;
  if (!control) throw new ControlProtocolError('missing control payload');

  const sessionId = control.sessionId();
  if (!sessionId) throw new ControlProtocolError('missing session id');

  return {
    type: control.type(),
    sessionId,
    generation: control.generation(),
    seq: control.seq(),
    timestamp: control.timestamp(),
    appearance: control.appearance() ?? undefined,
    message: control.message() ?? undefined,
    action: control.action() ?? undefined,
    width: control.width(),
    height: control.height(),
    code: control.code() ?? undefined
  };
}
