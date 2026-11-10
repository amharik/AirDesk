import CryptoKit
import Foundation

struct WorkspaceSyncKeyRotation: Codable, Equatable, Sendable {
    static let version = 1
    static let kind = "workspace-key-rotation"

    let version: Int
    let kind: String
    let workspaceId: String
    let issuerDeviceId: String
    let generation: UInt64
    let nonce: String
    let ciphertext: String

    enum CodingKeys: String, CodingKey {
        case version
        case kind
        case workspaceId
        case issuerDeviceId
        case generation
        case nonce
        case ciphertext
    }
}

enum WorkspaceSyncKeyRotationError: Error, Equatable, LocalizedError {
    case invalidMessage(String)
    case unsupportedVersion
    case invalidKind
    case workspaceMismatch
    case generationReplay
    case generationGap
    case invalidIssuer
    case invalidKey
    case authenticationFailed

    var code: String {
        switch self {
        case .invalidMessage: return "InvalidKeyRotation"
        case .unsupportedVersion: return "UnsupportedVersion"
        case .invalidKind: return "InvalidKeyRotation"
        case .workspaceMismatch: return "WorkspaceMismatch"
        case .generationReplay: return "GenerationReplay"
        case .generationGap: return "GenerationGap"
        case .invalidIssuer: return "InvalidIssuer"
        case .invalidKey: return "InvalidSyncKey"
        case .authenticationFailed: return "AuthenticationFailed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidMessage(let detail):
            return "InvalidKeyRotation: \(detail)"
        case .unsupportedVersion:
            return "UnsupportedVersion: unsupported workspace key rotation version."
        case .invalidKind:
            return "InvalidKeyRotation: message is not a workspace key rotation."
        case .workspaceMismatch:
            return "WorkspaceMismatch: key rotation belongs to another workspace."
        case .generationReplay:
            return "GenerationReplay: key rotation generation was already seen."
        case .generationGap:
            return "GenerationGap: key rotation skipped a generation."
        case .invalidIssuer:
            return "InvalidIssuer: key rotation issuer is not the expected trusted device."
        case .invalidKey:
            return "InvalidSyncKey: rotated workspace key material is invalid."
        case .authenticationFailed:
            return "AuthenticationFailed: key rotation authentication failed for this workspace key."
        }
    }
}

enum WorkspaceSyncKeyRotationCrypto {
    static let keyBytes = WorkspaceSyncCrypto.keyBytes
    static let nonceBytes = WorkspaceSyncCrypto.nonceBytes
    static let tagBytes = WorkspaceSyncCrypto.tagBytes

    static func rotate(
        currentKey: SymmetricKey,
        workspaceId: String,
        issuerDeviceId: String,
        nextGeneration: UInt64,
        newKey: SymmetricKey? = nil,
        nonce: Data? = nil
    ) throws -> (key: SymmetricKey, message: WorkspaceSyncKeyRotation) {
        guard !workspaceId.isEmpty, !issuerDeviceId.isEmpty else {
            throw WorkspaceSyncKeyRotationError.invalidMessage(
                "workspace and issuer device are required."
            )
        }
        guard nextGeneration > 0 else {
            throw WorkspaceSyncKeyRotationError.invalidMessage("generation must be positive.")
        }

        let newKey = newKey ?? SymmetricKey(size: .bits256)
        let rawKey = newKey.withUnsafeBytes { Data($0) }
        guard rawKey.count == keyBytes else {
            throw WorkspaceSyncKeyRotationError.invalidKey
        }
        let nonceData = nonce ?? Data((0..<nonceBytes).map { _ in UInt8.random(in: 0...255) })
        guard nonceData.count == nonceBytes else {
            throw WorkspaceSyncKeyRotationError.invalidMessage(
                "nonce must be \(nonceBytes) bytes."
            )
        }

        let header = WorkspaceSyncKeyRotation(
            version: WorkspaceSyncKeyRotation.version,
            kind: WorkspaceSyncKeyRotation.kind,
            workspaceId: workspaceId,
            issuerDeviceId: issuerDeviceId,
            generation: nextGeneration,
            nonce: nonceData.base64EncodedString(),
            ciphertext: ""
        )
        let sealed = try AES.GCM.seal(
            rawKey,
            using: currentKey,
            nonce: try AES.GCM.Nonce(data: nonceData),
            authenticating: try canonicalAad(for: header)
        )
        var ciphertext = Data(sealed.ciphertext)
        ciphertext.append(sealed.tag)
        return (
            SymmetricKey(data: rawKey),
            WorkspaceSyncKeyRotation(
                version: header.version,
                kind: header.kind,
                workspaceId: header.workspaceId,
                issuerDeviceId: header.issuerDeviceId,
                generation: header.generation,
                nonce: header.nonce,
                ciphertext: ciphertext.base64EncodedString()
            )
        )
    }

    static func decode(_ data: Data) throws -> WorkspaceSyncKeyRotation {
        let message: WorkspaceSyncKeyRotation
        do {
            message = try JSONDecoder().decode(WorkspaceSyncKeyRotation.self, from: data)
        } catch {
            throw WorkspaceSyncKeyRotationError.invalidMessage("message is not valid JSON.")
        }
        guard message.version == WorkspaceSyncKeyRotation.version else {
            throw WorkspaceSyncKeyRotationError.unsupportedVersion
        }
        guard message.kind == WorkspaceSyncKeyRotation.kind else {
            throw WorkspaceSyncKeyRotationError.invalidKind
        }
        guard !message.workspaceId.isEmpty, !message.issuerDeviceId.isEmpty else {
            throw WorkspaceSyncKeyRotationError.invalidMessage(
                "workspace and issuer device are required."
            )
        }
        return message
    }

    static func accept(
        _ message: WorkspaceSyncKeyRotation,
        currentKey: SymmetricKey,
        workspaceId: String,
        currentGeneration: UInt64,
        expectedIssuerDeviceId: String? = nil
    ) throws -> (key: SymmetricKey, generation: UInt64) {
        guard message.version == WorkspaceSyncKeyRotation.version else {
            throw WorkspaceSyncKeyRotationError.unsupportedVersion
        }
        guard message.kind == WorkspaceSyncKeyRotation.kind else {
            throw WorkspaceSyncKeyRotationError.invalidKind
        }
        guard message.workspaceId == workspaceId else {
            throw WorkspaceSyncKeyRotationError.workspaceMismatch
        }
        if let expectedIssuerDeviceId, message.issuerDeviceId != expectedIssuerDeviceId {
            throw WorkspaceSyncKeyRotationError.invalidIssuer
        }
        guard message.generation > currentGeneration else {
            throw WorkspaceSyncKeyRotationError.generationReplay
        }
        guard currentGeneration < UInt64.max,
              message.generation == currentGeneration + 1 else {
            throw WorkspaceSyncKeyRotationError.generationGap
        }
        guard let nonce = Data(base64Encoded: message.nonce), nonce.count == nonceBytes else {
            throw WorkspaceSyncKeyRotationError.invalidMessage("nonce is not valid base64.")
        }
        guard let ciphertext = Data(base64Encoded: message.ciphertext),
              ciphertext.count >= tagBytes + keyBytes else {
            throw WorkspaceSyncKeyRotationError.invalidMessage(
                "ciphertext does not contain a rotated key."
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
                using: currentKey,
                authenticating: try canonicalAad(for: message)
            )
        } catch {
            throw WorkspaceSyncKeyRotationError.authenticationFailed
        }
        guard rawKey.count == keyBytes else {
            throw WorkspaceSyncKeyRotationError.invalidKey
        }
        return (SymmetricKey(data: rawKey), message.generation)
    }

    static func canonicalAad(for message: WorkspaceSyncKeyRotation) throws -> Data {
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
            throw WorkspaceSyncKeyRotationError.invalidMessage(
                "could not encode authenticated metadata."
            )
        }
    }
}
