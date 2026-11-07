import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  CapabilityGrantError,
  CapabilityRevocationStore,
  authorizeCapabilityRequest,
  capabilityConfirmationThumbprint,
  createCapabilityLease,
  signCapabilityGrant,
  signCapabilityPossession,
  signCapabilityRevocationRecord,
  verifyCapabilityGrant,
  verifyCapabilityRevocationRecord
} from '../src/capability';
import type {
  CapabilityAuthorizationPolicy,
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
    jti: 'grant-auth-1',
    cap_uri: 'airdesk://fs/documents/read',
    op: ['read', 'stat'],
    nbf: fixture.now - 1_000,
    exp: fixture.now + 60_000,
    epoch_id: 4,
    ...(cnf === undefined ? {} : { cnf })
  };
}

function policy(provider: BrowserDeviceIdentity): CapabilityAuthorizationPolicy {
  return {
    providerDeviceId: provider.deviceId,
    approvedRootIssuers: [provider.deviceId],
    revocationIssuer: provider.deviceId,
    maxRevocationStalenessMs: 60_000
  };
}

async function revocationStore(
  provider: BrowserDeviceIdentity,
  entries: CapabilityRevocationRecord['entries'] = []
): Promise<CapabilityRevocationStore> {
  const record: CapabilityRevocationRecord = {
    iss: provider.deviceId,
    seq: 1,
    issued_at: fixture.now,
    entries
  };
  const verified = await verifyCapabilityRevocationRecord(
    await signCapabilityRevocationRecord(record, provider),
    provider,
    { now: fixture.now }
  );
  const store = new CapabilityRevocationStore({
    trustedIssuers: [provider.deviceId]
  });
  store.add(verified);
  return store;
}

async function failureCode(action: () => unknown): Promise<string> {
  try {
    await action();
  } catch (error) {
    if (error instanceof CapabilityGrantError) return error.code;
    throw error;
  }
  throw new Error('expected capability authorization failure');
}

async function authorizedRequest(
  provider: BrowserDeviceIdentity,
  controller: BrowserDeviceIdentity,
  options: {
    cnf?: string;
    revocations?: CapabilityRevocationStore;
    operation?: string;
  } = {}
) {
  const token = await signCapabilityGrant(
    claims(provider, controller.deviceId, options.cnf),
    provider
  );
  const grant = await verifyCapabilityGrant(token, provider, { now: fixture.now });
  const lease = createCapabilityLease(grant, {
    leaseId: 'lease-auth-1',
    workspaceId: 'workspace-1',
    applicationId: 'application-1',
    requesterDeviceId: controller.deviceId,
    sessionId: 'session-1',
    operations: ['read'],
    issuedAt: fixture.now,
    expiresAt: fixture.now + 10_000,
    auditId: 'audit-auth-1'
  });
  return {
    token,
    grant,
    lease,
    input: {
      chain: [token],
      verifiers: [provider],
      revocations: options.revocations ?? (await revocationStore(provider)),
      lease,
      workspaceId: 'workspace-1',
      applicationId: 'application-1',
      requesterDeviceId: controller.deviceId,
      sessionId: 'session-1',
      capUri: grant.claims.cap_uri,
      operation: options.operation ?? 'read',
      epochId: 4,
      now: fixture.now
    }
  };
}

describe('capability request authorization', () => {
  it('accepts an approved root grant, fresh revocation state and bounded lease', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const request = await authorizedRequest(provider, controller);
    const result = await authorizeCapabilityRequest(policy(provider), request.input);

    expect(result.root.claims.iss).toBe(provider.deviceId);
    expect(result.grant.claims.jti).toBe('grant-auth-1');
    expect(result.lease.leaseId).toBe('lease-auth-1');
  });

  it('requires proof of possession when the grant carries cnf', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const cnf = await capabilityConfirmationThumbprint(controller.publicKeySpki);
    const request = await authorizedRequest(provider, controller, { cnf });
    const nonce = new Uint8Array(32).fill(7);
    const proof = await signCapabilityPossession(request.grant, controller, nonce);

    expect(
      await failureCode(() => authorizeCapabilityRequest(policy(provider), request.input))
    ).toBe('missing-proof');
    await expect(
      authorizeCapabilityRequest(policy(provider), {
        ...request.input,
        possession: { proof, verifier: controller, requestNonce: nonce }
      })
    ).resolves.toMatchObject({ grant: { claims: { jti: 'grant-auth-1' } } });
    expect(
      await failureCode(() =>
        authorizeCapabilityRequest(policy(provider), {
          ...request.input,
          possession: {
            proof,
            verifier: controller,
            requestNonce: new Uint8Array(32).fill(8)
          }
        })
      )
    ).toBe('proof-mismatch');
  });

  it('rejects a root grant from an unapproved issuer', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const token = await signCapabilityGrant(
      {
        ...claims(provider, controller.deviceId),
        iss: controller.deviceId
      },
      controller
    );
    const grant = await verifyCapabilityGrant(token, controller, { now: fixture.now });
    const lease = createCapabilityLease(grant, {
      leaseId: 'lease-auth-2',
      workspaceId: 'workspace-1',
      applicationId: 'application-1',
      requesterDeviceId: controller.deviceId,
      sessionId: 'session-1',
      operations: ['read'],
      issuedAt: fixture.now,
      expiresAt: fixture.now + 10_000,
      auditId: 'audit-auth-2'
    });

    expect(
      await failureCode(() =>
        authorizeCapabilityRequest(policy(provider), {
          chain: [token],
          verifiers: [controller],
          revocations: new CapabilityRevocationStore(),
          lease,
          workspaceId: 'workspace-1',
          applicationId: 'application-1',
          requesterDeviceId: controller.deviceId,
          sessionId: 'session-1',
          capUri: grant.claims.cap_uri,
          operation: 'read',
          epochId: 4,
          now: fixture.now
        })
      )
    ).toBe('root-issuer-not-approved');
  });

  it('rejects a lease revoked by a signed distributed snapshot', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const revokedLeaseStore = await revocationStore(provider, [
      {
        ref: 'lease-auth-1',
        kind: 'lease',
        at: fixture.now,
        reason: 'device-revoked'
      }
    ]);
    const request = await authorizedRequest(provider, controller, {
      revocations: revokedLeaseStore
    });

    expect(
      await failureCode(() =>
        authorizeCapabilityRequest(policy(provider), request.input)
      )
    ).toBe('revoked');
  });

  it('rejects revoked grants, stale revocation state and out-of-scope requests', async () => {
    const provider = await loadIdentity(fixture.initiator);
    const controller = await loadIdentity(fixture.responder);
    const revokedStore = await revocationStore(provider, [
      {
        ref: 'grant-auth-1',
        kind: 'grant',
        at: fixture.now,
        reason: 'user-revoked'
      }
    ]);
    const request = await authorizedRequest(provider, controller, {
      revocations: revokedStore
    });
    const stale = await revocationStore(provider);
    expect(
      await failureCode(() =>
        authorizeCapabilityRequest(policy(provider), {
          ...request.input,
          now: fixture.now + 1_000
        })
      )
    ).toBe('revoked');
    expect(
      await failureCode(() =>
        authorizeCapabilityRequest(
          { ...policy(provider), maxRevocationStalenessMs: 1_000 },
          {
            ...request.input,
            revocations: stale,
            now: fixture.now + 2_000
          }
        )
      )
    ).toBe('revocation-stale');
    expect(
      await failureCode(() =>
        authorizeCapabilityRequest(policy(provider), {
          ...request.input,
          revocations: stale,
          operation: 'write'
        })
      )
    ).toBe('operation-not-granted');
    expect(
      await failureCode(() =>
        authorizeCapabilityRequest(policy(provider), {
          ...request.input,
          revocations: stale,
          workspaceId: 'workspace-2'
        })
      )
    ).toBe('lease-invalid');
  });
});
