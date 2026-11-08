import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  base64UrlToBytes,
  certificateHashChannelBinding,
  dtlsCertificateChannelBinding,
  dtlsFingerprintChannelBinding,
  exporterChannelBinding,
  webTransportHashChannelBinding
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

  it('uses a configured WebTransport server certificate hash', () => {
    const hash = new Uint8Array(32);
    for (let index = 0; index < hash.length; index += 1) hash[index] = index;

    const binding = webTransportHashChannelBinding([{ algorithm: 'sha-256', value: hash }]);

    expect(binding).toEqual({
      kind: 'certificate-hash',
      value: '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'
    });
  });

  it('fails closed when WebTransport has no server certificate hash', () => {
    expect(() => webTransportHashChannelBinding([])).toThrowError(
      expect.objectContaining({ code: 'missing-binding' })
    );
  });

  it('rejects ambiguous WebTransport certificate hashes', () => {
    const hash = new Uint8Array(32);
    expect(() =>
      webTransportHashChannelBinding([
        { algorithm: 'sha-256', value: hash },
        { algorithm: 'sha-256', value: hash }
      ])
    ).toThrowError(expect.objectContaining({ code: 'invalid-binding' }));
  });

  it('rejects non-SHA-256 or malformed WebTransport hashes', () => {
    expect(() =>
      webTransportHashChannelBinding([{ algorithm: 'sha-512', value: new Uint8Array(32) }])
    ).toThrowError(expect.objectContaining({ code: 'invalid-binding' }));
    expect(() =>
      webTransportHashChannelBinding([{ algorithm: 'sha-256', value: new Uint8Array(31) }])
    ).toThrowError(expect.objectContaining({ code: 'invalid-binding' }));
  });
});

describe('DTLS SDP fingerprints', () => {
  const hex = 'ab'.repeat(32);
  const colon = hex.match(/../g)!.join(':');

  it('maps the SDP SHA-256 fingerprint to a certificate-hash binding', () => {
    const sdp = [
      'v=0',
      'a=fingerprint:sha-256 ' + colon.toUpperCase(),
      'a=fingerprint:sha-256 ' + colon,
      'a=setup:actpass'
    ].join('\r\n');

    expect(dtlsFingerprintChannelBinding(sdp)).toEqual({
      kind: 'certificate-hash',
      value: hex
    });
  });

  it('rejects missing, malformed and unsupported fingerprints', () => {
    expect(() => dtlsFingerprintChannelBinding('v=0\r\n')).toThrowError(
      expect.objectContaining({ code: 'missing-binding' })
    );
    expect(() =>
      dtlsFingerprintChannelBinding('a=fingerprint:sha-256 aa:bb\r\n')
    ).toThrowError(expect.objectContaining({ code: 'invalid-binding' }));
    expect(() =>
      dtlsFingerprintChannelBinding(`a=fingerprint:sha-384 ${colon}\r\n`)
    ).toThrowError(expect.objectContaining({ code: 'invalid-binding' }));
  });

  it('rejects conflicting fingerprints in one SDP', () => {
    const other = 'cd'.repeat(32).match(/../g)!.join(':');
    const sdp = `a=fingerprint:sha-256 ${colon}\r\na=fingerprint:sha-256 ${other}\r\n`;
    expect(() => dtlsFingerprintChannelBinding(sdp)).toThrowError(
      expect.objectContaining({ code: 'invalid-binding' })
    );
  });
});
