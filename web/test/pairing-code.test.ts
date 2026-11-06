import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  PAIRING_CODE_PREFIX,
  NonceReplayGuard,
  PairingCodeError,
  PairingPinAttemptGuard,
  Spake2PlusSession,
  bytesToBase64Url,
  createPairingPinChallenge,
  createPairingQrSecretChallenge,
  derivePairingCodeRegistration,
  parsePairingCode,
  serializePairingCode,
  utf8
} from '../src/identity';
import type { PairingPayload } from '../src/identity';

const fixture = JSON.parse(
  readFileSync(new URL('./fixtures/ad-pair-1.json', import.meta.url), 'utf8')
) as {
  now: number;
  offer: PairingPayload;
  response: PairingPayload;
  responder: { deviceId: string };
};

function offer(): PairingPayload {
  return structuredClone(fixture.offer);
}

function source(fill: number): Crypto {
  return {
    getRandomValues<T extends ArrayBufferView | null>(bytes: T): T {
      if (bytes) new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength).fill(fill);
      return bytes;
    }
  } as Crypto;
}

function encode(value: unknown): string {
  return `${PAIRING_CODE_PREFIX}${bytesToBase64Url(utf8(JSON.stringify(value)))}`;
}

async function failureCode(action: () => unknown): Promise<string> {
  try {
    await action();
  } catch (error) {
    if (error instanceof PairingCodeError) return error.code;
    throw error;
  }
  throw new Error('expected pairing code failure');
}

describe('AD-PAIR-1 QR code envelope', () => {
  it('round-trips a PIN challenge without putting the PIN in the QR code', async () => {
    const challenge = createPairingPinChallenge(offer(), {
      now: fixture.now,
      cryptoSource: source(0)
    });
    const parsed = parsePairingCode(challenge.serialized, { now: fixture.now });

    expect(challenge.pin).toBe('000000');
    expect(parsed.mode).toBe('pin');
    expect(parsed.secret).toBeUndefined();
    expect(parsed.offer).toEqual(fixture.offer);
    expect(parsed.salt).toBe(challenge.code.salt);
    expect(challenge.serialized).not.toContain('000000');
    expect(parsePairingCode(serializePairingCode(parsed), { now: fixture.now })).toEqual(parsed);
    await expect(
      derivePairingCodeRegistration({
        code: parsed,
        pin: '000000',
        initiatorDeviceId: fixture.responder.deviceId,
        responderDeviceId: fixture.offer.deviceId
      })
    ).resolves.toMatchObject({ salt: expect.any(Uint8Array) });
  });

  it('round-trips a QR-secret challenge', () => {
    const challenge = createPairingQrSecretChallenge(offer(), {
      now: fixture.now,
      cryptoSource: source(7)
    });
    const parsed = parsePairingCode(challenge.serialized, { now: fixture.now });

    expect(challenge.secret).toHaveLength(32);
    expect(parsed.mode).toBe('qr-secret');
    expect(parsed.secret).toBe(challenge.code.secret);
    expect(challenge.serialized).not.toContain(bytesToBase64Url(utf8('000000')));
  });

  it('rejects malformed, unknown, unsupported, expired and replayed codes', () => {
    const challenge = createPairingPinChallenge(offer(), {
      now: fixture.now,
      cryptoSource: source(1)
    });
    const parsed = parsePairingCode(challenge.serialized, { now: fixture.now });

    expect(() => parsePairingCode('not-a-code')).toThrowError(
      expect.objectContaining({ code: 'invalid-code' })
    );
    expect(() => parsePairingCode(`${PAIRING_CODE_PREFIX}!`)).toThrowError(
      expect.objectContaining({ code: 'malformed-code' })
    );
    expect(() => parsePairingCode(encode({ ...parsed, extra: true }))).toThrowError(
      expect.objectContaining({ code: 'unknown-field' })
    );
    expect(() => parsePairingCode(encode({ ...parsed, version: 2 }))).toThrowError(
      expect.objectContaining({ code: 'unsupported-code-version' })
    );
    expect(() => parsePairingCode(encode({ ...parsed, mode: 'other' }))).toThrowError(
      expect.objectContaining({ code: 'invalid-mode' })
    );
    expect(() =>
      parsePairingCode(challenge.serialized, { now: fixture.offer.expiresAt })
    ).toThrowError(expect.objectContaining({ code: 'expired-code' }));

    const guard = new NonceReplayGuard({ now: () => fixture.now });
    parsePairingCode(challenge.serialized, {
      now: fixture.now,
      replayGuard: guard
    });
    expect(() =>
      parsePairingCode(challenge.serialized, {
        now: fixture.now,
        replayGuard: guard
      })
    ).toThrowError(expect.objectContaining({ code: 'replayed-nonce' }));
  });
});

describe('AD-PAIR-1 PIN/QR registration', () => {
  it('derives the same registration on both devices and binds PIN, salt and identities', async () => {
    const challenge = createPairingPinChallenge(offer(), {
      now: fixture.now,
      cryptoSource: source(1)
    });
    const parsed = parsePairingCode(challenge.serialized, { now: fixture.now });
    const input = {
      code: parsed,
      pin: challenge.pin!,
      initiatorDeviceId: fixture.responder.deviceId,
      responderDeviceId: fixture.offer.deviceId
    };

    const host = await derivePairingCodeRegistration(input);
    const controller = await derivePairingCodeRegistration(input);
    const wrongPin = await derivePairingCodeRegistration({ ...input, pin: '999999' });
    const wrongIdentity = await derivePairingCodeRegistration({
      ...input,
      initiatorDeviceId: fixture.offer.deviceId,
      responderDeviceId: fixture.response.deviceId
    });

    expect(Buffer.from(host.w0).equals(Buffer.from(controller.w0))).toBe(true);
    expect(Buffer.from(host.w1).equals(Buffer.from(controller.w1))).toBe(true);
    expect(Buffer.from(host.L).equals(Buffer.from(controller.L))).toBe(true);
    expect(Buffer.from(host.w0).equals(Buffer.from(wrongPin.w0))).toBe(false);
    expect(Buffer.from(host.w1).equals(Buffer.from(wrongIdentity.w1))).toBe(false);
  });

  it('derives a QR-secret registration without a PIN', async () => {
    const challenge = createPairingQrSecretChallenge(offer(), {
      now: fixture.now,
      cryptoSource: source(9)
    });
    const parsed = parsePairingCode(challenge.serialized, { now: fixture.now });
    const registration = await derivePairingCodeRegistration({
      code: parsed,
      initiatorDeviceId: fixture.responder.deviceId,
      responderDeviceId: fixture.offer.deviceId
    });

    expect(registration.L).toHaveLength(65);
    expect(registration.w0).toHaveLength(32);
    expect(registration.w1).toHaveLength(32);
  });

  it('rejects a missing or malformed PIN and PIN codes that carry a secret', async () => {
    const challenge = createPairingPinChallenge(offer(), {
      now: fixture.now,
      cryptoSource: source(2)
    });
    const parsed = parsePairingCode(challenge.serialized, { now: fixture.now });

    expect(
      await failureCode(() =>
        derivePairingCodeRegistration({
          code: parsed,
          pin: '12345',
          initiatorDeviceId: fixture.responder.deviceId,
          responderDeviceId: fixture.offer.deviceId
        })
      )
    ).toBe('invalid-pin');
    expect(
      await failureCode(() =>
        derivePairingCodeRegistration({
          code: { ...parsed, secret: parsed.salt },
          pin: challenge.pin,
          initiatorDeviceId: fixture.responder.deviceId,
          responderDeviceId: fixture.offer.deviceId
        })
      )
    ).toBe('invalid-secret');
  });

  it('feeds a password-derived SPAKE2+ exchange', async () => {
    const challenge = createPairingPinChallenge(offer(), {
      now: fixture.now,
      cryptoSource: source(3)
    });
    const parsed = parsePairingCode(challenge.serialized, { now: fixture.now });
    const registration = await derivePairingCodeRegistration({
      code: parsed,
      pin: challenge.pin,
      initiatorDeviceId: fixture.responder.deviceId,
      responderDeviceId: fixture.offer.deviceId
    });
    const prover = new Spake2PlusSession({
      role: 'prover',
      context: 'AD-PAIR-1',
      idProver: fixture.responder.deviceId,
      idVerifier: fixture.offer.deviceId,
      w0: registration.w0,
      w1: registration.w1
    });
    const verifier = new Spake2PlusSession({
      role: 'verifier',
      context: 'AD-PAIR-1',
      idProver: fixture.responder.deviceId,
      idVerifier: fixture.offer.deviceId,
      w0: registration.w0,
      L: registration.L
    });

    const response = await verifier.verifierRespond(prover.proverStart());
    const proverResult = await prover.proverFinish(response.share, response.confirmation);
    const verifierResult = await verifier.verifierFinish(proverResult.confirmation);

    expect(verifierResult.exchange).toEqual(proverResult.exchange);
  });
});

describe('AD-PAIR-1 PIN attempt guard', () => {
  it('locks after the configured failures and clears on success or expiry', () => {
    let now = fixture.now;
    const guard = new PairingPinAttemptGuard({ maxAttempts: 3, now: () => now });
    const expiresAt = fixture.offer.expiresAt;

    guard.assertAllowed('nonce', expiresAt);
    expect(guard.recordFailure('nonce', expiresAt)).toBe(2);
    expect(guard.recordFailure('nonce', expiresAt)).toBe(1);
    expect(guard.recordFailure('nonce', expiresAt)).toBe(0);
    expect(() => guard.assertAllowed('nonce', expiresAt)).toThrowError(
      expect.objectContaining({ code: 'pin-locked' })
    );

    guard.reset('nonce');
    guard.assertAllowed('nonce', expiresAt);
    guard.recordFailure('nonce', expiresAt);
    guard.recordSuccess('nonce');
    guard.assertAllowed('nonce', expiresAt);

    now = expiresAt;
    expect(() => guard.assertAllowed('nonce', expiresAt)).toThrowError(
      expect.objectContaining({ code: 'expired-code' })
    );
  });
});
