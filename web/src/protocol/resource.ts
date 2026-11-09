import * as flatbuffers from 'flatbuffers';
import { BindMode } from './generated/air-desk/protocol/bind-mode';
import { BlobAlgorithm } from './generated/air-desk/protocol/blob-algorithm';
import { BlobHandle } from './generated/air-desk/protocol/blob-handle';
import { Qid } from './generated/air-desk/protocol/qid';
import { ResourceCompoundRequest } from './generated/air-desk/protocol/resource-compound-request';
import { ResourceCompoundResult } from './generated/air-desk/protocol/resource-compound-result';
import { ResourceOpCode } from './generated/air-desk/protocol/resource-op-code';
import { ResourceReadResult } from './generated/air-desk/protocol/resource-read-result';
import { ResourceRpc } from './generated/air-desk/protocol/resource-rpc';
import { ResourceRpcPayload } from './generated/air-desk/protocol/resource-rpc-payload';
import { ResourceStat } from './generated/air-desk/protocol/resource-stat';
import { ResourceStatus } from './generated/air-desk/protocol/resource-status';

export { BindMode, BlobAlgorithm, ResourceOpCode, ResourceStatus };

export const RESOURCE_INLINE_LIMIT = 64 * 1024;
export const BLOB_HANDLE_VERSION = 1;
export const BLAKE3_DIGEST_BYTES = 32;
export const RESOURCE_MAX_PATH_SEGMENTS = 32;

export interface BlobHandlePayload {
  version?: number;
  algorithm?: BlobAlgorithm;
  digest: Uint8Array;
  length: bigint;
  expiresAt?: bigint;
}

export interface ResourceCompoundRequestPayload {
  requestId: bigint;
  fid: number;
  newFid: number;
  wnames: string[];
  openMode?: BindMode;
  readOffset?: bigint;
  readCount?: number;
  clunk?: boolean;
}

export interface ResourceCompoundResultPayload {
  requestId: bigint;
  status?: ResourceStatus;
  qid?: { type: number; version: number; path: bigint };
  iounit?: number;
  data?: Uint8Array;
  blob?: BlobHandlePayload;
  stat?: {
    qid: { type: number; version: number; path: bigint };
    mode: number;
    length: bigint;
    name: string;
    modifiedAt: bigint;
  };
  clunkStatus?: ResourceStatus;
}

export interface DecodedCompoundRequest {
  opCode: ResourceOpCode;
  request: ResourceCompoundRequestPayload;
}

export interface DecodedCompoundResult {
  opCode: ResourceOpCode;
  result: ResourceCompoundResultPayload;
}

export interface DecodedReadResult {
  opCode: ResourceOpCode;
  data: Uint8Array;
  blob: BlobHandlePayload | null;
}

export class ResourceProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ResourceProtocolError';
  }
}

function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length;
}

function validatePathSegments(wnames: string[]): void {
  if (wnames.length > RESOURCE_MAX_PATH_SEGMENTS) throw new ResourceProtocolError('too many path segments');
  for (const name of wnames) {
    if (!name || utf8Length(name) > 255 || name === '.' || name === '..' || name.includes('/')) {
      throw new ResourceProtocolError('invalid path segment');
    }
  }
}

export function validateBlobHandle(handle: BlobHandlePayload): void {
  if ((handle.version ?? BLOB_HANDLE_VERSION) !== BLOB_HANDLE_VERSION) {
    throw new ResourceProtocolError('unsupported blob handle version');
  }
  if ((handle.algorithm ?? BlobAlgorithm.blake3) !== BlobAlgorithm.blake3) {
    throw new ResourceProtocolError('unsupported blob digest algorithm');
  }
  if (handle.digest.length !== BLAKE3_DIGEST_BYTES) {
    throw new ResourceProtocolError('blake3 digest must be 32 bytes');
  }
  if (handle.length <= 0n) throw new ResourceProtocolError('invalid blob length');
  if ((handle.expiresAt ?? 0n) < 0n) throw new ResourceProtocolError('invalid blob expiry');
}

export function validateCompoundRequest(request: ResourceCompoundRequestPayload): void {
  if (request.requestId < 0n) throw new ResourceProtocolError('invalid request id');
  if (request.readOffset !== undefined && request.readOffset < 0n) {
    throw new ResourceProtocolError('invalid read offset');
  }
  if (request.readCount !== undefined && (!Number.isInteger(request.readCount) || request.readCount < 0)) {
    throw new ResourceProtocolError('invalid read count');
  }
  validatePathSegments(request.wnames);
}

export function validateCompoundResult(result: ResourceCompoundResultPayload): void {
  const data = result.data ?? new Uint8Array();
  if (data.length > RESOURCE_INLINE_LIMIT) {
    throw new ResourceProtocolError('inline result exceeds 64 KiB; return a blob handle');
  }
  if (data.length > 0 && result.blob) {
    throw new ResourceProtocolError('result cannot carry both inline data and a blob handle');
  }
  if (result.blob) validateBlobHandle(result.blob);
}

function createBlobHandle(builder: flatbuffers.Builder, handle: BlobHandlePayload): flatbuffers.Offset {
  validateBlobHandle(handle);
  const digest = BlobHandle.createDigestVector(builder, handle.digest);
  return BlobHandle.createBlobHandle(
    builder,
    handle.version ?? BLOB_HANDLE_VERSION,
    handle.algorithm ?? BlobAlgorithm.blake3,
    digest,
    handle.length,
    handle.expiresAt ?? 0n
  );
}

function createStat(
  builder: flatbuffers.Builder,
  stat: NonNullable<ResourceCompoundResultPayload['stat']>
): flatbuffers.Offset {
  const name = builder.createString(stat.name);
  ResourceStat.startResourceStat(builder);
  ResourceStat.addQid(builder, Qid.createQid(builder, stat.qid.type, stat.qid.version, stat.qid.path));
  ResourceStat.addMode(builder, stat.mode);
  ResourceStat.addLength(builder, stat.length);
  ResourceStat.addName(builder, name);
  ResourceStat.addModifiedAt(builder, stat.modifiedAt);
  return ResourceStat.endResourceStat(builder);
}

function finishRpc(
  builder: flatbuffers.Builder,
  payloadType: ResourceRpcPayload,
  payload: flatbuffers.Offset,
  opCode: ResourceOpCode
): Uint8Array {
  const rpc = ResourceRpc.createResourceRpc(builder, payloadType, payload, opCode);
  builder.finish(rpc);
  return builder.asUint8Array();
}

export function encodeCompoundRequest(request: ResourceCompoundRequestPayload): Uint8Array {
  validateCompoundRequest(request);
  const builder = new flatbuffers.Builder(1024);
  const segmentOffsets = request.wnames.map((name) => builder.createString(name));
  const wnames = ResourceCompoundRequest.createWnamesVector(builder, segmentOffsets);
  const payload = ResourceCompoundRequest.createResourceCompoundRequest(
    builder,
    request.requestId,
    request.fid,
    request.newFid,
    wnames,
    request.openMode ?? BindMode.read_only,
    request.readOffset ?? 0n,
    request.readCount ?? 0,
    request.clunk ?? true
  );
  return finishRpc(builder, ResourceRpcPayload.ResourceCompoundRequest, payload, ResourceOpCode.compound);
}

export function decodeCompoundRequest(data: Uint8Array): DecodedCompoundRequest {
  const rpc = ResourceRpc.getRootAsResourceRpc(new flatbuffers.ByteBuffer(data));
  if (rpc.opCode() !== ResourceOpCode.compound) throw new ResourceProtocolError('expected compound op code');
  if (rpc.payloadType() !== ResourceRpcPayload.ResourceCompoundRequest) {
    throw new ResourceProtocolError('expected compound request payload');
  }
  const request = rpc.payload(new ResourceCompoundRequest()) as ResourceCompoundRequest | null;
  if (!request) throw new ResourceProtocolError('missing compound request');
  const wnames: string[] = [];
  for (let i = 0; i < request.wnamesLength(); i += 1) {
    const name = request.wnames(i);
    if (typeof name !== 'string') throw new ResourceProtocolError('invalid path segment');
    wnames.push(name);
  }
  return {
    opCode: rpc.opCode(),
    request: {
      requestId: request.requestId(),
      fid: request.fid(),
      newFid: request.newFid(),
      wnames,
      openMode: request.openMode(),
      readOffset: request.readOffset(),
      readCount: request.readCount(),
      clunk: request.clunk()
    }
  };
}

export function encodeCompoundResult(result: ResourceCompoundResultPayload): Uint8Array {
  validateCompoundResult(result);
  const builder = new flatbuffers.Builder(1024);
  const data = result.data?.length ? ResourceCompoundResult.createDataVector(builder, result.data) : 0;
  const blob = result.blob ? createBlobHandle(builder, result.blob) : 0;
  const stat = result.stat ? createStat(builder, result.stat) : 0;
  const qid = result.qid ?? { type: 0, version: 0, path: 0n };
  ResourceCompoundResult.startResourceCompoundResult(builder);
  ResourceCompoundResult.addRequestId(builder, result.requestId);
  ResourceCompoundResult.addStatus(builder, result.status ?? ResourceStatus.ok);
  ResourceCompoundResult.addQid(builder, Qid.createQid(builder, qid.type, qid.version, qid.path));
  ResourceCompoundResult.addIounit(builder, result.iounit ?? RESOURCE_INLINE_LIMIT);
  if (data) ResourceCompoundResult.addData(builder, data);
  if (blob) ResourceCompoundResult.addBlob(builder, blob);
  if (stat) ResourceCompoundResult.addStat(builder, stat);
  ResourceCompoundResult.addClunkStatus(builder, result.clunkStatus ?? ResourceStatus.ok);
  const offset = ResourceCompoundResult.endResourceCompoundResult(builder);
  return finishRpc(builder, ResourceRpcPayload.ResourceCompoundResult, offset, ResourceOpCode.compound_result);
}

function decodeQid(qid: Qid): { type: number; version: number; path: bigint } {
  return { type: qid.type(), version: qid.version(), path: qid.path() };
}

function decodeBlob(handle: BlobHandle): BlobHandlePayload {
  const blob: BlobHandlePayload = {
    version: handle.version(),
    algorithm: handle.algorithm(),
    digest: new Uint8Array(handle.digestArray() ?? new Uint8Array()),
    length: handle.length(),
    expiresAt: handle.expiresAt()
  };
  validateBlobHandle(blob);
  return blob;
}

export function decodeCompoundResult(data: Uint8Array): DecodedCompoundResult {
  const rpc = ResourceRpc.getRootAsResourceRpc(new flatbuffers.ByteBuffer(data));
  if (rpc.opCode() !== ResourceOpCode.compound_result) throw new ResourceProtocolError('expected compound result op code');
  if (rpc.payloadType() !== ResourceRpcPayload.ResourceCompoundResult) {
    throw new ResourceProtocolError('expected compound result payload');
  }
  const result = rpc.payload(new ResourceCompoundResult()) as ResourceCompoundResult | null;
  if (!result) throw new ResourceProtocolError('missing compound result');
  const decodedBlob = result.blob();
  const byteData = result.dataArray();
  const payload: ResourceCompoundResultPayload = {
    requestId: result.requestId(),
    status: result.status(),
    qid: result.qid() ? decodeQid(result.qid()!) : undefined,
    iounit: result.iounit(),
    data: byteData ? new Uint8Array(byteData) : new Uint8Array(),
    blob: decodedBlob ? decodeBlob(decodedBlob) : undefined,
    clunkStatus: result.clunkStatus()
  };
  const stat = result.stat();
  if (stat) {
    const statQid = stat.qid();
    payload.stat = {
      qid: statQid ? decodeQid(statQid) : { type: 0, version: 0, path: 0n },
      mode: stat.mode(),
      length: stat.length(),
      name: stat.name() ?? '',
      modifiedAt: stat.modifiedAt()
    };
  }
  validateCompoundResult(payload);
  return { opCode: rpc.opCode(), result: payload };
}

export function encodeReadResult(data: Uint8Array, blob?: BlobHandlePayload): Uint8Array {
  if (data.length > RESOURCE_INLINE_LIMIT) throw new ResourceProtocolError('inline read result exceeds 64 KiB');
  if (data.length > 0 && blob) throw new ResourceProtocolError('read result cannot carry both data and a blob handle');
  if (blob) validateBlobHandle(blob);
  const builder = new flatbuffers.Builder(1024);
  const dataOffset = data.length ? ResourceReadResult.createDataVector(builder, data) : 0;
  const blobOffset = blob ? createBlobHandle(builder, blob) : 0;
  ResourceReadResult.startResourceReadResult(builder);
  if (dataOffset) ResourceReadResult.addData(builder, dataOffset);
  if (blobOffset) ResourceReadResult.addBlob(builder, blobOffset);
  const offset = ResourceReadResult.endResourceReadResult(builder);
  return finishRpc(builder, ResourceRpcPayload.ResourceReadResult, offset, ResourceOpCode.read_result);
}

export function decodeReadResult(data: Uint8Array): DecodedReadResult {
  const rpc = ResourceRpc.getRootAsResourceRpc(new flatbuffers.ByteBuffer(data));
  if (rpc.opCode() !== ResourceOpCode.read_result || rpc.payloadType() !== ResourceRpcPayload.ResourceReadResult) {
    throw new ResourceProtocolError('expected read result payload');
  }
  const result = rpc.payload(new ResourceReadResult()) as ResourceReadResult | null;
  if (!result) throw new ResourceProtocolError('missing read result');
  const bytes = result.dataArray();
  const inline = bytes ? new Uint8Array(bytes) : new Uint8Array();
  const blob = result.blob();
  if (inline.length > RESOURCE_INLINE_LIMIT) throw new ResourceProtocolError('inline read result exceeds 64 KiB');
  if (inline.length > 0 && blob) throw new ResourceProtocolError('read result cannot carry both data and a blob handle');
  return {
    opCode: rpc.opCode(),
    data: inline,
    blob: blob ? decodeBlob(blob) : null
  };
}
