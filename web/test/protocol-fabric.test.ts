import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import * as flatbuffers from 'flatbuffers';
import { describe, expect, it } from 'vitest';
import {
  ControlType,
  EventType,
  decodeControl,
  decodeInput,
  encodeControl,
  encodeInput
} from '../src/protocol';
import { Authorization } from '../src/protocol/generated/air-desk/protocol/authorization';
import { Availability } from '../src/protocol/generated/air-desk/protocol/availability';
import { CapabilityDescriptor } from '../src/protocol/generated/air-desk/protocol/capability-descriptor';
import { CapabilityLease } from '../src/protocol/generated/air-desk/protocol/capability-lease';
import { ChannelBindingKind } from '../src/protocol/generated/air-desk/protocol/channel-binding-kind';
import { ControlHeader } from '../src/protocol/generated/air-desk/protocol/control-header';
import { DeviceIdentity } from '../src/protocol/generated/air-desk/protocol/device-identity';
import { DeviceKind } from '../src/protocol/generated/air-desk/protocol/device-kind';
import { DisplaySession } from '../src/protocol/generated/air-desk/protocol/display-session';
import { Envelope } from '../src/protocol/generated/air-desk/protocol/envelope';
import { FabricPayload } from '../src/protocol/generated/air-desk/protocol/fabric-payload';
import { GroupMember } from '../src/protocol/generated/air-desk/protocol/group-member';
import { MergeClass } from '../src/protocol/generated/air-desk/protocol/merge-class';
import { MessagePayload } from '../src/protocol/generated/air-desk/protocol/message-payload';
import { PairingOffer } from '../src/protocol/generated/air-desk/protocol/pairing-offer';
import { PairingResponse } from '../src/protocol/generated/air-desk/protocol/pairing-response';
import { Qid } from '../src/protocol/generated/air-desk/protocol/qid';
import { ResourceOpCode } from '../src/protocol/generated/air-desk/protocol/resource-op-code';
import { ResourceRpc } from '../src/protocol/generated/air-desk/protocol/resource-rpc';
import { ResourceRpcPayload } from '../src/protocol/generated/air-desk/protocol/resource-rpc-payload';
import { ResourceWalk } from '../src/protocol/generated/air-desk/protocol/resource-walk';
import { ResourceWalkResult } from '../src/protocol/generated/air-desk/protocol/resource-walk-result';
import { SenderRole } from '../src/protocol/generated/air-desk/protocol/sender-role';
import { SyncRecord } from '../src/protocol/generated/air-desk/protocol/sync-record';
import { Viewport } from '../src/protocol/generated/air-desk/protocol/viewport';

const MAX_ENVELOPE_BYTES = 64 * 1024;

interface HeaderFixture {
  messageId?: string;
  senderDeviceId?: string;
  senderRole: keyof typeof SenderRole;
  correlationId?: string;
  idempotencyKey?: string;
  expiresAt: string;
  cancellationId?: string;
}

interface IdentityFixture {
  version: number;
  kind: keyof typeof DeviceKind;
  deviceId: string;
  publicKey?: string;
  nonce?: string;
  expiresAt: string;
  channelBindingKind: keyof typeof ChannelBindingKind;
  channelBindingValue?: string;
  capabilities: string[];
}

interface PairingOfferFixture {
  identity: IdentityFixture;
  offerNonce: string;
  expiresAt: string;
  channelBindingKind: keyof typeof ChannelBindingKind;
  channelBindingValue?: string;
  capabilities: string[];
}

interface PairingResponseFixture extends Omit<PairingOfferFixture, 'offerNonce'> {
  offerNonce: string;
  responseNonce: string;
  accepted: boolean;
}

interface CapabilityDescriptorFixture {
  capUri: string;
  version: number;
  providerDeviceId: string;
  availability: keyof typeof Availability;
  authorization: keyof typeof Authorization;
  permissions: string[];
  execution: string;
  transport: string;
  constraints: string;
}

interface CapabilityLeaseFixture {
  leaseId: string;
  capUri: string;
  workspaceId: string;
  applicationId: string;
  requesterDeviceId: string;
  sessionId: string;
  issuedAt: string;
  expiresAt: string;
  revoked: boolean;
  revocationReason?: string;
  operations: string[];
  auditId: string;
}

interface DisplaySessionFixture {
  workspaceId: string;
  displayId: string;
  viewport: {
    width: number;
    height: number;
    scale: number;
    orientation: string;
  };
  profile: string;
  generation: number;
}

interface SyncRecordFixture {
  workspaceId: string;
  recordId: string;
  deviceId: string;
  userId: string;
  seq: string;
  mergeClass: keyof typeof MergeClass;
  payloadHash: string;
}

interface GroupMemberFixture {
  workspaceId: string;
  deviceId: string;
  userId: string;
  role: string;
  seq: string;
}

interface FabricFixture {
  name: string;
  header: HeaderFixture;
  pairing: {
    offer: PairingOfferFixture;
    response: PairingResponseFixture;
  };
  capability: {
    descriptor: CapabilityDescriptorFixture;
    lease: CapabilityLeaseFixture;
  };
  displaySession: DisplaySessionFixture;
  syncRecord: SyncRecordFixture;
  groupMember: GroupMemberFixture;
}

const fixture = JSON.parse(
  readFileSync(join(process.cwd(), '..', 'protocol', 'fixtures', 'fabric-v1.json'), 'utf8')
) as FabricFixture;

class FabricProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'FabricProtocolError';
  }
}

function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length;
}

function hexBytes(hex: string | undefined, name: string, maxBytes: number): Uint8Array {
  if (hex === undefined) return new Uint8Array();
  if (hex.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(hex)) {
    throw new FabricProtocolError(`invalid ${name}`);
  }
  const bytes = Uint8Array.from(Buffer.from(hex, 'hex'));
  if (bytes.length > maxBytes) throw new FabricProtocolError(`${name} is too long`);
  return bytes;
}

function timestamp(value: string, name: string): bigint {
  let parsed: bigint;
  try {
    parsed = BigInt(value);
  } catch {
    throw new FabricProtocolError(`invalid ${name}`);
  }
  if (parsed < 0n || parsed > 0xffffffffffffffffn) {
    throw new FabricProtocolError(`invalid ${name}`);
  }
  return parsed;
}

function assertString(
  value: string | undefined,
  name: string,
  maxBytes: number,
  required = false
): void {
  if (value === undefined) {
    if (required) throw new FabricProtocolError(`missing ${name}`);
    return;
  }
  if (required && value.length === 0) throw new FabricProtocolError(`missing ${name}`);
  if (utf8Length(value) > maxBytes) throw new FabricProtocolError(`${name} is too long`);
}

function assertStringList(
  values: string[],
  name: string,
  maxEntries: number,
  maxBytes: number
): void {
  if (!Array.isArray(values) || values.length > maxEntries) {
    throw new FabricProtocolError(`invalid ${name}`);
  }
  for (const value of values) assertString(value, name, maxBytes, true);
}

function validateHeader(header: HeaderFixture): void {
  assertString(header.messageId, 'message id', 128);
  assertString(header.senderDeviceId, 'sender device id', 128);
  assertString(header.correlationId, 'correlation id', 128);
  assertString(header.idempotencyKey, 'idempotency key', 128);
  assertString(header.cancellationId, 'cancellation id', 128);
  timestamp(header.expiresAt, 'header expires at');
}

function validateIdentity(identity: IdentityFixture): void {
  if (!Number.isInteger(identity.version) || identity.version < 1 || identity.version > 0xffffffff) {
    throw new FabricProtocolError('invalid identity version');
  }
  assertString(identity.deviceId, 'device id', 128, true);
  assertString(identity.publicKey, 'public key', 4096);
  hexBytes(identity.nonce, 'identity nonce', 64);
  timestamp(identity.expiresAt, 'identity expires at');
  assertString(identity.channelBindingValue, 'channel binding value', 512);
  assertStringList(identity.capabilities, 'identity capabilities', 32, 256);
}

function validateOffer(offer: PairingOfferFixture): void {
  validateIdentity(offer.identity);
  hexBytes(offer.offerNonce, 'offer nonce', 64);
  timestamp(offer.expiresAt, 'offer expires at');
  assertString(offer.channelBindingValue, 'channel binding value', 512);
  assertStringList(offer.capabilities, 'offer capabilities', 32, 256);
}

function validateResponse(response: PairingResponseFixture): void {
  validateIdentity(response.identity);
  hexBytes(response.offerNonce, 'offer nonce', 64);
  hexBytes(response.responseNonce, 'response nonce', 64);
  timestamp(response.expiresAt, 'response expires at');
  assertString(response.channelBindingValue, 'channel binding value', 512);
  assertStringList(response.capabilities, 'response capabilities', 32, 256);
}

function validateDescriptor(descriptor: CapabilityDescriptorFixture): void {
  assertString(descriptor.capUri, 'capability uri', 256, true);
  if (!Number.isInteger(descriptor.version) || descriptor.version < 1) {
    throw new FabricProtocolError('invalid capability version');
  }
  assertString(descriptor.providerDeviceId, 'provider device id', 128, true);
  assertStringList(descriptor.permissions, 'permissions', 64, 128);
  assertString(descriptor.execution, 'execution', 128);
  assertString(descriptor.transport, 'transport', 128);
  assertString(descriptor.constraints, 'constraints', 4096);
}

function validateLease(lease: CapabilityLeaseFixture): void {
  assertString(lease.leaseId, 'lease id', 128, true);
  assertString(lease.capUri, 'capability uri', 256, true);
  assertString(lease.workspaceId, 'workspace id', 128, true);
  assertString(lease.applicationId, 'application id', 128);
  assertString(lease.requesterDeviceId, 'requester device id', 128);
  assertString(lease.sessionId, 'session id', 128);
  timestamp(lease.issuedAt, 'issued at');
  timestamp(lease.expiresAt, 'expires at');
  assertString(lease.revocationReason, 'revocation reason', 256);
  assertStringList(lease.operations, 'operations', 64, 128);
  assertString(lease.auditId, 'audit id', 128);
}

function createByteVector(builder: flatbuffers.Builder, bytes: Uint8Array): flatbuffers.Offset {
  if (bytes.length === 0) return 0;
  builder.startVector(1, bytes.length, 1);
  for (let index = bytes.length - 1; index >= 0; index--) {
    builder.addInt8(bytes[index]!);
  }
  return builder.endVector();
}

function createStringVector(
  builder: flatbuffers.Builder,
  values: string[]
): flatbuffers.Offset {
  if (values.length === 0) return 0;
  const offsets = values.map((value) => builder.createString(value));
  builder.startVector(4, offsets.length, 4);
  for (let index = offsets.length - 1; index >= 0; index--) {
    builder.addOffset(offsets[index]!);
  }
  return builder.endVector();
}

function optionalString(builder: flatbuffers.Builder, value: string | undefined): flatbuffers.Offset {
  return value === undefined ? 0 : builder.createString(value);
}

function createHeader(builder: flatbuffers.Builder, header: HeaderFixture): flatbuffers.Offset {
  validateHeader(header);
  return ControlHeader.createControlHeader(
    builder,
    optionalString(builder, header.messageId),
    optionalString(builder, header.senderDeviceId),
    SenderRole[header.senderRole],
    optionalString(builder, header.correlationId),
    optionalString(builder, header.idempotencyKey),
    timestamp(header.expiresAt, 'header expires at'),
    optionalString(builder, header.cancellationId)
  );
}

function createIdentity(
  builder: flatbuffers.Builder,
  identity: IdentityFixture
): flatbuffers.Offset {
  validateIdentity(identity);
  return DeviceIdentity.createDeviceIdentity(
    builder,
    identity.version,
    DeviceKind[identity.kind],
    builder.createString(identity.deviceId),
    optionalString(builder, identity.publicKey),
    createByteVector(builder, hexBytes(identity.nonce, 'identity nonce', 64)),
    timestamp(identity.expiresAt, 'identity expires at'),
    ChannelBindingKind[identity.channelBindingKind],
    optionalString(builder, identity.channelBindingValue),
    createStringVector(builder, identity.capabilities)
  );
}

function createOffer(builder: flatbuffers.Builder, offer: PairingOfferFixture): flatbuffers.Offset {
  validateOffer(offer);
  return PairingOffer.createPairingOffer(
    builder,
    createIdentity(builder, offer.identity),
    createByteVector(builder, hexBytes(offer.offerNonce, 'offer nonce', 64)),
    timestamp(offer.expiresAt, 'offer expires at'),
    ChannelBindingKind[offer.channelBindingKind],
    optionalString(builder, offer.channelBindingValue),
    createStringVector(builder, offer.capabilities)
  );
}

function createResponse(
  builder: flatbuffers.Builder,
  response: PairingResponseFixture
): flatbuffers.Offset {
  validateResponse(response);
  return PairingResponse.createPairingResponse(
    builder,
    createIdentity(builder, response.identity),
    createByteVector(builder, hexBytes(response.offerNonce, 'offer nonce', 64)),
    createByteVector(builder, hexBytes(response.responseNonce, 'response nonce', 64)),
    response.accepted,
    timestamp(response.expiresAt, 'response expires at'),
    ChannelBindingKind[response.channelBindingKind],
    optionalString(builder, response.channelBindingValue),
    createStringVector(builder, response.capabilities)
  );
}

function createDescriptor(
  builder: flatbuffers.Builder,
  descriptor: CapabilityDescriptorFixture
): flatbuffers.Offset {
  validateDescriptor(descriptor);
  return CapabilityDescriptor.createCapabilityDescriptor(
    builder,
    builder.createString(descriptor.capUri),
    descriptor.version,
    builder.createString(descriptor.providerDeviceId),
    Availability[descriptor.availability],
    Authorization[descriptor.authorization],
    createStringVector(builder, descriptor.permissions),
    optionalString(builder, descriptor.execution),
    optionalString(builder, descriptor.transport),
    optionalString(builder, descriptor.constraints)
  );
}

function createLease(builder: flatbuffers.Builder, lease: CapabilityLeaseFixture): flatbuffers.Offset {
  validateLease(lease);
  return CapabilityLease.createCapabilityLease(
    builder,
    builder.createString(lease.leaseId),
    builder.createString(lease.capUri),
    builder.createString(lease.workspaceId),
    optionalString(builder, lease.applicationId),
    optionalString(builder, lease.requesterDeviceId),
    optionalString(builder, lease.sessionId),
    timestamp(lease.issuedAt, 'issued at'),
    timestamp(lease.expiresAt, 'expires at'),
    lease.revoked,
    optionalString(builder, lease.revocationReason),
    createStringVector(builder, lease.operations),
    optionalString(builder, lease.auditId)
  );
}

function createDisplaySession(
  builder: flatbuffers.Builder,
  session: DisplaySessionFixture
): flatbuffers.Offset {
  const viewport = Viewport.createViewport(
    builder,
    session.viewport.width,
    session.viewport.height,
    session.viewport.scale,
    builder.createString(session.viewport.orientation)
  );
  const workspaceId = builder.createString(session.workspaceId);
  const displayId = builder.createString(session.displayId);
  const profile = builder.createString(session.profile);
  DisplaySession.startDisplaySession(builder);
  DisplaySession.addWorkspaceId(builder, workspaceId);
  DisplaySession.addDisplayId(builder, displayId);
  DisplaySession.addViewport(builder, viewport);
  DisplaySession.addProfile(builder, profile);
  DisplaySession.addGeneration(builder, session.generation);
  return DisplaySession.endDisplaySession(builder);
}

function createSyncRecord(
  builder: flatbuffers.Builder,
  record: SyncRecordFixture
): flatbuffers.Offset {
  return SyncRecord.createSyncRecord(
    builder,
    builder.createString(record.workspaceId),
    builder.createString(record.recordId),
    builder.createString(record.deviceId),
    builder.createString(record.userId),
    timestamp(record.seq, 'sync sequence'),
    MergeClass[record.mergeClass],
    createByteVector(builder, hexBytes(record.payloadHash, 'payload hash', 64))
  );
}

function createGroupMember(
  builder: flatbuffers.Builder,
  member: GroupMemberFixture
): flatbuffers.Offset {
  return GroupMember.createGroupMember(
    builder,
    builder.createString(member.workspaceId),
    builder.createString(member.deviceId),
    builder.createString(member.userId),
    builder.createString(member.role),
    timestamp(member.seq, 'member sequence')
  );
}

function createResourceRpc(
  builder: flatbuffers.Builder,
  opCode: ResourceOpCode,
  payloadType: ResourceRpcPayload,
  payload: flatbuffers.Offset
): flatbuffers.Offset {
  return ResourceRpc.createResourceRpc(builder, payloadType, payload, opCode);
}

function encodeFabric(
  fabricType: FabricPayload,
  createPayload: (builder: flatbuffers.Builder) => flatbuffers.Offset,
  version = 1,
  header: HeaderFixture = fixture.header
): Uint8Array {
  const builder = new flatbuffers.Builder(1024);
  const headerOffset = createHeader(builder, header);
  const payloadOffset = createPayload(builder);
  const envelope = Envelope.createEnvelope(
    builder,
    version,
    MessagePayload.NONE,
    0,
    headerOffset,
    fabricType,
    payloadOffset
  );
  Envelope.finishEnvelopeBuffer(builder, envelope);
  return builder.asUint8Array();
}

function decodeFabric<T>(
  bytes: Uint8Array,
  expectedType: FabricPayload,
  payload: T
): { envelope: Envelope; payload: T } {
  if (bytes.length < 8) throw new FabricProtocolError('truncated envelope');
  if (bytes.length > MAX_ENVELOPE_BYTES) throw new FabricProtocolError('oversized envelope');
  const buffer = new flatbuffers.ByteBuffer(bytes);
  if (!Envelope.bufferHasIdentifier(buffer)) {
    throw new FabricProtocolError('missing envelope identifier');
  }
  const envelope = Envelope.getRootAsEnvelope(buffer);
  if (envelope.version() !== 1) throw new FabricProtocolError('unsupported version');
  if (envelope.fabricPayloadType() !== expectedType) {
    throw new FabricProtocolError('unexpected fabric payload');
  }
  const decoded = envelope.fabricPayload(payload) as T | null;
  if (!decoded) throw new FabricProtocolError('missing fabric payload');
  return { envelope, payload: decoded };
}

function headerView(envelope: Envelope): Record<string, unknown> {
  const header = envelope.header(new ControlHeader());
  if (!header) throw new FabricProtocolError('missing control header');
  return {
    messageId: header.messageId() ?? undefined,
    senderDeviceId: header.senderDeviceId() ?? undefined,
    senderRole: header.senderRole(),
    correlationId: header.correlationId() ?? undefined,
    idempotencyKey: header.idempotencyKey() ?? undefined,
    expiresAt: header.expiresAt(),
    cancellationId: header.cancellationId() ?? undefined
  };
}

function expectedHeader(): Record<string, unknown> {
  const header = fixture.header;
  return {
    messageId: header.messageId,
    senderDeviceId: header.senderDeviceId,
    senderRole: SenderRole[header.senderRole],
    correlationId: header.correlationId,
    idempotencyKey: header.idempotencyKey,
    expiresAt: BigInt(header.expiresAt),
    cancellationId: header.cancellationId
  };
}

function strings(length: number, get: (index: number) => string | null): string[] {
  const values: string[] = [];
  for (let index = 0; index < length; index++) {
    const value = get(index);
    if (value !== null) values.push(value);
  }
  return values;
}

function bytes(value: Uint8Array | null): string {
  return value === null ? '' : Buffer.from(value).toString('hex');
}

describe('fabric v1 conformance fixture', () => {
  it('round-trips a typed header through a pairing offer', () => {
    const encoded = encodeFabric(FabricPayload.PairingOffer, (builder) =>
      createOffer(builder, fixture.pairing.offer)
    );
    const { envelope } = decodeFabric(encoded, FabricPayload.PairingOffer, new PairingOffer());
    expect(headerView(envelope)).toEqual(expectedHeader());
  });

  it('round-trips a pairing offer', () => {
    const expected = fixture.pairing.offer;
    const encoded = encodeFabric(FabricPayload.PairingOffer, (builder) =>
      createOffer(builder, expected)
    );
    const { envelope, payload } = decodeFabric(
      encoded,
      FabricPayload.PairingOffer,
      new PairingOffer()
    );
    const offer = payload as PairingOffer;
    const identity = offer.identity(new DeviceIdentity());
    expect(identity).not.toBeNull();

    expect({
      version: identity!.version(),
      kind: identity!.kind(),
      deviceId: identity!.deviceId(),
      publicKey: identity!.publicKey(),
      nonce: bytes(identity!.nonceArray()),
      expiresAt: identity!.expiresAt(),
      channelBindingKind: identity!.channelBindingKind(),
      channelBindingValue: identity!.channelBindingValue(),
      capabilities: strings(identity!.capabilitiesLength(), (index) =>
        identity!.capabilities(index)
      )
    }).toEqual({
      version: expected.identity.version,
      kind: DeviceKind[expected.identity.kind],
      deviceId: expected.identity.deviceId,
      publicKey: expected.identity.publicKey,
      nonce: expected.identity.nonce,
      expiresAt: BigInt(expected.identity.expiresAt),
      channelBindingKind: ChannelBindingKind[expected.identity.channelBindingKind],
      channelBindingValue: expected.identity.channelBindingValue,
      capabilities: expected.identity.capabilities
    });

    expect({
      offerNonce: bytes(offer.offerNonceArray()),
      expiresAt: offer.expiresAt(),
      channelBindingKind: offer.channelBindingKind(),
      channelBindingValue: offer.channelBindingValue(),
      capabilities: strings(offer.capabilitiesLength(), (index) => offer.capabilities(index))
    }).toEqual({
      offerNonce: expected.offerNonce,
      expiresAt: BigInt(expected.expiresAt),
      channelBindingKind: ChannelBindingKind[expected.channelBindingKind],
      channelBindingValue: expected.channelBindingValue,
      capabilities: expected.capabilities
    });
    expect(headerView(envelope)).toEqual(expectedHeader());
  });

  it('round-trips a pairing response', () => {
    const expected = fixture.pairing.response;
    const encoded = encodeFabric(FabricPayload.PairingResponse, (builder) =>
      createResponse(builder, expected)
    );
    const { envelope, payload } = decodeFabric(
      encoded,
      FabricPayload.PairingResponse,
      new PairingResponse()
    );
    const response = payload as PairingResponse;
    const identity = response.identity(new DeviceIdentity());
    expect(identity).not.toBeNull();

    expect({
      deviceId: identity!.deviceId(),
      kind: identity!.kind(),
      nonce: bytes(identity!.nonceArray()),
      channelBindingKind: identity!.channelBindingKind()
    }).toEqual({
      deviceId: expected.identity.deviceId,
      kind: DeviceKind[expected.identity.kind],
      nonce: expected.identity.nonce,
      channelBindingKind: ChannelBindingKind[expected.identity.channelBindingKind]
    });

    expect({
      offerNonce: bytes(response.offerNonceArray()),
      responseNonce: bytes(response.responseNonceArray()),
      accepted: response.accepted(),
      expiresAt: response.expiresAt(),
      channelBindingKind: response.channelBindingKind(),
      channelBindingValue: response.channelBindingValue(),
      capabilities: strings(response.capabilitiesLength(), (index) =>
        response.capabilities(index)
      )
    }).toEqual({
      offerNonce: expected.offerNonce,
      responseNonce: expected.responseNonce,
      accepted: expected.accepted,
      expiresAt: BigInt(expected.expiresAt),
      channelBindingKind: ChannelBindingKind[expected.channelBindingKind],
      channelBindingValue: expected.channelBindingValue,
      capabilities: expected.capabilities
    });
    expect(headerView(envelope)).toEqual(expectedHeader());
  });

  it('round-trips a capability descriptor', () => {
    const expected = fixture.capability.descriptor;
    const encoded = encodeFabric(FabricPayload.CapabilityDescriptor, (builder) =>
      createDescriptor(builder, expected)
    );
    const { envelope, payload } = decodeFabric(
      encoded,
      FabricPayload.CapabilityDescriptor,
      new CapabilityDescriptor()
    );
    const descriptor = payload as CapabilityDescriptor;

    expect({
      capUri: descriptor.capUri(),
      version: descriptor.version(),
      providerDeviceId: descriptor.providerDeviceId(),
      availability: descriptor.availability(),
      authorization: descriptor.authorization(),
      permissions: strings(descriptor.permissionsLength(), (index) =>
        descriptor.permissions(index)
      ),
      execution: descriptor.execution(),
      transport: descriptor.transport(),
      constraints: descriptor.constraints()
    }).toEqual({
      capUri: expected.capUri,
      version: expected.version,
      providerDeviceId: expected.providerDeviceId,
      availability: Availability[expected.availability],
      authorization: Authorization[expected.authorization],
      permissions: expected.permissions,
      execution: expected.execution,
      transport: expected.transport,
      constraints: expected.constraints
    });
    expect(headerView(envelope)).toEqual(expectedHeader());
  });

  it('round-trips a capability lease', () => {
    const expected = fixture.capability.lease;
    const encoded = encodeFabric(FabricPayload.CapabilityLease, (builder) =>
      createLease(builder, expected)
    );
    const { envelope, payload } = decodeFabric(
      encoded,
      FabricPayload.CapabilityLease,
      new CapabilityLease()
    );
    const lease = payload as CapabilityLease;

    expect({
      leaseId: lease.leaseId(),
      capUri: lease.capUri(),
      workspaceId: lease.workspaceId(),
      applicationId: lease.applicationId(),
      requesterDeviceId: lease.requesterDeviceId(),
      sessionId: lease.sessionId(),
      issuedAt: lease.issuedAt(),
      expiresAt: lease.expiresAt(),
      revoked: lease.revoked(),
      revocationReason: lease.revocationReason(),
      operations: strings(lease.operationsLength(), (index) => lease.operations(index)),
      auditId: lease.auditId()
    }).toEqual({
      leaseId: expected.leaseId,
      capUri: expected.capUri,
      workspaceId: expected.workspaceId,
      applicationId: expected.applicationId,
      requesterDeviceId: expected.requesterDeviceId,
      sessionId: expected.sessionId,
      issuedAt: BigInt(expected.issuedAt),
      expiresAt: BigInt(expected.expiresAt),
      revoked: expected.revoked,
      revocationReason: expected.revocationReason ?? null,
      operations: expected.operations,
      auditId: expected.auditId
    });
    expect(headerView(envelope)).toEqual(expectedHeader());
  });

  it('round-trips display, sync and group primitives', () => {
    const display = fixture.displaySession;
    const displayBytes = encodeFabric(FabricPayload.DisplaySession, (builder) =>
      createDisplaySession(builder, display)
    );
    const decodedDisplay = decodeFabric(
      displayBytes,
      FabricPayload.DisplaySession,
      new DisplaySession()
    ).payload as DisplaySession;
    const viewport = decodedDisplay.viewport(new Viewport());
    expect(viewport).not.toBeNull();
    expect({
      workspaceId: decodedDisplay.workspaceId(),
      displayId: decodedDisplay.displayId(),
      profile: decodedDisplay.profile(),
      generation: decodedDisplay.generation(),
      viewport: {
        width: viewport!.width(),
        height: viewport!.height(),
        scale: viewport!.scale(),
        orientation: viewport!.orientation()
      }
    }).toEqual(display);

    const sync = fixture.syncRecord;
    const syncBytes = encodeFabric(FabricPayload.SyncRecord, (builder) =>
      createSyncRecord(builder, sync)
    );
    const decodedSync = decodeFabric(syncBytes, FabricPayload.SyncRecord, new SyncRecord())
      .payload as SyncRecord;
    expect({
      workspaceId: decodedSync.workspaceId(),
      recordId: decodedSync.recordId(),
      deviceId: decodedSync.deviceId(),
      userId: decodedSync.userId(),
      seq: decodedSync.seq(),
      mergeClass: decodedSync.mergeClass(),
      payloadHash: bytes(decodedSync.payloadHashArray())
    }).toEqual({
      workspaceId: sync.workspaceId,
      recordId: sync.recordId,
      deviceId: sync.deviceId,
      userId: sync.userId,
      seq: BigInt(sync.seq),
      mergeClass: MergeClass[sync.mergeClass],
      payloadHash: sync.payloadHash
    });

    const member = fixture.groupMember;
    const memberBytes = encodeFabric(FabricPayload.GroupMember, (builder) =>
      createGroupMember(builder, member)
    );
    const decodedMember = decodeFabric(memberBytes, FabricPayload.GroupMember, new GroupMember())
      .payload as GroupMember;
    expect({
      workspaceId: decodedMember.workspaceId(),
      deviceId: decodedMember.deviceId(),
      userId: decodedMember.userId(),
      role: decodedMember.role(),
      seq: decodedMember.seq()
    }).toEqual({
      workspaceId: member.workspaceId,
      deviceId: member.deviceId,
      userId: member.userId,
      role: member.role,
      seq: BigInt(member.seq)
    });
  });
});

describe('fabric envelope validation', () => {
  it('rejects a wrong file identifier', () => {
    const encoded = encodeFabric(FabricPayload.PairingOffer, (builder) =>
      createOffer(builder, fixture.pairing.offer)
    );
    const wrongIdentifier = encoded.slice();
    wrongIdentifier[4] = 0x58;
    expect(() =>
      decodeFabric(wrongIdentifier, FabricPayload.PairingOffer, new PairingOffer())
    ).toThrow(/identifier/);
  });

  it('rejects an unsupported envelope version', () => {
    const encoded = encodeFabric(
      FabricPayload.PairingOffer,
      (builder) => createOffer(builder, fixture.pairing.offer),
      2
    );
    expect(() =>
      decodeFabric(encoded, FabricPayload.PairingOffer, new PairingOffer())
    ).toThrow(/version/);
  });

  it('round-trips resource RPC op codes and Qid tuples', () => {
    expect({
      attach: ResourceOpCode.attach,
      attachResult: ResourceOpCode.attach_result,
      walk: ResourceOpCode.walk,
      walkResult: ResourceOpCode.walk_result,
      open: ResourceOpCode.open,
      openResult: ResourceOpCode.open_result,
      read: ResourceOpCode.read,
      readResult: ResourceOpCode.read_result,
      write: ResourceOpCode.write,
      writeResult: ResourceOpCode.write_result,
      clunk: ResourceOpCode.clunk,
      clunkResult: ResourceOpCode.clunk_result,
      stat: ResourceOpCode.stat,
      statResult: ResourceOpCode.stat_result,
      wstat: ResourceOpCode.wstat,
      wstatResult: ResourceOpCode.wstat_result
    }).toEqual({
      attach: 100,
      attachResult: 101,
      walk: 102,
      walkResult: 103,
      open: 104,
      openResult: 105,
      read: 106,
      readResult: 107,
      write: 108,
      writeResult: 109,
      clunk: 110,
      clunkResult: 111,
      stat: 112,
      statResult: 113,
      wstat: 114,
      wstatResult: 115
    });

    const walkBytes = encodeFabric(FabricPayload.ResourceRpc, (builder) => {
      const wnames = ResourceWalk.createWnamesVector(builder, [
        builder.createString('etc'),
        builder.createString('hosts')
      ]);
      return createResourceRpc(
        builder,
        ResourceOpCode.walk,
        ResourceRpcPayload.ResourceWalk,
        ResourceWalk.createResourceWalk(builder, 7, 8, wnames)
      );
    });
    const walkRpc = decodeFabric(walkBytes, FabricPayload.ResourceRpc, new ResourceRpc())
      .payload as ResourceRpc;
    const walk = walkRpc.payload(new ResourceWalk()) as ResourceWalk | null;
    expect(walkRpc.opCode()).toBe(ResourceOpCode.walk);
    expect(walkRpc.payloadType()).toBe(ResourceRpcPayload.ResourceWalk);
    expect(walk).not.toBeNull();
    expect({
      fid: walk!.fid(),
      newFid: walk!.newFid(),
      wnames: strings(walk!.wnamesLength(), (index) => walk!.wnames(index))
    }).toEqual({ fid: 7, newFid: 8, wnames: ['etc', 'hosts'] });

    const resultBytes = encodeFabric(FabricPayload.ResourceRpc, (builder) => {
      ResourceWalkResult.startWqidsVector(builder, 2);
      Qid.createQid(builder, 0x80, 3, 9n);
      Qid.createQid(builder, 1, 2, 0x1122334455667788n);
      const qids = builder.endVector();
      return createResourceRpc(
        builder,
        ResourceOpCode.walk_result,
        ResourceRpcPayload.ResourceWalkResult,
        ResourceWalkResult.createResourceWalkResult(builder, qids)
      );
    });
    const resultRpc = decodeFabric(
      resultBytes,
      FabricPayload.ResourceRpc,
      new ResourceRpc()
    ).payload as ResourceRpc;
    const result = resultRpc.payload(new ResourceWalkResult()) as ResourceWalkResult | null;
    expect(resultRpc.opCode()).toBe(ResourceOpCode.walk_result);
    expect(result).not.toBeNull();
    expect(result!.wqidsLength()).toBe(2);
    expect([
      result!.wqids(0, new Qid())!.type(),
      result!.wqids(0, new Qid())!.version(),
      result!.wqids(0, new Qid())!.path(),
      result!.wqids(1, new Qid())!.type()
    ]).toEqual([1, 2, 0x1122334455667788n, 0x80]);
  });

  it('rejects malformed envelopes', () => {
    const encoded = encodeFabric(FabricPayload.PairingOffer, (builder) =>
      createOffer(builder, fixture.pairing.offer)
    );
    expect(() =>
      decodeFabric(encoded.slice(0, 8), FabricPayload.PairingOffer, new PairingOffer())
    ).toThrow();

    const badRoot = encoded.slice();
    new DataView(badRoot.buffer, badRoot.byteOffset, badRoot.byteLength).setUint32(
      0,
      badRoot.length + 64,
      true
    );
    expect(() =>
      decodeFabric(badRoot, FabricPayload.PairingOffer, new PairingOffer())
    ).toThrow();
  });

  it('rejects oversized envelopes and fields', () => {
    expect(() =>
      decodeFabric(
        new Uint8Array(MAX_ENVELOPE_BYTES + 1),
        FabricPayload.PairingOffer,
        new PairingOffer()
      )
    ).toThrow(/oversized/);

    const oversized = {
      ...fixture.pairing.offer,
      identity: {
        ...fixture.pairing.offer.identity,
        deviceId: 'x'.repeat(129)
      }
    };
    expect(() =>
      encodeFabric(FabricPayload.PairingOffer, (builder) => createOffer(builder, oversized))
    ).toThrow(/device id/);
  });
});

describe('legacy v1 compatibility', () => {
  it('still decodes control and input envelopes', () => {
    const control = decodeControl(
      encodeControl({
        type: ControlType.state,
        sessionId: 'session-legacy',
        generation: 3,
        seq: 4,
        timestamp: 1700000000123n,
        message: 'legacy'
      })
    );
    expect(control).toMatchObject({
      type: ControlType.state,
      sessionId: 'session-legacy',
      generation: 3,
      seq: 4,
      timestamp: 1700000000123n,
      message: 'legacy'
    });

    const input = decodeInput(
      encodeInput({
        type: EventType.key_down,
        sessionId: 'session-legacy',
        generation: 3,
        seq: 5,
        timestamp: 1700000000124n,
        key: 'a',
        code: 'KeyA'
      })
    );
    expect(input).toMatchObject({
      type: EventType.key_down,
      sessionId: 'session-legacy',
      generation: 3,
      seq: 5,
      timestamp: 1700000000124n,
      key: 'a',
      code: 'KeyA'
    });
  });
});
