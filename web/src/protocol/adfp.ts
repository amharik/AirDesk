import type * as flatbuffers from 'flatbuffers';
import { ControlHeader } from './generated/air-desk/protocol/control-header';
import { SenderRole } from './generated/air-desk/protocol/sender-role';

export const ADFP_FILE_IDENTIFIER = 'ADEN';
export const ADFP_VERSION = 1;
export const ADFP_MAX_ENVELOPE_BYTES = 1024 * 1024;
export const ADFP_MAX_HEADER_STRING_BYTES = 128;

export interface ADFPHeader {
  messageId: string;
  senderDeviceId: string;
  senderRole: SenderRole;
  correlationId?: string;
  idempotencyKey?: string;
  expiresAt?: bigint;
  cancellationId?: string;
}

export interface DecodedADFPHeader {
  messageId: string;
  senderDeviceId: string;
  senderRole: SenderRole;
  correlationId?: string;
  idempotencyKey?: string;
  expiresAt: bigint;
  cancellationId?: string;
}

export enum ADFPError {
  empty = 'empty',
  oversized = 'oversized',
  truncated = 'truncated',
  wrongFileIdentifier = 'wrong-file-identifier',
  wrongVersion = 'wrong-version',
  headerMissing = 'header-missing',
  headerInvalid = 'header-invalid',
  headerExpired = 'header-expired',
  unsupportedPayload = 'unsupported-payload'
}

export class ADFPErrorException extends Error {
  constructor(
    readonly reason: ADFPError,
    message: string
  ) {
    super(message);
    this.name = 'ADFPErrorException';
  }
}

function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length;
}

function requiredHeaderString(value: string | undefined, name: string): string {
  if (!value) throw new ADFPErrorException(ADFPError.headerInvalid, `${name} is required`);
  if (utf8Length(value) > ADFP_MAX_HEADER_STRING_BYTES) {
    throw new ADFPErrorException(ADFPError.headerInvalid, `${name} exceeds ${ADFP_MAX_HEADER_STRING_BYTES} bytes`);
  }
  return value;
}

function optionalHeaderString(value: string | undefined, name: string): string | undefined {
  if (value === undefined) return undefined;
  if (utf8Length(value) > ADFP_MAX_HEADER_STRING_BYTES) {
    throw new ADFPErrorException(ADFPError.headerInvalid, `${name} exceeds ${ADFP_MAX_HEADER_STRING_BYTES} bytes`);
  }
  return value;
}

export function validateADFPHeader(header: ADFPHeader, nowEpochMillis = BigInt(Date.now())): void {
  requiredHeaderString(header.messageId, 'messageId');
  requiredHeaderString(header.senderDeviceId, 'senderDeviceId');
  optionalHeaderString(header.correlationId, 'correlationId');
  optionalHeaderString(header.idempotencyKey, 'idempotencyKey');
  optionalHeaderString(header.cancellationId, 'cancellationId');
  if (header.senderRole === SenderRole.unspecified) {
    throw new ADFPErrorException(ADFPError.headerInvalid, 'senderRole is required');
  }
  if (header.expiresAt !== undefined) {
    if (header.expiresAt < 0n || header.expiresAt > 0xffffffffffffffffn) {
      throw new ADFPErrorException(ADFPError.headerInvalid, 'expiresAt is out of range');
    }
    if (header.expiresAt !== 0n && header.expiresAt <= nowEpochMillis) {
      throw new ADFPErrorException(ADFPError.headerExpired, 'ADFP envelope header has expired');
    }
  }
}

export function createADFPHeader(builder: flatbuffers.Builder, header: ADFPHeader): flatbuffers.Offset {
  return ControlHeader.createControlHeader(
    builder,
    builder.createString(requiredHeaderString(header.messageId, 'messageId')),
    builder.createString(requiredHeaderString(header.senderDeviceId, 'senderDeviceId')),
    header.senderRole,
    header.correlationId === undefined ? 0 : builder.createString(optionalHeaderString(header.correlationId, 'correlationId')!),
    header.idempotencyKey === undefined ? 0 : builder.createString(optionalHeaderString(header.idempotencyKey, 'idempotencyKey')!),
    header.expiresAt ?? 0n,
    header.cancellationId === undefined ? 0 : builder.createString(optionalHeaderString(header.cancellationId, 'cancellationId')!)
  );
}

export function decodeADFPHeader(
  header: ControlHeader,
  nowEpochMillis = BigInt(Date.now())
): DecodedADFPHeader {
  const decoded: DecodedADFPHeader = {
    messageId: requiredHeaderString(header.messageId() ?? undefined, 'messageId'),
    senderDeviceId: requiredHeaderString(header.senderDeviceId() ?? undefined, 'senderDeviceId'),
    senderRole: header.senderRole(),
    correlationId: header.correlationId() ?? undefined,
    idempotencyKey: header.idempotencyKey() ?? undefined,
    expiresAt: header.expiresAt(),
    cancellationId: header.cancellationId() ?? undefined
  };
  validateADFPHeader(decoded, nowEpochMillis);
  return decoded;
}

export function assertADFPEnvelopeSize(bytes: Uint8Array): void {
  if (bytes.length === 0) throw new ADFPErrorException(ADFPError.empty, 'ADFP envelope is empty');
  if (bytes.length > ADFP_MAX_ENVELOPE_BYTES) {
    throw new ADFPErrorException(
      ADFPError.oversized,
      `ADFP envelope is ${bytes.length} bytes; limit is ${ADFP_MAX_ENVELOPE_BYTES}`
    );
  }
}

export function hasADFPIdentifier(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 8 &&
    bytes[4] === 0x41 &&
    bytes[5] === 0x44 &&
    bytes[6] === 0x45 &&
    bytes[7] === 0x4e
  );
}
