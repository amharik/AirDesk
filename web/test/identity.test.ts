import { describe, expect, it } from 'vitest';
import {
  AdPairSession,
  BrowserIdentityAbsentError,
  BrowserIdentityLostError,
  DeviceRegistry,
  DeviceRegistryError,
  IdentityExistsError,
  MemoryKeyStore,
  NonceReplayGuard,
  PairingValidationError,
  bytesEqual,
  bytesToBase64Url,
  bytesToHex,
  canonicalPairingTranscript,
  computePairingTranscriptHash,
  createBrowserIdentity,
  deriveDeviceId,
  loadBrowserIdentity,
  loadOrCreateBrowserIdentity,
  parsePairingJson,
  selectIdentityAlgorithm,
  sha256,
  signPairingTranscript,
  utf8,
  validatePairingPayload
} from '../src/identity';
import type {
  PairingPayload,
  Spake2PlusExchangeResult,
  Spake2PlusPrimitive
} from '../src/identity';

const NOW = 1_700_000_000_000;
const OFFER_DEVICE = `ad-device:${'1'.repeat(64)}`;
const RESPONSE_DEVICE = `ad-device:${'2'.repeat(64)}`;
const PUBLIC_KEY = bytesToBase64Url(new Uint8Array(64).fill(7));
const OFFER_NONCE = bytesToBase64Url(new Uint8Array(32).fill(3));
const RESPONSE_NONCE = bytesToBase64Url(new Uint8Array(32).fill(4));
const CERTIFICATE_HASH = 'ab'.repeat(32);
const CERTIFICATE_HASH_TWO = 'cd'.repeat(32);

function offerPayload(overrides: Partial<PairingPayload> = {}): PairingPayload {
  return {
    protocol: 'adfp',
    version: '0.1',
    type: 'offer',
    deviceId: OFFER_DEVICE,
    publicKey: PUBLIC_KEY,
    nonce: OFFER_NONCE,
    expiresAt: NOW + 60_000,
    endpointHint: 'ws://127.0.0.1:4100',
    relayHint: 'https://relay.example/session/1',
    capabilities: ['display', 'clipboard-read'],
    channelBinding: { kind: 'certificate-hash', value: CERTIFICATE_HASH },
    ...overrides
  };
}

function responsePayload(
  offer: PairingPayload = offerPayload(),
  overrides: Partial<PairingPayload> = {}
): PairingPayload {
  return {
    protocol: 'adfp',
    version: '0.1',
    type: 'response',
    deviceId: RESPONSE_DEVICE,
    publicKey: PUBLIC_KEY,
    nonce: RESPONSE_NONCE,
    replyTo: offer.nonce,
    expiresAt: NOW + 60_000,
    endpointHint: 'ws://127.0.0.1:4100',
    capabilities: ['display'],
    channelBinding: { ...offer.channelBinding },
    ...overrides
  };
}

const PAKE_EVIDENCE: Spake2PlusExchangeResult = {
  initiatorShare: bytesToBase64Url(new Uint8Array(65).fill(1)),
  responderShare: bytesToBase64Url(new Uint8Array(65).fill(2)),
  initiatorConfirmation: bytesToBase64Url(new Uint8Array(32).fill(5)),
  responderConfirmation: bytesToBase64Url(new Uint8Array(32).fill(6)),
  sharedSecret: bytesToBase64Url(new Uint8Array(32).fill(11))
};

const fakePake: Spake2PlusPrimitive = {
  suite: 'SPAKE2+-P256-SHA256',
  async exchange() {
    return PAKE_EVIDENCE;
  }
};

function failureCode(action: () => unknown): string {
  try {
    action();
  } catch (error) {
    if (error instanceof PairingValidationError) return error.code;
    throw error;
  }
  throw new Error('expected pairing failure');
}

let pairingIdentities:
  | Promise<{ initiator: Awaited<ReturnType<typeof createBrowserIdentity>>; responder: Awaited<ReturnType<typeof createBrowserIdentity>> }>
  | undefined;

function getPairingIdentities() {
  pairingIdentities ??= Promise.all([
    createBrowserIdentity({ store: new MemoryKeyStore(), now: () => NOW }),
    createBrowserIdentity({ store: new MemoryKeyStore(), now: () => NOW })
  ]).then(([initiator, responder]) => ({ initiator, responder }));
  return pairingIdentities;
}

async function finishPairing(
  offer: PairingPayload = offerPayload(),
  response: PairingPayload = responsePayload(offer)
) {
  const { initiator, responder } = await getPairingIdentities();
  const boundOffer: PairingPayload = {
    ...offer,
    deviceId: initiator.deviceId,
    publicKey: bytesToBase64Url(initiator.publicKeySpki)
  };
  const boundResponse: PairingPayload = {
    ...response,
    deviceId: responder.deviceId,
    publicKey: bytesToBase64Url(responder.publicKeySpki),
    replyTo: boundOffer.nonce
  };
  const session = new AdPairSession({ pake: fakePake, now: () => NOW });
  session.acceptOffer(boundOffer);
  session.acceptResponse(boundResponse);
  const transcript = canonicalPairingTranscript({
    offer: boundOffer,
    response: boundResponse,
    pake: PAKE_EVIDENCE
  });
  return session.finish({
    secret: utf8('123456'),
    initiatorSignature: await signPairingTranscript(initiator, transcript),
    responderSignature: await signPairingTranscript(responder, transcript)
  });
}

describe('browser device identity', () => {
  it('prefers Ed25519 and falls back to P-256', async () => {
    const preferred = {
      async generateKey(algorithm: AlgorithmIdentifier) {
        const name = typeof algorithm === 'string' ? algorithm : algorithm.name;
        if (name === 'Ed25519') return {} as CryptoKeyPair;
        throw new Error('unexpected fallback');
      }
    } as unknown as SubtleCrypto;
    const fallback = {
      async generateKey(algorithm: AlgorithmIdentifier) {
        const name = typeof algorithm === 'string' ? algorithm : algorithm.name;
        if (name === 'Ed25519') throw new Error('unsupported');
        if (name === 'ECDSA') return {} as CryptoKeyPair;
        throw new Error('unexpected algorithm');
      }
    } as unknown as SubtleCrypto;

    await expect(selectIdentityAlgorithm(preferred)).resolves.toBe('Ed25519');
    await expect(selectIdentityAlgorithm(fallback)).resolves.toBe('P-256');
  });

  it('derives a stable device id from the public key and keeps private keys non-extractable', async () => {
    const store = new MemoryKeyStore();
    const identity = await createBrowserIdentity({ store, now: () => NOW });
    const expectedId = await deriveDeviceId(identity.publicKeySpki);
    const digest = await sha256(identity.publicKeySpki);

    expect(identity.deviceId).toBe(`ad-device:${bytesToHex(digest)}`);
    expect(identity.deviceId).toBe(expectedId);
    expect(identity.deviceId).toMatch(/^ad-device:[0-9a-f]{64}$/);
    expect(['Ed25519', 'P-256']).toContain(identity.algorithm);

    const stored = await store.load();
    expect(stored?.privateKey.extractable).toBe(false);

    const signature = await identity.sign(utf8('airdesk'));
    await expect(identity.verify(utf8('airdesk'), signature)).resolves.toBe(true);
    await expect(identity.verify(utf8('other'), signature)).resolves.toBe(false);
  });

  it('reloads the same identity and never silently rotates it', async () => {
    const store = new MemoryKeyStore();
    const first = await createBrowserIdentity({ store, now: () => NOW });
    const loaded = await loadBrowserIdentity({ store });
    expect(loaded.state).toBe('ready');
    if (loaded.state === 'ready') {
      expect(loaded.identity.deviceId).toBe(first.deviceId);
      expect(loaded.identity.algorithm).toBe(first.algorithm);
    }

    await expect(createBrowserIdentity({ store })).rejects.toBeInstanceOf(IdentityExistsError);

    await store.clear();
    const lost = await loadBrowserIdentity({ store, previouslyProvisioned: true });
    expect(lost.state).toBe('lost');
    await expect(
      loadOrCreateBrowserIdentity({ store, previouslyProvisioned: true })
    ).rejects.toBeInstanceOf(BrowserIdentityLostError);
    await expect(store.load()).resolves.toBeNull();
  });

  it('distinguishes a fresh install from a lost identity and requires explicit creation', async () => {
    const store = new MemoryKeyStore();
    await expect(loadBrowserIdentity({ store })).resolves.toMatchObject({ state: 'absent' });
    await expect(loadOrCreateBrowserIdentity({ store })).rejects.toBeInstanceOf(
      BrowserIdentityAbsentError
    );

    const identity = await loadOrCreateBrowserIdentity({ store, allowCreate: true });
    expect(identity.deviceId).toMatch(/^ad-device:[0-9a-f]{64}$/);

    const replacement = await createBrowserIdentity({ store, replace: true });
    expect(replacement.deviceId).not.toBe(identity.deviceId);

    const reloaded = await loadBrowserIdentity({ store });
    expect(reloaded.state).toBe('ready');
    if (reloaded.state === 'ready') expect(reloaded.identity.deviceId).toBe(replacement.deviceId);
  });
});

describe('AD-PAIR-1 payload validation', () => {
  it('accepts a strict versioned offer with an out-of-band certificate binding', () => {
    const parsed = parsePairingJson(JSON.stringify(offerPayload()), { now: NOW });
    expect(parsed).toMatchObject({
      protocol: 'adfp',
      version: '0.1',
      type: 'offer',
      deviceId: OFFER_DEVICE,
      nonce: OFFER_NONCE,
      channelBinding: { kind: 'certificate-hash', value: CERTIFICATE_HASH }
    });
  });

  it('rejects wrong protocol versions, malformed JSON and unknown fields', () => {
    expect(
      failureCode(() =>
        parsePairingJson(JSON.stringify(offerPayload({ version: '1.0' })), { now: NOW })
      )
    ).toBe('unknown-major');
    expect(
      failureCode(() =>
        parsePairingJson(JSON.stringify(offerPayload({ version: '0.2' })), { now: NOW })
      )
    ).toBe('unsupported-version');
    expect(
      failureCode(() =>
        parsePairingJson(JSON.stringify(offerPayload({ protocol: 'other' as 'adfp' })), {
          now: NOW
        })
      )
    ).toBe('unsupported-protocol');
    expect(failureCode(() => parsePairingJson('{not json', { now: NOW }))).toBe('malformed-json');
    expect(
      failureCode(() =>
        validatePairingPayload({ ...offerPayload(), extra: true }, { now: NOW })
      )
    ).toBe('unknown-field');
  });

  it('rejects expired payloads and replayed nonces', () => {
    expect(
      failureCode(() =>
        parsePairingJson(JSON.stringify(offerPayload({ expiresAt: NOW })), { now: NOW })
      )
    ).toBe('expired');

    const guard = new NonceReplayGuard({ now: () => NOW });
    const raw = JSON.stringify(offerPayload());
    parsePairingJson(raw, { now: NOW, replayGuard: guard });
    expect(failureCode(() => parsePairingJson(raw, { now: NOW, replayGuard: guard }))).toBe(
      'replayed-nonce'
    );
  });

  it('rejects missing, none and malformed channel bindings', () => {
    const missing = { ...offerPayload() } as Record<string, unknown>;
    delete missing.channelBinding;
    expect(failureCode(() => validatePairingPayload(missing, { now: NOW }))).toBe(
      'missing-binding'
    );

    const none = {
      ...offerPayload(),
      channelBinding: { kind: 'none', value: '' }
    } as unknown as PairingPayload;
    expect(failureCode(() => validatePairingPayload(none, { now: NOW }))).toBe(
      'missing-binding'
    );

    const malformed = {
      ...offerPayload(),
      channelBinding: { kind: 'certificate-hash', value: 'short' }
    } as PairingPayload;
    expect(failureCode(() => validatePairingPayload(malformed, { now: NOW }))).toBe(
      'invalid-binding'
    );
  });

  it('rejects invalid device identifiers, public keys, nonces, capabilities and hints', () => {
    expect(
      failureCode(() =>
        validatePairingPayload(offerPayload({ deviceId: 'device-name' }), { now: NOW })
      )
    ).toBe('invalid-device-id');
    expect(
      failureCode(() =>
        validatePairingPayload(offerPayload({ publicKey: 'not base64!' }), { now: NOW })
      )
    ).toBe('invalid-public-key');
    expect(
      failureCode(() =>
        validatePairingPayload(offerPayload({ nonce: 'short' }), { now: NOW })
      )
    ).toBe('invalid-nonce');
    expect(
      failureCode(() =>
        validatePairingPayload(offerPayload({ capabilities: ['display', 'display'] }), {
          now: NOW
        })
      )
    ).toBe('invalid-capabilities');
    expect(
      failureCode(() =>
        validatePairingPayload(offerPayload({ endpointHint: '' }), { now: NOW })
      )
    ).toBe('invalid-endpoint-hint');
  });
});

describe('AD-PAIR-1 transcript and state machine', () => {
  it('accepts an offer and response and derives a deterministic transcript and SAS', async () => {
    const first = await finishPairing();
    const second = await finishPairing();

    expect(first.state).toBe('completed');
    expect(first.transcriptHash).toHaveLength(32);
    expect(first.shortAuthenticationString).toMatch(/^\d{6}$/);
    expect(first.shortAuthenticationString).toBe(second.shortAuthenticationString);
    expect(bytesEqual(first.transcriptHash, second.transcriptHash)).toBe(true);
    expect(first.channelBinding).toEqual({
      kind: 'certificate-hash',
      value: CERTIFICATE_HASH
    });
    expect(first.requestedCapabilities).toEqual(['clipboard-read', 'display']);
  });

  it('changes the transcript when canonical fields change', async () => {
    const offer = offerPayload();
    const response = responsePayload(offer);
    const base = await computePairingTranscriptHash({ offer, response, pake: PAKE_EVIDENCE });
    const changedCapabilities = await computePairingTranscriptHash({
      offer: { ...offer, capabilities: ['display'] },
      response,
      pake: PAKE_EVIDENCE
    });
    const changedExpiry = await computePairingTranscriptHash({
      offer: { ...offer, expiresAt: offer.expiresAt + 1 },
      response,
      pake: PAKE_EVIDENCE
    });
    const changedBinding = await computePairingTranscriptHash({
      offer,
      response,
      pake: { ...PAKE_EVIDENCE, initiatorConfirmation: bytesToBase64Url(new Uint8Array(32).fill(9)) }
    });

    expect(bytesEqual(base, changedCapabilities)).toBe(false);
    expect(bytesEqual(base, changedExpiry)).toBe(false);
    expect(bytesEqual(base, changedBinding)).toBe(false);
  });

  it('rejects a transcript hash mismatch', async () => {
    const session = new AdPairSession({ pake: fakePake, now: () => NOW });
    session.acceptOffer(offerPayload());
    session.acceptResponse(responsePayload());
    await expect(
      session.finish({
        secret: utf8('123456'),
        expectedTranscriptHash: new Uint8Array(32).fill(9)
      })
    ).rejects.toMatchObject({ code: 'transcript-mismatch' });
    expect(session.state).toBe('failed');
  });

  it('rejects responses tied to another offer or another channel binding', () => {
    const offer = offerPayload();

    const wrongReply = new AdPairSession({ pake: fakePake, now: () => NOW });
    wrongReply.acceptOffer(offer);
    expect(
      failureCode(() =>
        wrongReply.acceptResponse(
          responsePayload(offer, {
            replyTo: bytesToBase64Url(new Uint8Array(32).fill(8))
          })
        )
      )
    ).toBe('offer-nonce-mismatch');

    const wrongBinding = new AdPairSession({ pake: fakePake, now: () => NOW });
    wrongBinding.acceptOffer(offer);
    expect(
      failureCode(() =>
        wrongBinding.acceptResponse(
          responsePayload(offer, {
            channelBinding: { kind: 'certificate-hash', value: CERTIFICATE_HASH_TWO }
          })
        )
      )
    ).toBe('channel-binding-mismatch');
  });

  it('rejects revoked devices', () => {
    const registry = new DeviceRegistry({ now: () => NOW });
    registry.pair({ deviceId: OFFER_DEVICE, publicKey: PUBLIC_KEY });
    registry.revoke(OFFER_DEVICE);

    const session = new AdPairSession({ pake: fakePake, now: () => NOW, registry });
    expect(failureCode(() => session.acceptOffer(offerPayload()))).toBe('revoked-device');
  });

  it('does not grant workspace ownership, membership, controller role or optional capabilities', async () => {
    const result = await finishPairing();

    expect(result.grants).toMatchObject({
      trusted: true,
      workspaceOwnership: false,
      workspaceMembership: false,
      controllerRole: false
    });
    expect(result.grants.grantedCapabilities).toEqual([]);
    expect(result.requestedCapabilities).toContain('clipboard-read');
  });
});

describe('device registry', () => {
  it('records requested capabilities without granting them', () => {
    const registry = new DeviceRegistry({ now: () => NOW });
    const record = registry.pair({
      deviceId: OFFER_DEVICE,
      publicKey: PUBLIC_KEY,
      requestedCapabilities: ['display', 'workspace-owner']
    });

    expect(record.requestedCapabilities).toEqual(['display', 'workspace-owner']);
    expect(registry.capabilities(OFFER_DEVICE)).toEqual([]);
    expect(registry.isTrusted(OFFER_DEVICE)).toBe(true);
  });

  it('invalidates future sessions and existing leases on revocation', () => {
    const registry = new DeviceRegistry({
      now: () => NOW,
      createLeaseId: () => 'lease-1'
    });
    registry.pair({ deviceId: OFFER_DEVICE, publicKey: PUBLIC_KEY });
    const lease = registry.issueSession(OFFER_DEVICE, 60_000);

    expect(registry.validateLease(lease)).toBe(true);
    expect(registry.revoke(OFFER_DEVICE)).toBe(true);
    expect(registry.validateLease(lease)).toBe(false);
    expect(() => registry.issueSession(OFFER_DEVICE, 60_000)).toThrow(DeviceRegistryError);
    expect(() =>
      registry.pair({ deviceId: OFFER_DEVICE, publicKey: PUBLIC_KEY })
    ).toThrow(DeviceRegistryError);
  });
});
