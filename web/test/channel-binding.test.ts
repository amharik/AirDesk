import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  base64UrlToBytes,
  certificateHashChannelBinding,
  dtlsCertificateChannelBinding,
  exporterChannelBinding
} from '../src/identity';

describe('browser pairing channel bindings', () => {
  it('encodes a TLS exporter value as base64url', () => {
    const exporter = new Uint8Array(32);
    for (let index = 0; index < exporter.length; index += 1) exporter[index] = index;

    const binding = exporterChannelBinding(exporter.buffer);

    expect(binding.kind).toBe('exporter');
    expect(base64UrlToBytes(binding.value)).toEqual(exporter);
  });

  it('rejects a short TLS exporter value', () => {
    expect(() => exporterChannelBinding(new Uint8Array(15))).toThrowError(
      expect.objectContaining({ code: 'invalid-binding' })
    );
  });

  it('hashes a DER certificate with SHA-256', async () => {
    const certificate = new Uint8Array([0x30, 0x82, 0x01, 0x0a, 0x02, 0x82]);
    const expected = createHash('sha256').update(certificate).digest('hex');

    const binding = await certificateHashChannelBinding(certificate);

    expect(binding).toEqual({ kind: 'certificate-hash', value: expected });
  });

  it('rejects an empty certificate', async () => {
    await expect(certificateHashChannelBinding(new Uint8Array())).rejects.toMatchObject({
      code: 'invalid-binding'
    });
  });

  it('uses the first remote certificate from a DTLS transport', async () => {
    const certificate = new Uint8Array([0x30, 0x82, 0x02, 0x01]);
    const expected = createHash('sha256').update(certificate).digest('hex');

    const binding = await dtlsCertificateChannelBinding({
      getRemoteCertificates: () => [certificate.buffer, new Uint8Array([0x01]).buffer]
    });

    expect(binding).toEqual({ kind: 'certificate-hash', value: expected });
  });

  it('fails closed when a DTLS transport has no remote certificate', async () => {
    await expect(
      dtlsCertificateChannelBinding({ getRemoteCertificates: () => [] })
    ).rejects.toMatchObject({ code: 'missing-binding' });
  });
});
