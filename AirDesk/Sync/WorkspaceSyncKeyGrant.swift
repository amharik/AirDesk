import CryptoKit
import Foundation

struct WorkspaceSyncKeyGrant: Codable, Equatable, Sendable {
    static let version = 1
    static let kind = "workspace-key-grant"

    let version: Int
    let kind: String
    let workspaceId: String
    let issuerDeviceId: String
    let generation: UInt64
    let nonce: String
    let ciphertext: String
}

enum WorkspaceSyncKeyGrantError: Error, Equatable, LocalizedError {
    case invalidMessage(String)
    case unsupportedVersion
    case invalidKind
    case workspaceMismatch
    case invalidIssuer
    case invalidKey
    case authenticationFailed

    var code: String {
        switch self {
        case .invalidMessage: return "InvalidKeyGrant"
        case .unsupportedVersion: return "UnsupportedVersion"
        case .invalidKind: return "InvalidKeyGrant"
        case .workspaceMismatch: return "WorkspaceMismatch"
        case .invalidIssuer: return "InvalidIssuer"
        case .invalidKey: return "InvalidSyncKey"
        case .authenticationFailed: return "AuthenticationFailed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidMessage(let detail):
            return "InvalidKeyGrant: \(detail)"
        case .unsupportedVersion:
            return "UnsupportedVersion: unsupported workspace key grant version."
        case .invalidKind:
            return "InvalidKeyGrant: message is not a workspace key grant."
        case .workspaceMismatch:
            return "WorkspaceMismatch: key grant belongs to another workspace."
        case .invalidIssuer:
            return "InvalidIssuer: key grant issuer is not the expected paired device."
        case .invalidKey:
            return "InvalidSyncKey: granted workspace key material is invalid."
        case .authenticationFailed:
            return "AuthenticationFailed: key grant is not authenticated by the pairing key."
        }
    }
}

enum WorkspaceSyncKeyGrantCrypto {
    static let keyBytes = WorkspaceSyncCrypto.keyBytes
    static let nonceBytes = WorkspaceSyncCrypto.nonceBytes
    static let tagBytes = WorkspaceSyncCrypto.tagBytes

    static func grant(
        currentKey: SymmetricKey,
        bootstrapKey: SymmetricKey,
        workspaceId: String,
        issuerDeviceId: String,
        generation: UInt64,
        nonce: Data? = nil
    ) throws -> WorkspaceSyncKeyGrant {
        guard !workspaceId.isEmpty, !issuerDeviceId.isEmpty else {
            throw WorkspaceSyncKeyGrantError.invalidMessage(
                "workspace and issuer device are required."
            )
        }
        guard generation > 0 else {
            throw WorkspaceSyncKeyGrantError.invalidMessage("generation must be positive.")
        }
        let rawKey = currentKey.withUnsafeBytes { Data($0) }
        guard rawKey.count == keyBytes else {
            throw WorkspaceSyncKeyGrantError.invalidKey
        }
        let nonceData = nonce ?? Data((0..<nonceBytes).map { _ in UInt8.random(in: 0...255) })
        guard nonceData.count == nonceBytes else {
            throw WorkspaceSyncKeyGrantError.invalidMessage(
                "nonce must be \(nonceBytes) bytes."
            )
        }

        let header = WorkspaceSyncKeyGrant(
            version: WorkspaceSyncKeyGrant.version,
            kind: WorkspaceSyncKeyGrant.kind,
            workspaceId: workspaceId,
            issuerDeviceId: issuerDeviceId,
            generation: generation,
            nonce: nonceData.base64EncodedString(),
            ciphertext: ""
        )
        let sealed = try AES.GCM.seal(
            rawKey,
            using: bootstrapKey,
            nonce: try AES.GCM.Nonce(data: nonceData),
            authenticating: try canonicalAad(for: header)
        )
        var ciphertext = Data(sealed.ciphertext)
        ciphertext.append(sealed.tag)
        return WorkspaceSyncKeyGrant(
            version: header.version,
            kind: header.kind,
            workspaceId: header.workspaceId,
            issuerDeviceId: header.issuerDeviceId,
            generation: header.generation,
            nonce: header.nonce,
            ciphertext: ciphertext.base64EncodedString()
        )
    }

    static func decode(_ data: Data) throws -> WorkspaceSyncKeyGrant {
        let message: WorkspaceSyncKeyGrant
        do {
            message = try JSONDecoder().decode(WorkspaceSyncKeyGrant.self, from: data)
        } catch {
            throw WorkspaceSyncKeyGrantError.invalidMessage("message is not valid JSON.")
        }
        guard message.version == WorkspaceSyncKeyGrant.version else {
            throw WorkspaceSyncKeyGrantError.unsupportedVersion
        }
        guard message.kind == WorkspaceSyncKeyGrant.kind else {
            throw WorkspaceSyncKeyGrantError.invalidKind
        }
        guard !message.workspaceId.isEmpty, !message.issuerDeviceId.isEmpty else {
            throw WorkspaceSyncKeyGrantError.invalidMessage(
                "workspace and issuer device are required."
            )
        }
        guard message.generation > 0 else {
            throw WorkspaceSyncKeyGrantError.invalidMessage("generation must be positive.")
        }
        return message
    }

    static func accept(
        _ message: WorkspaceSyncKeyGrant,
        bootstrapKey: SymmetricKey,
        workspaceId: String,
        expectedIssuerDeviceId: String? = nil
    ) throws -> (key: SymmetricKey, generation: UInt64) {
        guard message.version == WorkspaceSyncKeyGrant.version else {
            throw WorkspaceSyncKeyGrantError.unsupportedVersion
        }
        guard message.kind == WorkspaceSyncKeyGrant.kind else {
            throw WorkspaceSyncKeyGrantError.invalidKind
        }
        guard message.workspaceId == workspaceId else {
            throw WorkspaceSyncKeyGrantError.workspaceMismatch
        }
        if let expectedIssuerDeviceId, message.issuerDeviceId != expectedIssuerDeviceId {
            throw WorkspaceSyncKeyGrantError.invalidIssuer
        }
        guard let nonce = Data(base64Encoded: message.nonce), nonce.count == nonceBytes else {
            throw WorkspaceSyncKeyGrantError.invalidMessage("nonce is not valid base64.")
        }
        guard let ciphertext = Data(base64Encoded: message.ciphertext),
              ciphertext.count >= tagBytes + keyBytes else {
            throw WorkspaceSyncKeyGrantError.invalidMessage(
                "ciphertext does not contain a workspace key."
            )
        }

        let body = ciphertext.prefix(ciphertext.count - tagBytes)
        let tag = ciphertext.suffix(tagBytes)
        let rawKey: Data
        do {
            let sealed = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: nonce),
                ciphertext: body,
                tag: tag
            )
            rawKey = try AES.GCM.open(
                sealed,
                using: bootstrapKey,
                authenticating: try canonicalAad(for: message)
            )
        } catch {
            throw WorkspaceSyncKeyGrantError.authenticationFailed
        }
        guard rawKey.count == keyBytes else {
            throw WorkspaceSyncKeyGrantError.invalidKey
        }
        return (SymmetricKey(data: rawKey), message.generation)
    }

    static func canonicalAad(for message: WorkspaceSyncKeyGrant) throws -> Data {
        let values: [Any] = [
            message.version,
            message.kind,
            message.workspaceId,
            message.issuerDeviceId,
            NSNumber(value: message.generation)
        ]
        do {
            return try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        } catch {
            throw WorkspaceSyncKeyGrantError.invalidMessage(
                "could not encode authenticated metadata."
            )
        }
    }
}
