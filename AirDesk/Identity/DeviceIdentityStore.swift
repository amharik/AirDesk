import Foundation

protocol DeviceIdentitySecretStore {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func delete()
}

struct KeychainDeviceIdentitySecretStore: DeviceIdentitySecretStore {
    let service: String
    let account: String

    init(
        service: String = "com.airdesk.ios.identity",
        account: String = "device-identity-v1"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> Data? {
        try SecureStorage.load(service: service, account: account)
    }

    func save(_ data: Data) throws {
        try SecureStorage.save(data, service: service, account: account)
    }

    func delete() {
        SecureStorage.delete(service: service, account: account)
    }
}

final class DeviceIdentityStore {
    private struct StoredIdentity: Codable {
        static let currentVersion = 1

        let version: Int
        let algorithm: DeviceIdentityAlgorithm
        let privateKey: Data
    }

    private let secretStore: DeviceIdentitySecretStore
    private let preferredAlgorithm: DeviceIdentityAlgorithm
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        secretStore: DeviceIdentitySecretStore = KeychainDeviceIdentitySecretStore(),
        preferredAlgorithm: DeviceIdentityAlgorithm = .ed25519
    ) {
        self.secretStore = secretStore
        self.preferredAlgorithm = preferredAlgorithm
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func loadOrCreate() throws -> DeviceIdentity {
        if let data = try secretStore.load() {
            return try decodeIdentity(from: data)
        }
        return try createAndPersistIdentity()
    }

    func rotateIdentity() throws -> DeviceIdentity {
        secretStore.delete()
        return try createAndPersistIdentity()
    }

    private func decodeIdentity(from data: Data) throws -> DeviceIdentity {
        let stored: StoredIdentity
        do {
            stored = try decoder.decode(StoredIdentity.self, from: data)
        } catch {
            throw DeviceIdentityError.corruptedStoredIdentity
        }
        guard stored.version == StoredIdentity.currentVersion else {
            throw DeviceIdentityError.unsupportedStoredVersion(stored.version)
        }
        return try DeviceIdentity(
            algorithm: stored.algorithm,
            privateKeyRaw: stored.privateKey
        )
    }

    private func createAndPersistIdentity() throws -> DeviceIdentity {
        let identity = try DeviceIdentity(algorithm: preferredAlgorithm)
        let stored = StoredIdentity(
            version: StoredIdentity.currentVersion,
            algorithm: identity.algorithm,
            privateKey: identity.privateKeyRawRepresentation
        )
        let data: Data
        do {
            data = try encoder.encode(stored)
        } catch {
            throw DeviceIdentityError.corruptedStoredIdentity
        }
        try secretStore.save(data)
        return identity
    }
}
