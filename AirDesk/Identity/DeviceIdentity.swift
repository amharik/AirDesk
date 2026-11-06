import CryptoKit
import Foundation

enum DeviceIdentityAlgorithm: String, Codable, CaseIterable {
    case ed25519
    case p256

    var displayName: String {
        switch self {
        case .ed25519: return "Ed25519"
        case .p256: return "P-256"
        }
    }
}

enum DeviceIdentityError: LocalizedError, Equatable {
    case unsupportedAlgorithm(String)
    case invalidPrivateKey
    case invalidPublicKey
    case invalidSPKI
    case invalidSignature
    case unsupportedStoredVersion(Int)
    case corruptedStoredIdentity

    var errorDescription: String? {
        switch self {
        case .unsupportedAlgorithm(let algorithm):
            return "Unsupported device identity algorithm: \(algorithm)."
        case .invalidPrivateKey:
            return "The device private key is invalid."
        case .invalidPublicKey:
            return "The device public key is invalid."
        case .invalidSPKI:
            return "The device public key is not a canonical DER SubjectPublicKeyInfo."
        case .invalidSignature:
            return "The device signature is invalid."
        case .unsupportedStoredVersion(let version):
            return "The stored device identity version is unsupported (\(version))."
        case .corruptedStoredIdentity:
            return "The stored device identity is corrupted. It will not be rotated automatically."
        }
    }
}

struct DevicePublicKey: Equatable {
    static let ed25519SPKIPrefix = Data([
        0x30, 0x2a,
        0x30, 0x05,
        0x06, 0x03, 0x2b, 0x65, 0x70,
        0x03, 0x21, 0x00
    ])

    static let p256SPKIPrefix = Data([
        0x30, 0x59,
        0x30, 0x13,
        0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
        0x03, 0x42, 0x00
    ])

    let algorithm: DeviceIdentityAlgorithm
    let rawRepresentation: Data

    init(algorithm: DeviceIdentityAlgorithm, rawRepresentation: Data) throws {
        switch algorithm {
        case .ed25519:
            guard rawRepresentation.count == 32 else {
                throw DeviceIdentityError.invalidPublicKey
            }
            _ = try Curve25519.Signing.PublicKey(rawRepresentation: rawRepresentation)
        case .p256:
            guard rawRepresentation.count == 65,
                  rawRepresentation.first == 0x04 else {
                throw DeviceIdentityError.invalidPublicKey
            }
            _ = try P256.Signing.PublicKey(x963Representation: rawRepresentation)
        }
        self.algorithm = algorithm
        self.rawRepresentation = rawRepresentation
    }

    init(spki: Data) throws {
        if spki.count == Self.ed25519SPKIPrefix.count + 32,
           spki.prefix(Self.ed25519SPKIPrefix.count) == Self.ed25519SPKIPrefix {
            try self.init(
                algorithm: .ed25519,
                rawRepresentation: Data(spki.suffix(32))
            )
            return
        }

        if spki.count == Self.p256SPKIPrefix.count + 65,
           spki.prefix(Self.p256SPKIPrefix.count) == Self.p256SPKIPrefix {
            try self.init(
                algorithm: .p256,
                rawRepresentation: Data(spki.suffix(65))
            )
            return
        }

        throw DeviceIdentityError.invalidSPKI
    }

    var spki: Data {
        switch algorithm {
        case .ed25519:
            return Self.ed25519SPKIPrefix + rawRepresentation
        case .p256:
            return Self.p256SPKIPrefix + rawRepresentation
        }
    }

    var spkiHex: String {
        spki.map { String(format: "%02x", $0) }.joined()
    }

    var deviceId: String {
        DeviceIdentity.deviceId(forSPKI: spki)
    }

    func verify(signature: Data, for data: Data) -> Bool {
        switch algorithm {
        case .ed25519:
            guard let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: rawRepresentation
            ) else {
                return false
            }
            return publicKey.isValidSignature(signature, for: data)
        case .p256:
            guard let publicKey = try? P256.Signing.PublicKey(
                x963Representation: rawRepresentation
            ),
            let signature = try? P256.Signing.ECDSASignature(
                rawRepresentation: signature
            ) else {
                return false
            }
            return publicKey.isValidSignature(signature, for: data)
        }
    }
}

struct DeviceIdentity {
    static let deviceIdPrefix = "ad-device:"

    private enum PrivateKey {
        case ed25519(Curve25519.Signing.PrivateKey)
        case p256(P256.Signing.PrivateKey)
    }

    let algorithm: DeviceIdentityAlgorithm
    let publicKey: DevicePublicKey
    private let privateKey: PrivateKey

    init(algorithm: DeviceIdentityAlgorithm = .ed25519) throws {
        switch algorithm {
        case .ed25519:
            let key = Curve25519.Signing.PrivateKey()
            self.privateKey = .ed25519(key)
            self.publicKey = try DevicePublicKey(
                algorithm: .ed25519,
                rawRepresentation: key.publicKey.rawRepresentation
            )
        case .p256:
            let key = P256.Signing.PrivateKey()
            self.privateKey = .p256(key)
            self.publicKey = try DevicePublicKey(
                algorithm: .p256,
                rawRepresentation: key.publicKey.x963Representation
            )
        }
        self.algorithm = algorithm
    }

    init(algorithm: DeviceIdentityAlgorithm, privateKeyRaw: Data) throws {
        switch algorithm {
        case .ed25519:
            guard privateKeyRaw.count == 32 else {
                throw DeviceIdentityError.invalidPrivateKey
            }
            let key: Curve25519.Signing.PrivateKey
            do {
                key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
            } catch {
                throw DeviceIdentityError.invalidPrivateKey
            }
            self.privateKey = .ed25519(key)
            self.publicKey = try DevicePublicKey(
                algorithm: .ed25519,
                rawRepresentation: key.publicKey.rawRepresentation
            )
        case .p256:
            guard privateKeyRaw.count == 32 else {
                throw DeviceIdentityError.invalidPrivateKey
            }
            let key: P256.Signing.PrivateKey
            do {
                key = try P256.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
            } catch {
                throw DeviceIdentityError.invalidPrivateKey
            }
            self.privateKey = .p256(key)
            self.publicKey = try DevicePublicKey(
                algorithm: .p256,
                rawRepresentation: key.publicKey.x963Representation
            )
        }
        self.algorithm = algorithm
    }

    var privateKeyRawRepresentation: Data {
        switch privateKey {
        case .ed25519(let key): return key.rawRepresentation
        case .p256(let key): return key.rawRepresentation
        }
    }

    var spki: Data { publicKey.spki }
    var spkiHex: String { publicKey.spkiHex }
    var deviceId: String { publicKey.deviceId }

    func sign(_ data: Data) throws -> Data {
        switch privateKey {
        case .ed25519(let key):
            do {
                return try key.signature(for: data)
            } catch {
                throw DeviceIdentityError.invalidSignature
            }
        case .p256(let key):
            do {
                return try key.signature(for: data).rawRepresentation
            } catch {
                throw DeviceIdentityError.invalidSignature
            }
        }
    }

    static func deviceId(forSPKI spki: Data) -> String {
        let digest = SHA256.hash(data: spki)
        return deviceIdPrefix + digest.map { String(format: "%02x", $0) }.joined()
    }
}
