import type { DeviceSignatureVerifier } from '../identity/identity';
import { CapabilityGrantError } from './grant';
import type {
  CapabilityGrantErrorCode,
  CapabilityLease,
  VerifiedCapabilityGrant
} from './grant';
import { validateCapabilityLease, verifyCapabilityGrantChain } from './grant';
import { verifyCapabilityPossession } from './proof';
import type { CapabilityPossessionProof } from './proof';
import type { CapabilityRevocationStore } from './revocation';

export interface CapabilityAuthorizationPolicy {
  providerDeviceId: string;
  approvedRootIssuers: Iterable<string>;
  revocationIssuer: string;
  maxRevocationStalenessMs: number;
  requireProofOfPossession?: boolean;
  maxFutureSkewMs?: number;
}

export interface CapabilityPossessionEvidence {
  proof: CapabilityPossessionProof;
  verifier: DeviceSignatureVerifier;
  requestNonce?: Uint8Array;
}

export interface AuthorizeCapabilityRequestInput {
  chain: readonly Uint8Array[];
  verifiers: readonly DeviceSignatureVerifier[];
  revocations: CapabilityRevocationStore;
  lease: CapabilityLease;
  workspaceId: string;
  applicationId: string;
  requesterDeviceId: string;
  sessionId: string;
  capUri: string;
  operation: string;
  epochId: number;
  now?: number;
  possession?: CapabilityPossessionEvidence;
}

export interface CapabilityAuthorizationResult {
  chain: VerifiedCapabilityGrant[];
  root: VerifiedCapabilityGrant;
  grant: VerifiedCapabilityGrant;
  lease: CapabilityLease;
}

function fail(code: CapabilityGrantErrorCode, message: string): never {
  throw new CapabilityGrantError(code, message);
}

export async function authorizeCapabilityRequest(
  policy: CapabilityAuthorizationPolicy,
  input: AuthorizeCapabilityRequestInput
): Promise<CapabilityAuthorizationResult> {
  if (
    policy.providerDeviceId.length === 0 ||
    policy.revocationIssuer.length === 0 ||
    !Number.isSafeInteger(policy.maxRevocationStalenessMs) ||
    policy.maxRevocationStalenessMs < 0
  ) {
    fail('lease-invalid', 'invalid capability authorization policy');
  }
  const now = input.now ?? Date.now();
  const chain = await verifyCapabilityGrantChain(input.chain, input.verifiers, {
    now,
    expectedAudience: policy.providerDeviceId,
    expectedEpochId: input.epochId
  });
  const root = chain[0]!;
  const grant = chain[chain.length - 1]!;
  const approvedRootIssuers = new Set(policy.approvedRootIssuers);
  if (!approvedRootIssuers.has(root.claims.iss)) {
    fail('root-issuer-not-approved', 'root grant issuer is not approved by the provider');
  }
  if (!grant.claims.op.includes(input.operation)) {
    fail('operation-not-granted', 'grant does not allow the requested operation');
  }
  if (grant.claims.cap_uri !== input.capUri) {
    fail('operation-not-granted', 'requested capability does not match the grant');
  }

  input.revocations.assertNotRevoked(grant.claims.jti, 'grant', {
    issuer: policy.revocationIssuer,
    now,
    maxStalenessMs: policy.maxRevocationStalenessMs,
    ...(policy.maxFutureSkewMs === undefined
      ? {}
      : { maxFutureSkewMs: policy.maxFutureSkewMs })
  });
  validateCapabilityLease(input.lease, grant, {
    now,
    workspaceId: input.workspaceId,
    applicationId: input.applicationId,
    requesterDeviceId: input.requesterDeviceId,
    sessionId: input.sessionId
  });
  if (input.lease.capUri !== input.capUri) {
    fail('lease-invalid', 'lease capability does not match the request');
  }
  if (!input.lease.operations.includes(input.operation)) {
    fail('operation-not-granted', 'lease does not allow the requested operation');
  }

  if (grant.claims.cnf !== undefined || policy.requireProofOfPossession) {
    if (!input.possession) {
      fail('missing-proof', 'proof of possession is required');
    }
    await verifyCapabilityPossession(
      grant,
      input.possession.proof,
      input.possession.verifier,
      input.possession.requestNonce === undefined
        ? {}
        : { requestNonce: input.possession.requestNonce }
    );
  }

  return { chain, root, grant, lease: input.lease };
}
