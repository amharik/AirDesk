import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  CAPABILITY_CHAIN_MAX_DEPTH,
  CapabilityGrantError,
  createCapabilityLease,
  decodeCbor,
  encodeCbor,
  signCapabilityGrant,
  validateCapabilityLease,
  verifyCapabilityGrant,
  verifyCapabilityGrantChain
} from '../src/capability';
import type { CapabilityGrantClaims } from '../src/capability';
import {
  MemoryKeyStore,
  base64UrlToBytes,
  bytesToBase64Url,
  bytesToHex,
  createBrowserIdentity,
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

function rootClaims(
  provider: BrowserDeviceIdentity,
  subject: string
): CapabilityGrantClaims {
  return {
    iss: provider.deviceId,
    sub: subject,
    aud: provider.deviceId,
    jti: 'grant-root-1',
    cap_uri: 'airdesk://fs/documents/read',
    op: ['read', 'stat'],
    nbf: fixture.now - 1_000,
    exp: fixture.now + 60_000,
    epoch_id: 7
  };
}

async function failureCode(action: () => unknown): Promise<string> {
  try {
    await action();
  } catch (error) {
    if (error instanceof CapabilityGrantError) return error.code;
    throw error;
  }
  throw new Error('expected capability grant failure');
}

describe('capability grant COSE_Sign1', () => {
  it('signs and verifies a root grant', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const claims = rootClaims(provider, controller.deviceId);
    const token = await signCapabilityGrant(claims, provider);

    expect(bytesToHex(token.subarray(0, 3))).toBe('d28443');
    const verified = await verifyCapabilityGrant(token, provider, {
      now: fixture.now,
      expectedAudience: provider.deviceId,
      expectedSubject: controller.deviceId,
      expectedEpochId: 7
    });

    expect(verified.claims).toEqual(claims);
    expect(verified.algorithm).toBe('Ed25519');
    expect(verified.tokenHash).toHaveLength(32);
  });

  it('rejects invalid signatures, tampering and mismatched expectations', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const claims = rootClaims(provider, controller.deviceId);
    const token = await signCapabilityGrant(claims, provider);

    const tamperedSignature = new Uint8Array(token);
    tamperedSignature[tamperedSignature.length - 1]! ^= 0x01;
    expect(
      await failureCode(() =>
        verifyCapabilityGrant(tamperedSignature, provider, { now: fixture.now })
      )
    ).toBe('invalid-signature');

    const tamperedPayload = new Uint8Array(token);
    const signatureBytes = tamperedPayload.length - 66;
    tamperedPayload[signatureBytes - 1]! ^= 0x01;
    expect(
      await failureCode(() =>
        verifyCapabilityGrant(tamperedPayload, provider, { now: fixture.now })
      )
    ).toBe('invalid-signature');

    expect(
      await failureCode(() =>
        verifyCapabilityGrant(token, provider, {
          now: fixture.now,
          expectedAudience: 'other-provider'
        })
      )
    ).toBe('audience-mismatch');
    expect(
      await failureCode(() =>
        verifyCapabilityGrant(token, provider, {
          now: fixture.now,
          expectedEpochId: 8
        })
      )
    ).toBe('epoch-mismatch');
    expect(
      await failureCode(() =>
        verifyCapabilityGrant(
          token,
          { ...provider, deviceId: controller.deviceId },
          { now: fixture.now }
        )
      )
    ).toBe('issuer-mismatch');
  });

  it('rejects expired and not-yet-valid grants', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const token = await signCapabilityGrant(
      rootClaims(provider, controller.deviceId),
      provider
    );

    expect(
      await failureCode(() =>
        verifyCapabilityGrant(token, provider, { now: fixture.now + 60_000 })
      )
    ).toBe('expired');
    expect(
      await failureCode(() =>
        verifyCapabilityGrant(token, provider, { now: fixture.now - 2_000 })
      )
    ).toBe('not-yet-valid');
  });

  it('rejects an issuer that does not match the signer', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    expect(
      await failureCode(() =>
        signCapabilityGrant(
          { ...rootClaims(provider, controller.deviceId), iss: controller.deviceId },
          provider
        )
      )
    ).toBe('issuer-mismatch');
  });
});

describe('capability grant delegation chain', () => {
  it('verifies an attenuated three-hop chain', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const task = await createBrowserIdentity({
      store: new MemoryKeyStore(),
      now: () => fixture.now
    });

    const root = await signCapabilityGrant(
      rootClaims(provider, controller.deviceId),
      provider
    );
    const rootVerified = await verifyCapabilityGrant(root, provider, {
      now: fixture.now
    });
    const childClaims: CapabilityGrantClaims = {
      iss: controller.deviceId,
      sub: task.deviceId,
      aud: provider.deviceId,
      jti: 'grant-child-1',
      cap_uri: 'airdesk://fs/documents/read',
      op: ['read'],
      nbf: fixture.now - 500,
      exp: fixture.now + 30_000,
      epoch_id: 7,
      parent: bytesToBase64Url(rootVerified.tokenHash)
    };
    const child = await signCapabilityGrant(childClaims, controller);

    const chain = await verifyCapabilityGrantChain(
      [root, child],
      [provider, controller],
      {
        now: fixture.now,
        expectedAudience: provider.deviceId,
        expectedEpochId: 7,
        expectedRootIssuer: provider.deviceId
      }
    );

    expect(chain).toHaveLength(2);
    expect(chain[1]?.claims.op).toEqual(['read']);
    expect(chain[1]?.claims.parent).toBe(bytesToBase64Url(rootVerified.tokenHash));
  });

  it('rejects widened or mismatched delegation', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const root = await signCapabilityGrant(
      rootClaims(provider, controller.deviceId),
      provider
    );
    const rootVerified = await verifyCapabilityGrant(root, provider, {
      now: fixture.now
    });
    const parentHash = bytesToBase64Url(rootVerified.tokenHash);

    const verifyChild = async (
      overrides: Partial<CapabilityGrantClaims>,
      childVerifier = controller
    ) => {
      const signer = overrides.iss === provider.deviceId ? provider : controller;
      const child = await signCapabilityGrant(
        {
          iss: controller.deviceId,
          sub: controller.deviceId,
          aud: provider.deviceId,
          jti: 'grant-child-2',
          cap_uri: 'airdesk://fs/documents/read',
          op: ['read'],
          nbf: fixture.now - 500,
          exp: fixture.now + 30_000,
          epoch_id: 7,
          parent: parentHash,
          ...overrides
        },
        signer
      );
      return failureCode(() =>
        verifyCapabilityGrantChain([root, child], [provider, childVerifier], {
          now: fixture.now
        })
      );
    };

    expect(await verifyChild({ op: ['read', 'write'] })).toBe('attenuation-widened');
    expect(await verifyChild({ exp: fixture.now + 90_000 })).toBe('attenuation-widened');
    expect(await verifyChild({ cap_uri: 'airdesk://fs' })).toBe('attenuation-widened');
    expect(await verifyChild({ epoch_id: 8 })).toBe('attenuation-widened');
    expect(await verifyChild({ aud: controller.deviceId })).toBe('attenuation-widened');
    expect(await verifyChild({ iss: provider.deviceId }, provider)).toBe('chain-mismatch');
    expect(await verifyChild({ parent: bytesToBase64Url(new Uint8Array(32)) })).toBe(
      'parent-mismatch'
    );
  });

  it('rejects a chain longer than the maximum depth', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const token = await signCapabilityGrant(
      rootClaims(provider, controller.deviceId),
      provider
    );
    const tokens = Array.from({ length: CAPABILITY_CHAIN_MAX_DEPTH + 1 }, () => token);
    const verifiers = tokens.map(() => provider);

    expect(
      await failureCode(() => verifyCapabilityGrantChain(tokens, verifiers, { now: fixture.now }))
    ).toBe('chain-too-deep');
  });
});

describe('capability lease', () => {
  it('bounds a lease to its grant, workspace and application', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const token = await signCapabilityGrant(
      rootClaims(provider, controller.deviceId),
      provider
    );
    const grant = await verifyCapabilityGrant(token, provider, { now: fixture.now });
    const lease = createCapabilityLease(grant, {
      leaseId: 'lease-1',
      workspaceId: 'workspace-1',
      applicationId: 'application-1',
      requesterDeviceId: controller.deviceId,
      sessionId: 'session-1',
      operations: ['read'],
      issuedAt: fixture.now,
      expiresAt: fixture.now + 10_000,
      auditId: 'audit-1'
    });

    expect(lease.epochId).toBe(7);
    expect(() =>
      validateCapabilityLease(lease, grant, {
        now: fixture.now + 1_000,
        workspaceId: 'workspace-1',
        applicationId: 'application-1',
        requesterDeviceId: controller.deviceId,
        sessionId: 'session-1'
      })
    ).not.toThrow();

    expect(() =>
      validateCapabilityLease(lease, grant, {
        now: fixture.now + 1_000,
        workspaceId: 'workspace-2'
      })
    ).toThrowError(expect.objectContaining({ code: 'lease-invalid' }));
    expect(() =>
      validateCapabilityLease(lease, grant, { now: fixture.now + 10_000 })
    ).toThrowError(expect.objectContaining({ code: 'expired' }));
  });

  it('rejects leases that outlive or widen their grant', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const token = await signCapabilityGrant(
      rootClaims(provider, controller.deviceId),
      provider
    );
    const grant = await verifyCapabilityGrant(token, provider, { now: fixture.now });
    const base = {
      leaseId: 'lease-2',
      workspaceId: 'workspace-1',
      applicationId: 'application-1',
      requesterDeviceId: controller.deviceId,
      sessionId: 'session-1',
      operations: ['read'],
      issuedAt: fixture.now,
      auditId: 'audit-2'
    };

    expect(() =>
      createCapabilityLease(grant, { ...base, expiresAt: grant.claims.exp + 1 })
    ).toThrowError(expect.objectContaining({ code: 'lease-invalid' }));
    expect(() =>
      createCapabilityLease(grant, {
        ...base,
        operations: ['read', 'write'],
        expiresAt: fixture.now + 10_000
      })
    ).toThrowError(expect.objectContaining({ code: 'lease-invalid' }));
  });
});

describe('CBOR codec', () => {
  it('encodes integer-keyed maps used by COSE protected headers', () => {
    expect(bytesToHex(encodeCbor(new Map([[1, -8]])))).toBe('a10127');
    expect(bytesToHex(encodeCbor(new Map([[1, -7]])))).toBe('a10126');
  });

  it('round-trips nested bytes, arrays and maps', () => {
    const value = new Map<string, unknown>([
      ['bytes', new Uint8Array([1, 2, 3])],
      ['array', ['a', 1, true, null]],
      ['map', new Map([['n', -9]])]
    ]);
    const encoded = encodeCbor(value as never);
    expect(decodeCbor(encoded)).toEqual(value);
  });

  it('rejects duplicate keys and trailing bytes', () => {
    expect(() => decodeCbor(new Uint8Array([0xa2, 0x01, 0x01, 0x01, 0x02]))).toThrow(
      'duplicate CBOR map key'
    );
    expect(() => decodeCbor(new Uint8Array([0x01, 0x02]))).toThrow('trailing CBOR bytes');
  });
});
