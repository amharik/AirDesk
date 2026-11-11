import CryptoKit
import Foundation

enum CapabilityRevocationKind: String, Equatable {
    case grant
    case lease
}

struct CapabilityRevocationEntry: Equatable {
    var ref: String
    var kind: CapabilityRevocationKind
    var atMillis: Int64
    var reason: String
}

struct CapabilityRevocationRecord: Equatable {
    static let maxEntries = 1_024

    var iss: String
    var seq: UInt64
    var issuedAtMillis: Int64
    var entries: [CapabilityRevocationEntry]

    func validate() throws {
        guard CapabilityGrantClaims.isBounded(
            iss,
            maximum: CapabilityGrantClaims.maxIdentifierBytes
        ) else {
            throw CapabilityAccessError.invalidRevocation("issuer")
        }
        guard seq >= 1 else {
            throw CapabilityAccessError.invalidRevocation("sequence")
        }
        guard issuedAtMillis >= 0 else {
            throw CapabilityAccessError.invalidRevocation("issued_at")
        }
        guard entries.count <= Self.maxEntries else {
            throw CapabilityAccessError.invalidRevocation("too many entries")
        }
        var seen: Set<String> = []
        for entry in entries {
            guard CapabilityGrantClaims.isBounded(
                entry.ref,
                maximum: CapabilityGrantClaims.maxIdentifierBytes
            ) else {
                throw CapabilityAccessError.invalidRevocation("reference")
            }
            guard !entry.reason.isEmpty, entry.reason.utf8.count <= 256 else {
                throw CapabilityAccessError.invalidRevocation("reason")
            }
            guard entry.atMillis >= 0, entry.atMillis <= issuedAtMillis else {
                throw CapabilityAccessError.invalidRevocation("entry time")
            }
            guard seen.insert("\(entry.kind.rawValue):\(entry.ref)").inserted else {
                throw CapabilityAccessError.invalidRevocation("duplicate entry")
            }
        }
    }
}

final class CapabilityRevocationStore {
    private var records: [String: CapabilityRevocationRecord] = [:]
    private let trustedIssuers: Set<String>?

    init(trustedIssuers: Set<String>? = nil) {
        self.trustedIssuers = trustedIssuers
    }

    @discardableResult
    func add(_ record: CapabilityRevocationRecord) throws -> Bool {
        try record.validate()
        if let trustedIssuers, !trustedIssuers.contains(record.iss) {
            throw CapabilityAccessError.issuerMismatch
        }
        if let existing = records[record.iss] {
            guard record.seq >= existing.seq else {
                throw CapabilityAccessError.revocationStale
            }
            if record.seq == existing.seq {
                guard record == existing else {
                    throw CapabilityAccessError.invalidRevocation(
                        "conflicting records for one sequence"
                    )
                }
                return false
            }
            let next = Set(record.entries.map { "\($0.kind.rawValue):\($0.ref)" })
            for previous in existing.entries {
                guard next.contains("\(previous.kind.rawValue):\(previous.ref)") else {
                    throw CapabilityAccessError.invalidRevocation(
                        "record drops a prior entry"
                    )
                }
            }
        }
        records[record.iss] = record
        return true
    }

    func latest(issuer: String) -> CapabilityRevocationRecord? {
        records[issuer]
    }

    func assertNotRevoked(
        ref: String,
        kind: CapabilityRevocationKind,
        issuer: String,
        nowMillis: Int64,
        maxStalenessMillis: Int64,
        maxFutureSkewMillis: Int64
    ) throws {
        guard CapabilityGrantClaims.isBounded(
            ref,
            maximum: CapabilityGrantClaims.maxIdentifierBytes
        ) else {
            throw CapabilityAccessError.invalidRevocation("reference")
        }
        guard maxStalenessMillis >= 0 else {
            throw CapabilityAccessError.revocationStale
        }
        guard let latest = records[issuer] else {
            throw CapabilityAccessError.revocationStale
        }
        let age = nowMillis - latest.issuedAtMillis
        if age < 0, -age > maxFutureSkewMillis {
            throw CapabilityAccessError.revocationStale
        }
        if age > maxStalenessMillis {
            throw CapabilityAccessError.revocationStale
        }
        if latest.entries.contains(where: { $0.kind == kind && $0.ref == ref }) {
            throw CapabilityAccessError.revoked
        }
    }
}

struct CapabilityAuthorizationPolicy: Equatable {
    var providerDeviceId: String
    var approvedRootIssuers: Set<String>
    var revocationIssuer: String
    var maxRevocationStalenessMillis: Int64
    var requireProofOfPossession = false
    var maxFutureSkewMillis: Int64 = 300_000

    func validate() throws {
        guard CapabilityGrantClaims.isBounded(
            providerDeviceId,
            maximum: CapabilityGrantClaims.maxIdentifierBytes
        ),
        CapabilityGrantClaims.isBounded(
            revocationIssuer,
            maximum: CapabilityGrantClaims.maxIdentifierBytes
        ),
        !approvedRootIssuers.isEmpty,
        maxRevocationStalenessMillis >= 0,
        maxFutureSkewMillis >= 0 else {
            throw CapabilityAccessError.invalidLease("authorization policy")
        }
    }
}

struct CapabilityPossessionProof: Equatable {
    var algorithm: DeviceIdentityAlgorithm
    var signature: Data
    var nonce: Data?
}

struct CapabilityPossessionEvidence: Equatable {
    var proof: CapabilityPossessionProof
    var publicKey: DevicePublicKey
    var requestNonce: Data?
}

enum CapabilityPossession {
    static let domain = Data("AD-CAP-POP-1".utf8)

    static func challenge(grant: CapabilityGrant, nonce: Data?) -> Data {
        var data = domain
        data.append(grant.tokenHash)
        if let nonce {
            data.append(nonce)
        }
        return data
    }

    static func confirmationThumbprint(_ publicKey: DevicePublicKey) -> String {
        PairingEncoding.base64URLString(
            Data(SHA256.hash(data: publicKey.spki))
        )
    }

    static func sign(
        grant: CapabilityGrant,
        identity: DeviceIdentity,
        nonce: Data? = nil
    ) throws -> CapabilityPossessionEvidence {
        let signature = try identity.sign(challenge(grant: grant, nonce: nonce))
        return CapabilityPossessionEvidence(
            proof: CapabilityPossessionProof(
                algorithm: identity.algorithm,
                signature: signature,
                nonce: nonce
            ),
            publicKey: identity.publicKey,
            requestNonce: nonce
        )
    }

    static func verify(
        grant: CapabilityGrant,
        evidence: CapabilityPossessionEvidence
    ) throws {
        let expected = confirmationThumbprint(evidence.publicKey)
        guard grant.claims.cnf == expected else {
            throw CapabilityAccessError.confirmationMismatch
        }
        guard evidence.proof.algorithm == evidence.publicKey.algorithm,
              evidence.proof.signature.count <= 128 else {
            throw CapabilityAccessError.proofMismatch
        }
        if let requestNonce = evidence.requestNonce,
           let proofNonce = evidence.proof.nonce,
           requestNonce != proofNonce {
            throw CapabilityAccessError.proofMismatch
        }
        let nonce = evidence.requestNonce ?? evidence.proof.nonce
        guard evidence.publicKey.verify(
            signature: evidence.proof.signature,
            for: challenge(grant: grant, nonce: nonce)
        ) else {
            throw CapabilityAccessError.proofMismatch
        }
    }
}

struct CapabilityAuthorizationRequest: Equatable {
    var chain: [CapabilityGrant]
    var leaseId: String
    var workspaceId: String
    var applicationId: String
    var requesterDeviceId: String
    var sessionId: String
    var capUri: String
    var operation: String
    var epochId: UInt64
    var nowMillis: Int64
    var possession: CapabilityPossessionEvidence?
}

struct CapabilityAuthorizationResult: Equatable {
    var chain: [CapabilityGrant]
    var root: CapabilityGrant
    var grant: CapabilityGrant
    var lease: CapabilityGrantLease
}

final class CapabilityAuthorizer {
    static let maxChainDepth = 3

    private let policy: CapabilityAuthorizationPolicy
    private let leases: CapabilityLeaseManager
    private let revocations: CapabilityRevocationStore

    init(
        policy: CapabilityAuthorizationPolicy,
        leases: CapabilityLeaseManager,
        revocations: CapabilityRevocationStore
    ) throws {
        try policy.validate()
        self.policy = policy
        self.leases = leases
        self.revocations = revocations
    }

    func authorize(
        _ request: CapabilityAuthorizationRequest
    ) throws -> CapabilityAuthorizationResult {
        guard !request.chain.isEmpty else {
            throw CapabilityAccessError.invalidGrant("chain is empty")
        }
        guard request.chain.count <= Self.maxChainDepth else {
            throw CapabilityAccessError.chainTooDeep
        }

        for grant in request.chain {
            try validateGrantWindow(grant, request: request)
            guard grant.claims.aud == policy.providerDeviceId else {
                throw CapabilityAccessError.audienceMismatch
            }
            guard grant.claims.epochId == request.epochId else {
                throw CapabilityAccessError.epochMismatch
            }
        }

        let root = request.chain[0]
        guard root.claims.parent == nil else {
            throw CapabilityAccessError.issuerChainMismatch
        }
        guard policy.approvedRootIssuers.contains(root.claims.iss) else {
            throw CapabilityAccessError.rootIssuerNotApproved
        }
        for index in 1..<request.chain.count {
            try validateLink(parent: request.chain[index - 1], child: request.chain[index])
        }

        let grant = request.chain[request.chain.count - 1]
        guard grant.claims.capUri == request.capUri,
              grant.claims.operations.contains(request.operation) else {
            throw CapabilityAccessError.operationNotGranted(request.operation)
        }

        try revocations.assertNotRevoked(
            ref: grant.claims.jti,
            kind: .grant,
            issuer: policy.revocationIssuer,
            nowMillis: request.nowMillis,
            maxStalenessMillis: policy.maxRevocationStalenessMillis,
            maxFutureSkewMillis: policy.maxFutureSkewMillis
        )
        try revocations.assertNotRevoked(
            ref: request.leaseId,
            kind: .lease,
            issuer: policy.revocationIssuer,
            nowMillis: request.nowMillis,
            maxStalenessMillis: policy.maxRevocationStalenessMillis,
            maxFutureSkewMillis: policy.maxFutureSkewMillis
        )

        guard let lease = leases.lease(id: request.leaseId) else {
            throw CapabilityAccessError.leaseNotActive(request.leaseId)
        }
        try validateLease(lease, grant: grant, request: request)

        if grant.claims.cnf != nil || policy.requireProofOfPossession {
            guard let possession = request.possession else {
                throw CapabilityAccessError.missingProof
            }
            try CapabilityPossession.verify(grant: grant, evidence: possession)
        }

        return CapabilityAuthorizationResult(
            chain: request.chain,
            root: root,
            grant: grant,
            lease: lease
        )
    }

    private func validateGrantWindow(
        _ grant: CapabilityGrant,
        request: CapabilityAuthorizationRequest
    ) throws {
        guard request.nowMillis >= grant.claims.notBeforeMillis else {
            throw CapabilityAccessError.notYetValid
        }
        guard request.nowMillis < grant.claims.expiresAtMillis else {
            throw CapabilityAccessError.expired
        }
    }

    private func validateLink(parent: CapabilityGrant, child: CapabilityGrant) throws {
        guard child.claims.iss == parent.claims.sub else {
            throw CapabilityAccessError.issuerChainMismatch
        }
        guard child.claims.parent == parent.tokenHashBase64URL else {
            throw CapabilityAccessError.parentMismatch
        }
        guard child.claims.aud == parent.claims.aud,
              child.claims.epochId == parent.claims.epochId else {
            throw CapabilityAccessError.attenuationWidened
        }
        guard child.claims.notBeforeMillis >= parent.claims.notBeforeMillis,
              child.claims.expiresAtMillis <= parent.claims.expiresAtMillis else {
            throw CapabilityAccessError.attenuationWidened
        }
        guard isCapabilityAttenuated(parent: parent.claims.capUri, child: child.claims.capUri) else {
            throw CapabilityAccessError.attenuationWidened
        }
        let allowed = Set(parent.claims.operations)
        guard child.claims.operations.allSatisfy(allowed.contains) else {
            throw CapabilityAccessError.attenuationWidened
        }
    }

    private func validateLease(
        _ lease: CapabilityGrantLease,
        grant: CapabilityGrant,
        request: CapabilityAuthorizationRequest
    ) throws {
        guard !lease.revoked else {
            throw CapabilityAccessError.leaseRevoked
        }
        guard request.nowMillis >= lease.issuedAtMillis else {
            throw CapabilityAccessError.notYetValid
        }
        guard request.nowMillis < lease.expiresAtMillis else {
            throw CapabilityAccessError.leaseExpired
        }
        guard lease.grantJti == grant.claims.jti,
              lease.capUri == grant.claims.capUri,
              lease.epochId == grant.claims.epochId else {
            throw CapabilityAccessError.invalidLease("lease does not match its grant")
        }
        guard lease.expiresAtMillis <= grant.claims.expiresAtMillis,
              lease.issuedAtMillis >= grant.claims.notBeforeMillis else {
            throw CapabilityAccessError.invalidLease("lease outlives its grant")
        }
        let granted = Set(grant.claims.operations)
        guard lease.operations.allSatisfy(granted.contains) else {
            throw CapabilityAccessError.invalidLease("lease operations exceed the grant")
        }
        guard lease.workspaceId == request.workspaceId,
              lease.applicationId == request.applicationId,
              lease.requesterDeviceId == request.requesterDeviceId,
              lease.sessionId == request.sessionId else {
            throw CapabilityAccessError.invalidLease("lease request context mismatch")
        }
        guard lease.capUri == request.capUri,
              lease.operations.contains(request.operation) else {
            throw CapabilityAccessError.operationNotGranted(request.operation)
        }
    }

    private func isCapabilityAttenuated(parent: String, child: String) -> Bool {
        child == parent || child.hasPrefix(parent + "/")
    }
}
