import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  BLOB_HANDLE_VERSION,
  BlobAlgorithm,
  RESOURCE_INLINE_LIMIT,
  ResourceProtocolError,
  decodeCompoundRequest,
  decodeCompoundResult,
  decodeReadResult,
  encodeCompoundRequest,
  encodeCompoundResult,
  encodeReadResult,
  validateBlobHandle
} from '../src/protocol/resource';

interface QidFixture {
  type: number;
  version: number;
  path: string;
}

interface CompoundRequestFixture {
  requestId: string;
  fid: number;
  newFid: number;
  wnames: string[];
  openMode: string;
  readOffset: string;
  readCount: number;
  clunk: boolean;
  hex: string;
}

interface BlobFixture {
  version: number;
  algorithm: string;
  digestHex: string;
  length: string;
  expiresAt: string;
  hex: string;
}

interface CompoundResultFixture {
  requestId: string;
  status: string;
  qid: QidFixture;
  iounit: number;
  dataHex?: string;
  blob?: BlobFixture;
  clunkStatus: string;
  stat?: {
    qid: QidFixture;
    mode: number;
    length: string;
    name: string;
    modifiedAt: string;
  };
  hex: string;
}

interface CompoundFixture {
  inlineLimitBytes: number;
  request: CompoundRequestFixture;
  result: CompoundResultFixture;
  blobResult: CompoundResultFixture;
  invalid: Array<{ name: string; dataBytes?: number; digestBytes?: number; expectedError: string }>;
}

interface BlobFileFixture {
  inlineLimitBytes: number;
  blob: BlobFixture;
  smallRead: { dataHex: string; hex: string };
  invalid: Array<{ name: string; dataBytes?: number; algorithm?: number; expectedError: string }>;
}

const fixtures = join(process.cwd(), '..', 'protocol', 'fixtures');
const compound = JSON.parse(
  readFileSync(join(fixtures, 'resource-compound', 'walk-open-read-clunk-v1.json'), 'utf8')
) as CompoundFixture;
const blobFile = JSON.parse(
  readFileSync(join(fixtures, 'resource-blob', 'blake3-handle-v1.json'), 'utf8')
) as BlobFileFixture;

function bytesFromHex(value: string): Uint8Array {
  return Uint8Array.from(Buffer.from(value, 'hex'));
}

function hexFromBytes(value: Uint8Array): string {
  return Buffer.from(value).toString('hex');
}

function fixtureEntry<T>(values: T[], index: number): T {
  const value = values[index];
  if (value === undefined) throw new Error(`missing fixture entry ${index}`);
  return value;
}

function blobPayload(source: BlobFixture) {
  return {
    version: source.version,
    algorithm: BlobAlgorithm.blake3,
    digest: bytesFromHex(source.digestHex),
    length: BigInt(source.length),
    expiresAt: BigInt(source.expiresAt)
  };
}

describe('ADFP resource compound and blob fixtures', () => {
  it('decodes and re-encodes the compound walk/open/read/clunk request', () => {
    const decoded = decodeCompoundRequest(bytesFromHex(compound.request.hex));
    expect(decoded.request.requestId).toBe(BigInt(compound.request.requestId));
    expect(decoded.request.fid).toBe(compound.request.fid);
    expect(decoded.request.newFid).toBe(compound.request.newFid);
    expect(decoded.request.wnames).toEqual(compound.request.wnames);
    expect(decoded.request.readOffset).toBe(BigInt(compound.request.readOffset));
    expect(decoded.request.readCount).toBe(compound.request.readCount);
    expect(decoded.request.clunk).toBe(compound.request.clunk);
    expect(hexFromBytes(encodeCompoundRequest(decoded.request))).toBe(compound.request.hex);
  });

  it('decodes and re-encodes an inline compound result', () => {
    const decoded = decodeCompoundResult(bytesFromHex(compound.result.hex));
    expect(decoded.result.requestId).toBe(BigInt(compound.result.requestId));
    expect(decoded.result.qid?.path).toBe(BigInt(compound.result.qid.path));
    expect(hexFromBytes(decoded.result.data ?? new Uint8Array())).toBe(compound.result.dataHex);
    expect(decoded.result.stat?.name).toBe(compound.result.stat?.name);
    expect(decoded.result.blob).toBeUndefined();
    expect(hexFromBytes(encodeCompoundResult(decoded.result))).toBe(compound.result.hex);
  });

  it('returns a versioned BLAKE3 handle for large compound results', () => {
    const decoded = decodeCompoundResult(bytesFromHex(compound.blobResult.hex));
    expect(decoded.result.data).toEqual(new Uint8Array());
    expect(decoded.result.blob?.version).toBe(BLOB_HANDLE_VERSION);
    expect(decoded.result.blob?.algorithm).toBe(BlobAlgorithm.blake3);
    expect(decoded.result.blob?.digest).toHaveLength(32);
    expect(decoded.result.blob?.length).toBe(131072n);
    expect(hexFromBytes(encodeCompoundResult(decoded.result))).toBe(compound.blobResult.hex);
  });

  it('decodes and re-encodes standalone read results with and without a blob handle', () => {
    const large = decodeReadResult(bytesFromHex(blobFile.blob.hex));
    expect(large.data).toEqual(new Uint8Array());
    expect(large.blob?.length).toBe(131072n);
    expect(hexFromBytes(encodeReadResult(large.data, large.blob ?? undefined))).toBe(blobFile.blob.hex);

    const small = decodeReadResult(bytesFromHex(blobFile.smallRead.hex));
    expect(hexFromBytes(small.data)).toBe(blobFile.smallRead.dataHex);
    expect(small.blob).toBeNull();
    expect(hexFromBytes(encodeReadResult(small.data))).toBe(blobFile.smallRead.hex);
  });

  it('rejects oversized inline results and ambiguous data/blob payloads', () => {
    const digest = bytesFromHex(blobFile.blob.digestHex);
    expect(() =>
      encodeCompoundResult({
        requestId: 1n,
        data: new Uint8Array(RESOURCE_INLINE_LIMIT + 1)
      })
    ).toThrow(fixtureEntry(compound.invalid, 0).expectedError);

    expect(() =>
      encodeCompoundResult({
        requestId: 1n,
        data: new Uint8Array(1),
        blob: blobPayload(blobFile.blob)
      })
    ).toThrow(fixtureEntry(compound.invalid, 1).expectedError);

    expect(() => validateBlobHandle({ digest: digest.slice(1), length: 1n })).toThrow(
      fixtureEntry(compound.invalid, 2).expectedError
    );

    expect(() => encodeReadResult(new Uint8Array(RESOURCE_INLINE_LIMIT + 1))).toThrow(
      fixtureEntry(blobFile.invalid, 0).expectedError
    );
    expect(() =>
      encodeReadResult(new Uint8Array(1), blobPayload(blobFile.blob))
    ).toThrow(fixtureEntry(blobFile.invalid, 1).expectedError);
    expect(() =>
      validateBlobHandle({
        algorithm: 9 as BlobAlgorithm,
        digest,
        length: 131072n
      })
    ).toThrow(fixtureEntry(blobFile.invalid, 2).expectedError);
  });

  it('rejects unsafe or oversized path segments', () => {
    expect(() =>
      encodeCompoundRequest({ requestId: 1n, fid: 1, newFid: 2, wnames: ['..'] })
    ).toThrow(ResourceProtocolError);
    expect(() =>
      encodeCompoundRequest({ requestId: 1n, fid: 1, newFid: 2, wnames: ['a/b'] })
    ).toThrow(ResourceProtocolError);
    expect(() =>
      encodeCompoundRequest({
        requestId: 1n,
        fid: 1,
        newFid: 2,
        wnames: new Array(33).fill('x')
      })
    ).toThrow(ResourceProtocolError);
  });
});
