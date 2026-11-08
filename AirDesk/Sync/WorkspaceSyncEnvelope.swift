import CryptoKit
import Foundation

struct WorkspaceSyncEnvelope: Codable, Equatable, Sendable {
    static let version = 1

    let version: Int
    let workspaceId: String
    let senderDeviceId: String
    let hostEpoch: UInt64
    let syncSeq: UInt64
    let nonce: String
    let ciphertext: String
    let aad: String
}

enum WorkspaceSyncEnvelopeError: Error, Equatable, LocalizedError {
    case invalidEnvelope(String)
    case unsupportedVersion
    case workspaceMismatch
    case epochMismatch
    case deviceMismatch
    case senderRevoked
    case staleSequence
    case truncatedCiphertext
    case authenticationFailed
    case invalidKey(String)

    var code: String {
        switch self {
        case .invalidEnvelope: return "InvalidEnvelope"
        case .unsupportedVersion: return "UnsupportedVersion"
        case .workspaceMismatch: return "WorkspaceMismatch"
        case .epochMismatch: return "EpochMismatch"
        case .deviceMismatch: return "DeviceMismatch"
        case .senderRevoked: return "SenderRevoked"
        case .staleSequence: return "StaleSequence"
        case .truncatedCiphertext: return "TruncatedCiphertext"
        case .authenticationFailed: return "AuthenticationFailed"
        case .invalidKey: return "InvalidSyncKey"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope(let detail):
            return "InvalidEnvelope: \(detail)"
        case .unsupportedVersion:
            return "UnsupportedVersion: unsupported envelope version."
        case .workspaceMismatch:
            return "WorkspaceMismatch: envelope belongs to another workspace."
        case .epochMismatch:
            return "EpochMismatch: envelope belongs to another host epoch."
        case .deviceMismatch:
            return "DeviceMismatch: envelope sender device does not match."
        case .senderRevoked:
            return "SenderRevoked: envelope sender device is revoked."
        case .staleSequence:
            return "StaleSequence: envelope sequence was already applied."
        case .truncatedCiphertext:
            return "TruncatedCiphertext: ciphertext is shorter than its tag."
        case .authenticationFailed:
            return "AuthenticationFailed: envelope authentication failed for this key and metadata."
        case .invalidKey(let detail):
            return "InvalidSyncKey: \(detail)"
        }
    }
}

struct WorkspaceSyncExpectations: Sendable {
    let workspaceId: String
    let hostEpoch: UInt64
    let senderDeviceId: String?
    let revokedSenderDeviceIds: Set<String>
    let lastSyncSeq: UInt64?

    init(
        workspaceId: String,
        hostEpoch: UInt64,
        senderDeviceId: String? = nil,
        revokedSenderDeviceIds: Set<String> = [],
        lastSyncSeq: UInt64? = nil
    ) {
        self.workspaceId = workspaceId
        self.hostEpoch = hostEpoch
        self.senderDeviceId = senderDeviceId
        self.revokedSenderDeviceIds = revokedSenderDeviceIds
        self.lastSyncSeq = lastSyncSeq
    }
}

enum WorkspaceSyncCrypto {
    static let nonceBytes = 12
    static let tagBytes = 16
    static let keyBytes = 32
    static let minimumSecretBytes = 16

    static func importKey(_ rawKey: Data) throws -> SymmetricKey {
        guard rawKey.count == keyBytes else {
            throw WorkspaceSyncEnvelopeError.invalidKey("a workspace sync key must be \(keyBytes) bytes.")
        }
        return SymmetricKey(data: rawKey)
    }

    static func derivePairingKey(secret: Data) throws -> SymmetricKey {
        guard secret.count >= minimumSecretBytes else {
            throw WorkspaceSyncEnvelopeError.invalidKey("workspace sync key material is too short.")
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data("airdesk.sync.v1".utf8),
            info: Data("pairing-workspace-sync".utf8),
            outputByteCount: keyBytes
        )
    }

    static func deriveKey(secret: Data, workspaceId: String) throws -> SymmetricKey {
        guard secret.count >= minimumSecretBytes else {
            throw WorkspaceSyncEnvelopeError.invalidKey("workspace sync key material is too short.")
        }
        guard !workspaceId.isEmpty else {
            throw WorkspaceSyncEnvelopeError.invalidKey("a workspace identifier is required.")
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data("airdesk.sync.v1".utf8),
            info: Data("workspace:\(workspaceId)".utf8),
            outputByteCount: keyBytes
        )
    }

    static func encrypt(
        key: SymmetricKey,
        workspaceId: String,
        senderDeviceId: String,
        hostEpoch: UInt64,
        syncSeq: UInt64,
        plaintext: Data,
        aad: Data = Data(),
        nonce: Data? = nil
    ) throws -> WorkspaceSyncEnvelope {
        guard !workspaceId.isEmpty, !senderDeviceId.isEmpty else {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("workspace and sender device are required.")
        }
        let nonceData = nonce ?? Data((0..<nonceBytes).map { _ in UInt8.random(in: 0...255) })
        guard nonceData.count == nonceBytes else {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("nonce must be \(nonceBytes) bytes.")
        }

        let encodedAad = aad.isEmpty ? "" : Data(aad).base64EncodedString()
        let header = WorkspaceSyncEnvelope(
            version: WorkspaceSyncEnvelope.version,
            workspaceId: workspaceId,
            senderDeviceId: senderDeviceId,
            hostEpoch: hostEpoch,
            syncSeq: syncSeq,
            nonce: nonceData.base64EncodedString(),
            ciphertext: "",
            aad: encodedAad
        )
        let additionalData = try canonicalAad(for: header)

        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: try AES.GCM.Nonce(data: nonceData),
                authenticating: additionalData
            )
        } catch {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("could not encrypt the payload.")
        }

        var ciphertext = Data(sealed.ciphertext)
        ciphertext.append(sealed.tag)
        return WorkspaceSyncEnvelope(
            version: header.version,
            workspaceId: header.workspaceId,
            senderDeviceId: header.senderDeviceId,
            hostEpoch: header.hostEpoch,
            syncSeq: header.syncSeq,
            nonce: header.nonce,
            ciphertext: ciphertext.base64EncodedString(),
            aad: header.aad
        )
    }

    static func validateMetadata(
        _ envelope: WorkspaceSyncEnvelope,
        expected: WorkspaceSyncExpectations
    ) throws {
        guard envelope.version == WorkspaceSyncEnvelope.version else {
            throw WorkspaceSyncEnvelopeError.unsupportedVersion
        }
        guard !envelope.workspaceId.isEmpty, !envelope.senderDeviceId.isEmpty else {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("workspace and sender device are required.")
        }
        guard envelope.workspaceId == expected.workspaceId else {
            throw WorkspaceSyncEnvelopeError.workspaceMismatch
        }
        guard envelope.hostEpoch == expected.hostEpoch else {
            throw WorkspaceSyncEnvelopeError.epochMismatch
        }
        if let senderDeviceId = expected.senderDeviceId,
           envelope.senderDeviceId != senderDeviceId {
            throw WorkspaceSyncEnvelopeError.deviceMismatch
        }
        if expected.revokedSenderDeviceIds.contains(envelope.senderDeviceId) {
            throw WorkspaceSyncEnvelopeError.senderRevoked
        }
        if let lastSyncSeq = expected.lastSyncSeq, envelope.syncSeq <= lastSyncSeq {
            throw WorkspaceSyncEnvelopeError.staleSequence
        }
    }

    static func decrypt(
        key: SymmetricKey,
        envelope: WorkspaceSyncEnvelope,
        expected: WorkspaceSyncExpectations
    ) throws -> Data {
        try validateMetadata(envelope, expected: expected)

        guard let nonce = Data(base64Encoded: envelope.nonce) else {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("nonce is not valid base64.")
        }
        guard nonce.count == nonceBytes else {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("nonce must be \(nonceBytes) bytes.")
        }
        guard let ciphertext = Data(base64Encoded: envelope.ciphertext) else {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("ciphertext is not valid base64.")
        }
        guard ciphertext.count >= tagBytes else {
            throw WorkspaceSyncEnvelopeError.truncatedCiphertext
        }

        let body = ciphertext.prefix(ciphertext.count - tagBytes)
        let tag = ciphertext.suffix(tagBytes)
        let additionalData = try canonicalAad(for: envelope)
        do {
            let sealed = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: nonce),
                ciphertext: body,
                tag: tag
            )
            return try AES.GCM.open(sealed, using: key, authenticating: additionalData)
        } catch {
            throw WorkspaceSyncEnvelopeError.authenticationFailed
        }
    }

    static func canonicalAad(for envelope: WorkspaceSyncEnvelope) throws -> Data {
        let values: [Any] = [
            envelope.version,
            envelope.workspaceId,
            envelope.senderDeviceId,
            NSNumber(value: envelope.hostEpoch),
            NSNumber(value: envelope.syncSeq),
            envelope.aad
        ]
        do {
            return try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        } catch {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("could not encode authenticated metadata.")
        }
    }
}
