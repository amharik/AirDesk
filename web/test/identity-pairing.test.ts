import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  AdPairSession,
  DeviceRegistry,
  MemoryKeyStore,
  NonceReplayGuard,
  PairingValidationError,
  base64UrlToBytes,
  bytesToBase64Url,
  bytesToHex,
  canonicalPairingTranscript,
  computePairingTranscriptHash,
  deriveAdPairSessionKeys,
  hexToBytes,
  importBrowserIdentity,
  signPairingTranscript,
  utf8,
  validatePairingPayload
} from '../src/identity';
import type {
  BrowserDeviceIdentity,
  DeviceIdentityAlgorithm,
  PairingChannelBinding,
  PairingPayload,
  Spake2PlusExchangeResult,
  Spake2PlusPrimitive
} from '../src/identity';

interface FixtureIdentity {
  algorithm: DeviceIdentityAlgorithm;
  privateKeyPkcs8: string;
  publicKeySpki: string;
  deviceId: string;
}

interface AdPairFixture {
  version: number;
  now: number;
  binding: PairingChannelBinding;
  initiator: FixtureIdentity;
  responder: FixtureIdentity;
  offer: PairingPayload;
  response: PairingPayload;
  pake: Spake2PlusExchangeResult;
  pakeSecret: string;
  password: string;
  tamper: {
    binding: PairingChannelBinding;
    capability: string;
    invalidSignature: string;
  };
  expected: {
    transcript: string;
    transcriptHash: string;
    shortAuthenticationString: string;
    signatures: { initiator: string; responder: string };
    sessionKeys: {
      version: number;
      initiatorToResponder: string;
      responderToInitiator: string;
      transport: string;
    };
  };
}

const fixture = JSON.parse(
  readFileSync(new URL('./fixtures/ad-pair-1.json', import.meta.url), 'utf8')
) as AdPairFixture;

async function loadIdentity(material: FixtureIdentity): Promise<BrowserDeviceIdentity> {
  return importBrowserIdentity(
    {
      algorithm: material.algorithm,
      privateKeyPkcs8: base64UrlToBytes(material.privateKeyPkcs8),
      publicKeySpki: base64UrlToBytes(material.publicKeySpki)
    },
    { store: new MemoryKeyStore(), now: () => fixture.now }
  );
}

const fakePake: Spake2PlusPrimitive = {
  suite: 'SPAKE2+-P256-SHA256',
  async exchange() {
    return fixture.pake;
  }
};

function clone<T>(value: T): T {
  return structuredClone(value);
}

async function startSession(
  offer: PairingPayload = clone(fixture.offer),
  response: PairingPayload = clone(fixture.response),
  options: {
    registry?: DeviceRegistry;
    initiatorVerifier?: BrowserDeviceIdentity;
    responderVerifier?: BrowserDeviceIdentity;
  } = {}
): Promise<{
  session: AdPairSession;
  initiator: BrowserDeviceIdentity;
  responder: BrowserDeviceIdentity;
}> {
  const initiator = await loadIdentity(fixture.initiator);
  const responder = await loadIdentity(fixture.responder);
  const session = new AdPairSession({
    pake: fakePake,
    now: () => fixture.now,
    initiatorVerifier: options.initiatorVerifier ?? initiator,
    responderVerifier: options.responderVerifier ?? responder,
    ...(options.registry ? { registry: options.registry } : {})
  });
  session.acceptOffer(offer);
  session.acceptResponse(response);
  return { session, initiator, responder };
}

function expectedSignatures(): {
  initiatorSignature: Uint8Array;
  responderSignature: Uint8Array;
} {
  return {
    initiatorSignature: base64UrlToBytes(fixture.expected.signatures.initiator),
    responderSignature: base64UrlToBytes(fixture.expected.signatures.responder)
  };
}

async function failureCode(action: () => unknown): Promise<string> {
  try {
    await action();
  } catch (error) {
    if (error instanceof PairingValidationError) return error.code;
    throw error;
  }
  throw new Error('expected pairing failure');
}

describe('AD-PAIR-1 deterministic fixture', () => {
  it('reproduces the canonical transcript, SAS, signatures and session keys', async () => {
    const { session, initiator, responder } = await startSession();
    const result = await session.finish({
      secret: utf8(fixture.password),
      ...expectedSignatures()
    });

    expect(bytesToHex(result.transcript)).toBe(fixture.expected.transcript);
    expect(bytesToHex(result.transcriptHash)).toBe(fixture.expected.transcriptHash);
    expect(result.shortAuthenticationString).toBe(
      fixture.expected.shortAuthenticationString
    );
    expect(bytesToBase64Url(result.signatures.initiator)).toBe(
      fixture.expected.signatures.initiator
    );
    expect(bytesToBase64Url(result.signatures.responder)).toBe(
      fixture.expected.signatures.responder
    );
    expect(result.channelBinding).toEqual(fixture.binding);
    expect(result.keyScheduleVersion).toBe(1);
    expect(result.sessionKeys.version).toBe(fixture.expected.sessionKeys.version);
    expect(bytesToHex(result.sessionKeys.initiatorToResponder.bytes)).toBe(
      fixture.expected.sessionKeys.initiatorToResponder
    );
    expect(bytesToHex(result.sessionKeys.responderToInitiator.bytes)).toBe(
      fixture.expected.sessionKeys.responderToInitiator
    );
    expect(bytesToHex(result.sessionKeys.transport.bytes)).toBe(
      fixture.expected.sessionKeys.transport
    );

    await expect(
      initiator.verify(result.transcript, result.signatures.initiator)
    ).resolves.toBe(true);
    await expect(
      responder.verify(result.transcript, result.signatures.responder)
    ).resolves.toBe(true);
  });

  it('binds session keys to the PAKE secret, transcript hash and channel binding', async () => {
    const keys = await deriveAdPairSessionKeys({
      pakeSharedSecret: base64UrlToBytes(fixture.pakeSecret),
      transcriptHash: hexToBytes(fixture.expected.transcriptHash),
      channelBinding: fixture.binding
    });
    expect(bytesToHex(keys.initiatorToResponder.bytes)).toBe(
      fixture.expected.sessionKeys.initiatorToResponder
    );
    expect(bytesToHex(keys.responderToInitiator.bytes)).toBe(
      fixture.expected.sessionKeys.responderToInitiator
    );
    expect(bytesToHex(keys.transport.bytes)).toBe(fixture.expected.sessionKeys.transport);

    const changedBinding = await deriveAdPairSessionKeys({
      pakeSharedSecret: base64UrlToBytes(fixture.pakeSecret),
      transcriptHash: hexToBytes(fixture.expected.transcriptHash),
      channelBinding: fixture.tamper.binding
    });
    const changedSecret = await deriveAdPairSessionKeys({
      pakeSharedSecret: new Uint8Array(32).fill(12),
      transcriptHash: hexToBytes(fixture.expected.transcriptHash),
      channelBinding: fixture.binding
    });
    const changedTranscript = await deriveAdPairSessionKeys({
      pakeSharedSecret: base64UrlToBytes(fixture.pakeSecret),
      transcriptHash: new Uint8Array(32).fill(13),
      channelBinding: fixture.binding
    });

    expect(bytesToHex(changedBinding.transport.bytes)).not.toBe(
      fixture.expected.sessionKeys.transport
    );
    expect(bytesToHex(changedSecret.transport.bytes)).not.toBe(
      fixture.expected.sessionKeys.transport
    );
    expect(bytesToHex(changedTranscript.transport.bytes)).not.toBe(
      fixture.expected.sessionKeys.transport
    );
  });
});

describe('AD-PAIR-1 long-term signatures', () => {
  it('rejects missing signatures', async () => {
    const { session } = await startSession();
    expect(
      await failureCode(() =>
        session.finish({
          secret: utf8(fixture.password),
          initiatorSignature: expectedSignatures().initiatorSignature
        })
      )
    ).toBe('missing-signature');
  });

  it('rejects invalid and swapped signatures', async () => {
    const first = await startSession();
    expect(
      await failureCode(() =>
        first.session.finish({
          secret: utf8(fixture.password),
          initiatorSignature: base64UrlToBytes(fixture.tamper.invalidSignature),
          responderSignature: expectedSignatures().responderSignature
        })
      )
    ).toBe('invalid-signature');

    const second = await startSession();
    const signatures = expectedSignatures();
    expect(
      await failureCode(() =>
        second.session.finish({
          secret: utf8(fixture.password),
          initiatorSignature: signatures.responderSignature,
          responderSignature: signatures.initiatorSignature
        })
      )
    ).toBe('invalid-signature');
  });

  it('rejects a verifier that does not match the payload identity', async () => {
    const initiator = await loadIdentity(fixture.initiator);
    const responder = await loadIdentity(fixture.responder);
    const session = new AdPairSession({
      pake: fakePake,
      now: () => fixture.now,
      initiatorVerifier: responder,
      responderVerifier: responder
    });
    session.acceptOffer(clone(fixture.offer));
    session.acceptResponse(clone(fixture.response));

    expect(
      await failureCode(() =>
        session.finish({ secret: utf8(fixture.password), ...expectedSignatures() })
      )
    ).toBe('signature-device-mismatch');
    expect(initiator.deviceId).not.toBe(responder.deviceId);
  });

  it('rejects a payload device id that does not match its public key even with a spoofed verifier', async () => {
    const initiator = await loadIdentity(fixture.initiator);
    const responder = await loadIdentity(fixture.responder);
    const offer = clone(fixture.offer);
    offer.deviceId = responder.deviceId;
    const spoofedVerifier = {
      deviceId: offer.deviceId,
      algorithm: initiator.algorithm,
      publicKeySpki: initiator.publicKeySpki,
      verify: (data: Uint8Array, signature: Uint8Array) => initiator.verify(data, signature)
    };

    const session = new AdPairSession({
      pake: fakePake,
      now: () => fixture.now,
      initiatorVerifier: spoofedVerifier,
      responderVerifier: responder
    });
    session.acceptOffer(offer);
    session.acceptResponse(clone(fixture.response));

    expect(
      await failureCode(() =>
        session.finish({ secret: utf8(fixture.password), ...expectedSignatures() })
      )
    ).toBe('signature-device-mismatch');
  });

  it('rejects a signature made over a tampered transcript', async () => {
    const offer = clone(fixture.offer);
    offer.capabilities = [...offer.capabilities, fixture.tamper.capability];
    const { session, initiator } = await startSession(offer, clone(fixture.response));
    const tamperedTranscript = canonicalPairingTranscript({
      offer,
      response: clone(fixture.response),
      pake: fixture.pake
    });
    const signature = await signPairingTranscript(initiator, tamperedTranscript);

    expect(
      await failureCode(() =>
        session.finish({
          secret: utf8(fixture.password),
          initiatorSignature: signature,
          responderSignature: expectedSignatures().responderSignature
        })
      )
    ).toBe('invalid-signature');
  });
});

describe('AD-PAIR-1 binding, revocation and replay', () => {
  it('rejects missing, unsupported, mismatched and tampered channel bindings', async () => {
    expect(
      await failureCode(() =>
        canonicalPairingTranscript({
          offer: {
            ...clone(fixture.offer),
            channelBinding: { kind: 'none', value: '' }
          } as unknown as PairingPayload,
          response: clone(fixture.response),
          pake: fixture.pake
        })
      )
    ).toBe('missing-binding');

    expect(
      await failureCode(() =>
        canonicalPairingTranscript({
          offer: {
            ...clone(fixture.offer),
            channelBinding: { kind: 'unknown', value: fixture.binding.value }
          } as unknown as PairingPayload,
          response: clone(fixture.response),
          pake: fixture.pake
        })
      )
    ).toBe('unsupported-binding');

    const offer = clone(fixture.offer);
    const mismatched = { ...clone(fixture.response), channelBinding: fixture.tamper.binding };
    const session = new AdPairSession({
      pake: fakePake,
      now: () => fixture.now,
      initiatorVerifier: await loadIdentity(fixture.initiator),
      responderVerifier: await loadIdentity(fixture.responder)
    });
    session.acceptOffer(offer);
    expect(
      await failureCode(() => session.acceptResponse(mismatched))
    ).toBe('channel-binding-mismatch');

    const base = await computePairingTranscriptHash({
      offer: clone(fixture.offer),
      response: clone(fixture.response),
      pake: fixture.pake
    });
    const tampered = await computePairingTranscriptHash({
      offer: { ...clone(fixture.offer), channelBinding: fixture.tamper.binding },
      response: { ...clone(fixture.response), channelBinding: fixture.tamper.binding },
      pake: fixture.pake
    });
    expect(bytesToHex(base)).toBe(fixture.expected.transcriptHash);
    expect(bytesToHex(tampered)).not.toBe(fixture.expected.transcriptHash);
  });

  it('rejects a device revoked before or during finish', async () => {
    const before = new DeviceRegistry({ now: () => fixture.now });
    before.pair({ deviceId: fixture.initiator.deviceId, publicKey: fixture.offer.publicKey });
    before.revoke(fixture.initiator.deviceId);
    const revokedSession = new AdPairSession({
      pake: fakePake,
      now: () => fixture.now,
      registry: before,
      initiatorVerifier: await loadIdentity(fixture.initiator),
      responderVerifier: await loadIdentity(fixture.responder)
    });
    expect(
      await failureCode(() => revokedSession.acceptOffer(clone(fixture.offer)))
    ).toBe('revoked-device');

    const during = new DeviceRegistry({ now: () => fixture.now });
    during.pair({ deviceId: fixture.initiator.deviceId, publicKey: fixture.offer.publicKey });
    during.pair({ deviceId: fixture.responder.deviceId, publicKey: fixture.response.publicKey });
    const { session } = await startSession(clone(fixture.offer), clone(fixture.response), {
      registry: during
    });
    during.revoke(fixture.responder.deviceId);
    expect(
      await failureCode(() =>
        session.finish({ secret: utf8(fixture.password), ...expectedSignatures() })
      )
    ).toBe('revoked-device');
  });

  it('rejects a replayed nonce', () => {
    const guard = new NonceReplayGuard({ now: () => fixture.now });
    validatePairingPayload(clone(fixture.offer), {
      now: fixture.now,
      replayGuard: guard
    });
    expect(() =>
      validatePairingPayload(clone(fixture.offer), {
        now: fixture.now,
        replayGuard: guard
      })
    ).toThrowError(PairingValidationError);
  });
});
