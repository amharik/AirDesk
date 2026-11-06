export type CborMap = Map<CborValue, CborValue>;
export type CborValue =
  | null
  | boolean
  | number
  | string
  | Uint8Array
  | CborValue[]
  | CborMap;
export type CborInput =
  | null
  | boolean
  | number
  | string
  | Uint8Array
  | readonly CborInput[]
  | { readonly [key: string]: CborInput }
  | ReadonlyMap<CborInput, CborInput>;

export type CborErrorCode = 'unsupported-value' | 'malformed-cbor' | 'too-large';

export class CborError extends Error {
  readonly code: CborErrorCode;

  constructor(code: CborErrorCode, message: string) {
    super(message);
    this.name = 'CborError';
    this.code = code;
  }
}

const MAX_BYTES = 16_384;
const MAX_DEPTH = 32;
const MAX_ITEMS = 4_096;
const TEXT_DECODER = new TextDecoder('utf-8', { fatal: true });

function fail(message: string): never {
  throw new CborError('malformed-cbor', message);
}

function encodeHead(major: number, length: number, out: number[]): void {
  if (!Number.isSafeInteger(length) || length < 0) {
    throw new CborError('unsupported-value', 'invalid CBOR length');
  }
  const prefix = major << 5;
  if (length < 24) {
    out.push(prefix | length);
  } else if (length <= 0xff) {
    out.push(prefix | 24, length);
  } else if (length <= 0xffff) {
    out.push(prefix | 25, length >> 8, length & 0xff);
  } else if (length <= 0xffffffff) {
    out.push(
      prefix | 26,
      (length >>> 24) & 0xff,
      (length >>> 16) & 0xff,
      (length >>> 8) & 0xff,
      length & 0xff
    );
  } else {
    const big = BigInt(length);
    out.push(prefix | 27);
    for (let shift = 56n; shift >= 0n; shift -= 8n) {
      out.push(Number((big >> shift) & 0xffn));
    }
  }
}

function encodeValue(value: CborInput, out: number[], depth: number): void {
  if (depth > MAX_DEPTH) throw new CborError('too-large', 'CBOR nesting is too deep');
  if (value === null) {
    out.push(0xf6);
    return;
  }
  if (value === false) {
    out.push(0xf4);
    return;
  }
  if (value === true) {
    out.push(0xf5);
    return;
  }
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) {
      throw new CborError('unsupported-value', 'CBOR integers must be safe integers');
    }
    if (value >= 0) {
      encodeHead(0, value, out);
    } else {
      encodeHead(1, -1 - value, out);
    }
    return;
  }
  if (typeof value === 'string') {
    const bytes = new TextEncoder().encode(value);
    encodeHead(3, bytes.length, out);
    for (const byte of bytes) out.push(byte);
    return;
  }
  if (value instanceof Uint8Array) {
    encodeHead(2, value.length, out);
    for (const byte of value) out.push(byte);
    return;
  }
  if (Array.isArray(value)) {
    if (value.length > MAX_ITEMS) throw new CborError('too-large', 'CBOR array is too large');
    encodeHead(4, value.length, out);
    for (const item of value) encodeValue(item, out, depth + 1);
    return;
  }
  if (value instanceof Map) {
    if (value.size > MAX_ITEMS) throw new CborError('too-large', 'CBOR map is too large');
    encodeHead(5, value.size, out);
    for (const [key, item] of value) {
      encodeValue(key, out, depth + 1);
      encodeValue(item, out, depth + 1);
    }
    return;
  }
  if (typeof value === 'object') {
    const entries = Object.entries(value);
    if (entries.length > MAX_ITEMS) throw new CborError('too-large', 'CBOR map is too large');
    encodeHead(5, entries.length, out);
    for (const [key, item] of entries) {
      if (item === undefined) {
        throw new CborError('unsupported-value', 'CBOR object values must be defined');
      }
      encodeValue(key, out, depth + 1);
      encodeValue(item, out, depth + 1);
    }
    return;
  }
  throw new CborError('unsupported-value', 'unsupported CBOR value');
}

export function encodeCbor(value: CborInput): Uint8Array {
  const out: number[] = [];
  encodeValue(value, out, 0);
  if (out.length > MAX_BYTES) throw new CborError('too-large', 'CBOR value is too large');
  return new Uint8Array(out);
}

class Reader {
  readonly bytes: Uint8Array;
  offset: number;
  items = 0;

  constructor(bytes: Uint8Array, offset: number) {
    this.bytes = bytes;
    this.offset = offset;
  }

  readByte(): number {
    if (this.offset >= this.bytes.length) fail('truncated CBOR value');
    return this.bytes[this.offset++]!;
  }

  readLength(additional: number): number {
    if (additional < 24) return additional;
    if (additional === 24) return this.readByte();
    if (additional === 25) {
      return (this.readByte() << 8) | this.readByte();
    }
    if (additional === 26) {
      return (
        (this.readByte() * 0x1000000) +
        (this.readByte() << 16) +
        (this.readByte() << 8) +
        this.readByte()
      );
    }
    if (additional === 27) {
      let value = 0;
      for (let index = 0; index < 8; index += 1) {
        value = value * 256 + this.readByte();
      }
      if (!Number.isSafeInteger(value)) fail('CBOR integer is too large');
      return value;
    }
    fail('unsupported CBOR length');
  }

  readValue(depth: number): CborValue {
    if (depth > MAX_DEPTH) throw new CborError('too-large', 'CBOR nesting is too deep');
    this.items += 1;
    if (this.items > MAX_ITEMS) throw new CborError('too-large', 'CBOR item count is too large');

    const initial = this.readByte();
    const major = initial >> 5;
    const additional = initial & 0x1f;

    if (major === 7) {
      if (additional === 20) return false;
      if (additional === 21) return true;
      if (additional === 22) return null;
      fail('unsupported CBOR simple value');
    }

    const length = this.readLength(additional);

    switch (major) {
      case 0:
        return length;
      case 1:
        if (length > Number.MAX_SAFE_INTEGER) fail('CBOR negative integer is too large');
        return -1 - length;
      case 2: {
        if (this.offset + length > this.bytes.length) fail('truncated CBOR bytes');
        const value = this.bytes.slice(this.offset, this.offset + length);
        this.offset += length;
        return value;
      }
      case 3: {
        if (this.offset + length > this.bytes.length) fail('truncated CBOR text');
        const value = this.bytes.slice(this.offset, this.offset + length);
        this.offset += length;
        try {
          return TEXT_DECODER.decode(value);
        } catch {
          fail('invalid UTF-8 in CBOR text');
        }
        break;
      }
      case 4: {
        if (length > MAX_ITEMS) throw new CborError('too-large', 'CBOR array is too large');
        const values: CborValue[] = [];
        for (let index = 0; index < length; index += 1) {
          values.push(this.readValue(depth + 1));
        }
        return values;
      }
      case 5: {
        if (length > MAX_ITEMS) throw new CborError('too-large', 'CBOR map is too large');
        const values: CborMap = new Map();
        const seen = new Set<string>();
        for (let index = 0; index < length; index += 1) {
          const key = this.readValue(depth + 1);
          let keyId: string;
          if (typeof key === 'string') keyId = `s:${key}`;
          else if (typeof key === 'number' && Number.isSafeInteger(key)) keyId = `n:${key}`;
          else fail('CBOR map keys must be text or integers');
          if (seen.has(keyId)) fail('duplicate CBOR map key');
          seen.add(keyId);
          values.set(key, this.readValue(depth + 1));
        }
        return values;
      }
      default:
        fail('unsupported CBOR tag');
    }
  }
}

export function decodeCborAt(
  bytes: Uint8Array,
  offset = 0
): { value: CborValue; next: number } {
  if (bytes.length > MAX_BYTES) throw new CborError('too-large', 'CBOR value is too large');
  if (!Number.isSafeInteger(offset) || offset < 0 || offset >= bytes.length) {
    fail('invalid CBOR offset');
  }
  const reader = new Reader(bytes, offset);
  const value = reader.readValue(0);
  return { value, next: reader.offset };
}

export function decodeCbor(bytes: Uint8Array): CborValue {
  const { value, next } = decodeCborAt(bytes);
  if (next !== bytes.length) fail('trailing CBOR bytes');
  return value;
}
