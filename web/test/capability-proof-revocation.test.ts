import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  CapabilityGrantError,
  CapabilityRevocationStore,
  capabilityConfirmationThumbprint,
  signCapabilityGrant,
  signCapabilityPossession,
  signCapabilityRevocationRecord,
  verifyCapabilityGrant,
  verifyCapabilityPossession,
  verifyCapabilityRevocationRecord
} from '../src/capability';
import type {
  CapabilityGrantClaims,
  CapabilityRevocationRecord
} from '../src/capability';
import {
  MemoryKeyStore,
  base64UrlToBytes,
  importBrowserIdentity
} from '../src/identity';
import type {
  BrowserDeviceIdentity,
  DeviceIdentityAlgorithm
} from '../src/identity';

interface FixtureIdentity {
  algorithm: DeviceIdentityAlgorithm;
  privateKeyPkcs8: string;
  publicKeySpki: string;
  deviceId: string;
}

const fixture = JSON.parse(
  readFileSync(new URL('./fixtures/ad-pair-1.json', import.meta.url), 'utf8')
) as {
  now: number;
  initiator: FixtureIdentity;
  responder: FixtureIdentity;
};

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

function claims(
  provider: BrowserDeviceIdentity,
  subject: string,
  cnf?: string
): CapabilityGrantClaims {
  return {
    iss: provider.deviceId,
    sub: subject,
    aud: provider.deviceId,
    jti: 'grant-proof-1',
    cap_uri: 'airdesk://fs/documents/read',
    op: ['read'],
    nbf: fixture.now - 1_000,
    exp: fixture.now + 60_000,
    epoch_id: 3,
    ...(cnf === undefined ? {} : { cnf })
  };
}

async function failureCode(action: () => unknown): Promise<string> {
  try {
    await action();
  } catch (error) {
    if (error instanceof CapabilityGrantError) return error.code;
    throw error;
  }
  throw new Error('expected capability failure');
}

describe('capability proof of possession', () => {
  it('binds the confirmation thumbprint and request nonce to the grant', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const cnf = await capabilityConfirmationThumbprint(controller.publicKeySpki);
    const token = await signCapabilityGrant(claims(provider, controller.deviceId, cnf), provider);
    const grant = await verifyCapabilityGrant(token, provider, { now: fixture.now });
    const nonce = new Uint8Array(32).fill(9);
    const proof = await signCapabilityPossession(grant, controller, nonce);

    await expect(
      verifyCapabilityPossession(grant, proof, controller, { requestNonce: nonce })
    ).resolves.toBeUndefined();

    expect(
      await failureCode(() =>
        verifyCapabilityPossession(
          grant,
          proof,
          controller,
          { requestNonce: new Uint8Array(32).fill(8) }
        )
      )
    ).toBe('proof-mismatch');
    expect(
      await failureCode(() => verifyCapabilityPossession(grant, proof, provider))
    ).toBe('confirmation-mismatch');
  });

  it('rejects missing proofs and grants that do not require them', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const cnf = await capabilityConfirmationThumbprint(controller.publicKeySpki);
    const withCnf = await verifyCapabilityGrant(
      await signCapabilityGrant(claims(provider, controller.deviceId, cnf), provider),
      provider,
      { now: fixture.now }
    );
    const withoutCnf = await verifyCapabilityGrant(
      await signCapabilityGrant(claims(provider, controller.deviceId), provider),
      provider,
      { now: fixture.now }
    );

    expect(
      await failureCode(() =>
        verifyCapabilityPossession(
          withCnf,
          { algorithm: 'Ed25519', signature: new Uint8Array() },
          controller
        )
      )
    ).toBe('missing-proof');
    expect(
      await failureCode(() =>
        verifyCapabilityPossession(
          withoutCnf,
          { algorithm: 'Ed25519', signature: new Uint8Array([1]) },
          controller
        )
      )
    ).toBe('proof-not-required');
  });
});

describe('capability revocation records', () => {
  function record(
    provider: BrowserDeviceIdentity,
    seq: number,
    ref: string
  ): CapabilityRevocationRecord {
    return {
      iss: provider.deviceId,
      seq,
      issued_at: fixture.now,
      entries: [
        {
          ref,
          kind: 'grant',
          at: fixture.now,
          reason: 'user-revoked'
        }
      ]
    };
  }

  it('signs, verifies and enforces a revocation snapshot', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const token = await signCapabilityGrant(
      claims(provider, controller.deviceId),
      provider
    );
    const grant = await verifyCapabilityGrant(token, provider, { now: fixture.now });
    const recordToken = await signCapabilityRevocationRecord(
      record(provider, 1, grant.claims.jti),
      provider
    );
    const verified = await verifyCapabilityRevocationRecord(recordToken, provider, {
      now: fixture.now,
      expectedIssuer: provider.deviceId,
      minimumSequence: 1
    });
    const store = new CapabilityRevocationStore({
      trustedIssuers: [provider.deviceId]
    });

    expect(store.add(verified)).toBe(true);
    expect(store.add(verified)).toBe(false);
    expect(() =>
      store.assertNotRevoked(grant.claims.jti, 'grant', {
        issuer: provider.deviceId,
        now: fixture.now + 1_000,
        maxStalenessMs: 60_000
      })
    ).toThrowError(expect.objectContaining({ code: 'revoked' }));
    expect(() =>
      store.assertNotRevoked('another-grant', 'grant', {
        issuer: provider.deviceId,
        now: fixture.now + 1_000,
        maxStalenessMs: 60_000
      })
    ).not.toThrow();
    expect(
      await failureCode(() =>
        verifyCapabilityRevocationRecord(recordToken, provider, {
          now: fixture.now,
          expectedIssuer: controller.deviceId
        })
      )
    ).toBe('issuer-mismatch');
  });

  it('rejects stale, future and tampered revocation records', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const recordToken = await signCapabilityRevocationRecord(
      record(provider, 1, 'grant-1'),
      provider
    );

    expect(
      await failureCode(() =>
        verifyCapabilityRevocationRecord(recordToken, provider, {
          now: fixture.now + 120_000,
          maxStalenessMs: 60_000
        })
      )
    ).toBe('revocation-stale');

    const future = await signCapabilityRevocationRecord(
      {
        ...record(provider, 1, 'grant-1'),
        issued_at: fixture.now + 600_000,
        entries: [
          {
            ref: 'grant-1',
            kind: 'grant',
            at: fixture.now,
            reason: 'policy'
          }
        ]
      },
      provider
    );
    expect(
      await failureCode(() =>
        verifyCapabilityRevocationRecord(future, provider, { now: fixture.now })
      )
    ).toBe('revocation-stale');

    const tampered = new Uint8Array(recordToken);
    tampered[tampered.length - 1]! ^= 0x01;
    expect(
      await failureCode(() =>
        verifyCapabilityRevocationRecord(tampered, provider, { now: fixture.now })
      )
    ).toBe('invalid-revocation');

    expect(
      await failureCode(() =>
        signCapabilityRevocationRecord(
          { ...record(provider, 1, 'grant-1'), iss: controller.deviceId },
          provider
        )
      )
    ).toBe('issuer-mismatch');
  });

  it('keeps revocation sequences monotonic and snapshots cumulative', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const store = new CapabilityRevocationStore({
      trustedIssuers: [provider.deviceId]
    });
    const first = await verifyCapabilityRevocationRecord(
      await signCapabilityRevocationRecord(record(provider, 1, 'grant-1'), provider),
      provider,
      { now: fixture.now }
    );
    const second = await verifyCapabilityRevocationRecord(
      await signCapabilityRevocationRecord(
        {
          ...record(provider, 2, 'grant-2'),
          entries: [
            ...record(provider, 1, 'grant-1').entries,
            ...record(provider, 2, 'grant-2').entries
          ]
        },
        provider
      ),
      provider,
      { now: fixture.now }
    );
    const dropped = await verifyCapabilityRevocationRecord(
      await signCapabilityRevocationRecord(record(provider, 3, 'grant-3'), provider),
      provider,
      { now: fixture.now }
    );

    expect(store.add(first)).toBe(true);
    expect(store.add(second)).toBe(true);
    expect(store.latest(provider.deviceId)?.record.seq).toBe(2);
    expect(() => store.add(dropped)).toThrowError(
      expect.objectContaining({ code: 'invalid-revocation' })
    );
    expect(() => store.add(first)).toThrowError(
      expect.objectContaining({ code: 'revocation-stale' })
    );
  });

  it('fails closed without a fresh record from the required issuer', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const empty = new CapabilityRevocationStore({
      trustedIssuers: [provider.deviceId]
    });
    expect(() =>
      empty.assertNotRevoked('grant-1', 'grant', {
        issuer: provider.deviceId,
        now: fixture.now,
        maxStalenessMs: 60_000
      })
    ).toThrowError(expect.objectContaining({ code: 'revocation-stale' }));

    const recordToken = await signCapabilityRevocationRecord(
      record(provider, 1, 'grant-1'),
      provider
    );
    const verified = await verifyCapabilityRevocationRecord(recordToken, provider, {
      now: fixture.now
    });
    empty.add(verified);
    expect(() =>
      empty.assertNotRevoked('grant-2', 'grant', {
        issuer: provider.deviceId,
        now: fixture.now + 61_000,
        maxStalenessMs: 60_000
      })
    ).toThrowError(expect.objectContaining({ code: 'revocation-stale' }));
  });
});
