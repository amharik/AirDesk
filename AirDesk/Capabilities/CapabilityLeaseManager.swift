import CryptoKit
import Foundation

enum CapabilityAccessError: Error, Equatable, LocalizedError {
    case invalidGrant(String)
    case invalidLease(String)
    case grantSignatureInvalid
    case grantTokenMismatch
    case issuerMismatch
    case audienceMismatch
    case issuerChainMismatch
    case parentMismatch
    case chainTooDeep
    case rootIssuerNotApproved
    case attenuationWidened
    case notYetValid
    case expired
    case revoked
    case epochMismatch
    case operationNotGranted(String)
    case leaseNotActive(String)
    case leaseRevoked
    case leaseExpired
    case missingProof
    case proofMismatch
    case confirmationMismatch
    case revocationStale
    case invalidRevocation(String)
    case handlerUnavailable

    var code: String {
        switch self {
        case .invalidGrant: return "invalid-grant"
        case .invalidLease: return "invalid-lease"
        case .grantSignatureInvalid: return "invalid-signature"
        case .grantTokenMismatch: return "grant-token-mismatch"
        case .issuerMismatch: return "issuer-mismatch"
        case .audienceMismatch: return "audience-mismatch"
        case .issuerChainMismatch: return "chain-mismatch"
        case .parentMismatch: return "parent-mismatch"
        case .chainTooDeep: return "chain-too-deep"
        case .rootIssuerNotApproved: return "root-issuer-not-approved"
        case .attenuationWidened: return "attenuation-widened"
        case .notYetValid: return "not-yet-valid"
        case .expired: return "expired"
        case .revoked: return "revoked"
        case .epochMismatch: return "epoch-mismatch"
        case .operationNotGranted: return "operation-not-granted"
        case .leaseNotActive: return "lease-not-active"
        case .leaseRevoked: return "revoked"
        case .leaseExpired: return "expired"
        case .missingProof: return "missing-proof"
        case .proofMismatch: return "proof-mismatch"
        case .confirmationMismatch: return "confirmation-mismatch"
        case .revocationStale: return "revocation-stale"
        case .invalidRevocation: return "invalid-revocation"
        case .handlerUnavailable: return "handler-unavailable"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidGrant(let reason):
            return "InvalidGrant: \(reason)"
        case .invalidLease(let reason):
            return "InvalidLease: \(reason)"
        case .grantSignatureInvalid:
            return "InvalidSignature: the capability grant signature is invalid."
        case .grantTokenMismatch:
            return "GrantTokenMismatch: the claims do not match the signed grant token."
        case .issuerMismatch:
            return "IssuerMismatch: the grant issuer does not match its signing key."
        case .audienceMismatch:
            return "AudienceMismatch: the grant is not addressed to this provider."
        case .issuerChainMismatch:
            return "ChainMismatch: a delegated grant issuer does not match its parent subject."
        case .parentMismatch:
            return "ParentMismatch: the delegated grant parent hash is invalid."
        case .chainTooDeep:
            return "ChainTooDeep: the capability grant chain exceeds its depth limit."
        case .rootIssuerNotApproved:
            return "RootIssuerNotApproved: the root grant issuer is not approved by this provider."
        case .attenuationWidened:
            return "AttenuationWidened: a delegated grant exceeds its parent authority."
        case .notYetValid:
            return "NotYetValid: the capability grant or lease is not yet valid."
        case .expired:
            return "Expired: the capability grant or lease has expired."
        case .revoked:
            return "Revoked: the capability grant or lease was revoked."
        case .epochMismatch:
            return "EpochMismatch: the capability epoch does not match the request."
        case .operationNotGranted(let operation):
            return "OperationNotGranted: the capability does not allow \(operation)."
        case .leaseNotActive(let leaseId):
            return "LeaseNotActive: the capability lease \(leaseId) is not active."
        case .leaseRevoked:
            return "LeaseRevoked: the capability lease was revoked."
        case .leaseExpired:
            return "LeaseExpired: the capability lease has expired."
        case .missingProof:
            return "MissingProof: proof of possession is required for this capability."
        case .proofMismatch:
            return "ProofMismatch: the proof of possession is invalid."
        case .confirmationMismatch:
            return "ConfirmationMismatch: the proof key does not match the grant confirmation."
        case .revocationStale:
            return "RevocationStale: no fresh revocation record is available."
        case .invalidRevocation(let reason):
            return "InvalidRevocation: \(reason)"
        case .handlerUnavailable:
            return "HandlerUnavailable: no capability invocation handler is installed."
        }
    }
}

struct CapabilityGrantClaims: Equatable {
    static let maxIdentifierBytes = 256
    static let maxCapabilityURIBytes = 512
    static let maxOperationBytes = 64
    static let maxOperations = 32

    var iss: String
    var sub: String
    var aud: String
    var jti: String
    var capUri: String
    var operations: [String]
    var notBeforeMillis: Int64
    var expiresAtMillis: Int64
    var epochId: UInt64
    var cnf: String?
    var parent: String?

    func validate() throws {
        for (label, value) in [
            ("iss", iss),
            ("sub", sub),
            ("aud", aud),
            ("jti", jti)
        ] {
            guard Self.isBounded(value, maximum: Self.maxIdentifierBytes) else {
                throw CapabilityAccessError.invalidGrant(label)
            }
        }
        guard Self.isBounded(capUri, maximum: Self.maxCapabilityURIBytes),
              Self.isCapabilityURI(capUri) else {
            throw CapabilityAccessError.invalidGrant("cap_uri")
        }
        guard !operations.isEmpty, operations.count <= Self.maxOperations else {
            throw CapabilityAccessError.invalidGrant("op")
        }
        var seen: Set<String> = []
        for operation in operations {
            guard Self.isBounded(operation, maximum: Self.maxOperationBytes),
                  seen.insert(operation).inserted else {
                throw CapabilityAccessError.invalidGrant("op")
            }
        }
        guard notBeforeMillis >= 0, expiresAtMillis > notBeforeMillis else {
            throw CapabilityAccessError.invalidGrant("validity")
        }
        if let cnf {
            guard Self.isDigest(cnf) else {
                throw CapabilityAccessError.invalidGrant("cnf")
            }
        }
        if let parent {
            guard Self.isDigest(parent) else {
                throw CapabilityAccessError.invalidGrant("parent")
            }
        }
    }

    static func isCapabilityURI(_ value: String) -> Bool {
        guard value.hasPrefix("airdesk://") else { return false }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~-:/"
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func isDigest(_ value: String) -> Bool {
        guard let data = PairingEncoding.data(base64URL: value) else { return false }
        return data.count == 32
    }

    static func isBounded(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximum && !value.contains("\0")
    }
}

struct CapabilityGrant: Equatable {
    let claims: CapabilityGrantClaims
    let token: Data
    let tokenHash: Data
    let issuerKey: DevicePublicKey
    let signature: Data

    init(claims: CapabilityGrantClaims, issuer: DeviceIdentity) throws {
        try claims.validate()
        let token = CapabilityGrantCodec.encode(claims)
        let signature = try issuer.sign(token)
        try self.init(
            claims: claims,
            token: token,
            issuerKey: issuer.publicKey,
            signature: signature
        )
    }

    init(
        claims: CapabilityGrantClaims,
        token: Data,
        issuerKey: DevicePublicKey,
        signature: Data
    ) throws {
        try claims.validate()
        guard CapabilityGrantCodec.encode(claims) == token else {
            throw CapabilityAccessError.grantTokenMismatch
        }
        guard issuerKey.deviceId == claims.iss else {
            throw CapabilityAccessError.issuerMismatch
        }
        guard !signature.isEmpty, issuerKey.verify(signature: signature, for: token) else {
            throw CapabilityAccessError.grantSignatureInvalid
        }
        self.claims = claims
        self.token = token
        self.tokenHash = Data(SHA256.hash(data: token))
        self.issuerKey = issuerKey
        self.signature = signature
    }

    var tokenHashBase64URL: String {
        PairingEncoding.base64URLString(tokenHash)
    }
}

enum CapabilityGrantCodec {
    static let version: UInt8 = 1

    static func encode(_ claims: CapabilityGrantClaims) -> Data {
        var data = Data([version])
        append(claims.iss, to: &data)
        append(claims.sub, to: &data)
        append(claims.aud, to: &data)
        append(claims.jti, to: &data)
        append(claims.capUri, to: &data)
        append(UInt32(claims.operations.count), to: &data)
        for operation in claims.operations {
            append(operation, to: &data)
        }
        append(claims.notBeforeMillis, to: &data)
        append(claims.expiresAtMillis, to: &data)
        append(claims.epochId, to: &data)
        append(claims.cnf, to: &data)
        append(claims.parent, to: &data)
        return data
    }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        append(UInt32(bytes.count), to: &data)
        data.append(bytes)
    }

    private static func append(_ value: String?, to data: inout Data) {
        guard let value else {
            data.append(0)
            return
        }
        data.append(1)
        append(value, to: &data)
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: Int64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}

struct CapabilityGrantLease: Equatable {
    var leaseId: String
    var grantJti: String
    var capUri: String
    var workspaceId: String
    var applicationId: String
    var requesterDeviceId: String
    var sessionId: String
    var operations: [String]
    var issuedAtMillis: Int64
    var expiresAtMillis: Int64
    var epochId: UInt64
    var auditId: String
    var revoked: Bool = false
    var revocationReason: String?

    func validate() throws {
        for (label, value) in [
            ("leaseId", leaseId),
            ("grantJti", grantJti),
            ("workspaceId", workspaceId),
            ("applicationId", applicationId),
            ("requesterDeviceId", requesterDeviceId),
            ("sessionId", sessionId),
            ("auditId", auditId)
        ] {
            guard CapabilityGrantClaims.isBounded(
                value,
                maximum: CapabilityGrantClaims.maxIdentifierBytes
            ) else {
                throw CapabilityAccessError.invalidLease(label)
            }
        }
        guard CapabilityGrantClaims.isCapabilityURI(capUri) else {
            throw CapabilityAccessError.invalidLease("capUri")
        }
        guard !operations.isEmpty,
              operations.count <= CapabilityGrantClaims.maxOperations,
              Set(operations).count == operations.count,
              operations.allSatisfy({
                  CapabilityGrantClaims.isBounded(
                      $0,
                      maximum: CapabilityGrantClaims.maxOperationBytes
                  )
              }) else {
            throw CapabilityAccessError.invalidLease("operations")
        }
        guard expiresAtMillis > issuedAtMillis else {
            throw CapabilityAccessError.invalidLease("validity")
        }
        if let revocationReason, revocationReason.utf8.count > 256 {
            throw CapabilityAccessError.invalidLease("revocationReason")
        }
    }
}

struct CapabilityLeaseIssueRequest: Equatable {
    var leaseId: String
    var workspaceId: String
    var applicationId: String
    var requesterDeviceId: String
    var sessionId: String
    var operations: [String]
    var issuedAtMillis: Int64
    var expiresAtMillis: Int64
    var auditId: String
}

final class CapabilityLeaseManager {
    private var leases: [String: CapabilityGrantLease] = [:]
    private let now: () -> Int64

    init(now: @escaping () -> Int64 = {
        Int64(Date().timeIntervalSince1970 * 1000)
    }) {
        self.now = now
    }

    func issue(
        grant: CapabilityGrant,
        request: CapabilityLeaseIssueRequest
    ) throws -> CapabilityGrantLease {
        let claims = grant.claims
        let issuedAt = request.issuedAtMillis
        let expiresAt = request.expiresAtMillis
        guard issuedAt >= claims.notBeforeMillis else {
            throw CapabilityAccessError.notYetValid
        }
        guard expiresAt <= claims.expiresAtMillis else {
            throw CapabilityAccessError.invalidLease("lease outlives its grant")
        }
        guard expiresAt > issuedAt else {
            throw CapabilityAccessError.invalidLease("validity")
        }
        guard request.operations.allSatisfy(claims.operations.contains) else {
            throw CapabilityAccessError.invalidLease("operations exceed the grant")
        }
        guard leases[request.leaseId] == nil else {
            throw CapabilityAccessError.invalidLease("lease id is already active")
        }

        let lease = CapabilityGrantLease(
            leaseId: request.leaseId,
            grantJti: claims.jti,
            capUri: claims.capUri,
            workspaceId: request.workspaceId,
            applicationId: request.applicationId,
            requesterDeviceId: request.requesterDeviceId,
            sessionId: request.sessionId,
            operations: request.operations,
            issuedAtMillis: issuedAt,
            expiresAtMillis: expiresAt,
            epochId: claims.epochId,
            auditId: request.auditId
        )
        try lease.validate()
        leases[lease.leaseId] = lease
        return lease
    }

    func lease(id: String) -> CapabilityGrantLease? {
        leases[id]
    }

    func activeLeases(now: Int64? = nil) -> [CapabilityGrantLease] {
        let current = now ?? self.now()
        return leases.values
            .filter { !$0.revoked && current < $0.expiresAtMillis }
            .sorted { $0.leaseId < $1.leaseId }
    }

    @discardableResult
    func revoke(leaseId: String, reason: String = "Revoked") -> Bool {
        guard var lease = leases[leaseId] else { return false }
        lease.revoked = true
        lease.revocationReason = reason
        leases[leaseId] = lease
        return true
    }

    @discardableResult
    func remove(leaseId: String) -> Bool {
        leases.removeValue(forKey: leaseId) != nil
    }

    @discardableResult
    func purgeExpired(now: Int64? = nil) -> Int {
        let current = now ?? self.now()
        let expired = leases.filter { current >= $0.value.expiresAtMillis }.map(\.key)
        for id in expired {
            leases.removeValue(forKey: id)
        }
        return expired.count
    }
}
