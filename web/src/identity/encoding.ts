const TEXT_ENCODER = new TextEncoder();

export function utf8(value: string): Uint8Array {
  return TEXT_ENCODER.encode(value);
}

export function bytesToHex(bytes: Uint8Array): string {
  let value = '';
  for (const byte of bytes) value += byte.toString(16).padStart(2, '0');
  return value;
}

export function hexToBytes(value: string): Uint8Array {
  if (value.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(value)) {
    throw new Error('invalid hexadecimal value');
  }
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

export function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function base64UrlToBytes(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('invalid base64url value');
  const padded =
    value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (value.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

export function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const length = parts.reduce((total, part) => total + part.length, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

export function randomBytes(length: number, source: Crypto = crypto): Uint8Array {
  if (!Number.isSafeInteger(length) || length <= 0) throw new Error('invalid random length');
  const bytes = new Uint8Array(length);
  source.getRandomValues(bytes);
  return bytes;
}

export function randomNonce(source: Crypto = crypto): string {
  return bytesToBase64Url(randomBytes(32, source));
}

export function asBufferSource(bytes: Uint8Array): BufferSource {
  return bytes as unknown as BufferSource;
}

export async function sha256(
  bytes: Uint8Array,
  subtle: SubtleCrypto = crypto.subtle
): Promise<Uint8Array> {
  return new Uint8Array(await subtle.digest('SHA-256', asBufferSource(bytes)));
}

export function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index]! ^ right[index]!;
  }
  return difference === 0;
}
