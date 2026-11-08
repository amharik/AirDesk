import Foundation

enum DeviceTrustState: String, Codable {
    case pending
    case trusted
    case revoked
}

struct PairedPeerRecord: Codable, Equatable {
    var deviceId: String
    var displayLabel: String
    var publicKeySPKI: Data
    var trustState: DeviceTrustState
    var pairedAt: Date
    var revokedAt: Date?
    var revocationReason: String?

    init(
        deviceId: String,
        displayLabel: String,
        publicKeySPKI: Data,
        trustState: DeviceTrustState = .trusted,
        pairedAt: Date,
        revokedAt: Date? = nil,
        revocationReason: String? = nil
    ) {
        self.deviceId = deviceId
        self.displayLabel = displayLabel
        self.publicKeySPKI = publicKeySPKI
        self.trustState = trustState
        self.pairedAt = pairedAt
        self.revokedAt = revokedAt
        self.revocationReason = revocationReason
    }
}

struct DeviceSessionCredential: Equatable {
    let deviceId: String
    let issuedAt: Date
    let expiresAt: Date
}

enum DeviceRegistryError: LocalizedError, Equatable {
    case peerNotFound(String)
    case invalidRecord(String)

    var errorDescription: String? {
        switch self {
        case .peerNotFound(let deviceId):
            return "No paired peer record exists for \(deviceId)."
        case .invalidRecord(let reason):
            return "The paired peer record is invalid: \(reason)"
        }
    }
}

protocol DeviceRegistryStorage {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct FileDeviceRegistryStorage: DeviceRegistryStorage {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    static func applicationSupport(fileManager: FileManager = .default) throws -> FileDeviceRegistryStorage {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("AirDesk/Identity", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileDeviceRegistryStorage(
            url: directory.appendingPathComponent("paired-peers.json")
        )
    }

    func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func save(_ data: Data) throws {
        try data.write(to: url, options: .atomic)
    }
}

final class DeviceRegistry {
    private let storage: DeviceRegistryStorage
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var records: [String: PairedPeerRecord] = [:]

    init(storage: DeviceRegistryStorage) throws {
        self.storage = storage
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        try reload()
    }

    static func applicationSupport(fileManager: FileManager = .default) throws -> DeviceRegistry {
        try DeviceRegistry(
            storage: FileDeviceRegistryStorage.applicationSupport(fileManager: fileManager)
        )
    }

    func reload() throws {
        lock.lock()
        defer { lock.unlock() }
        try reloadUnlocked()
    }

    var peers: [PairedPeerRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.sorted {
            if $0.pairedAt == $1.pairedAt {
                return $0.deviceId < $1.deviceId
            }
            return $0.pairedAt < $1.pairedAt
        }
    }

    var pairedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.count
    }

    var trustedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.values.filter { $0.trustState == .trusted }.count
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.values.filter { $0.trustState == .pending }.count
    }

    var revokedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.values.filter { $0.trustState == .revoked }.count
    }

    func peer(deviceId: String) -> PairedPeerRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[deviceId]
    }

    func upsert(_ record: PairedPeerRecord) throws {
        try Self.validate(record)
        lock.lock()
        defer { lock.unlock() }
        if let existing = records[record.deviceId],
           existing.trustState == .revoked,
           record.trustState != .revoked {
            throw DeviceRegistryError.invalidRecord(
                "A revoked peer requires explicit re-pairing before trust is restored."
            )
        }
        var stored = record
        if let existing = records[record.deviceId],
           existing.trustState == .trusted,
           record.trustState == .pending {
            stored.trustState = .trusted
            stored.pairedAt = existing.pairedAt
        }
        records[record.deviceId] = stored
        try persistUnlocked()
    }

    @discardableResult
    func trust(deviceId: String, at date: Date = Date()) throws -> PairedPeerRecord {
        lock.lock()
        defer { lock.unlock() }
        guard var record = records[deviceId] else {
            throw DeviceRegistryError.peerNotFound(deviceId)
        }
        guard record.trustState != .revoked else {
            throw DeviceRegistryError.invalidRecord(
                "A revoked peer requires explicit re-pairing before trust is restored."
            )
        }
        record.trustState = .trusted
        record.pairedAt = date
        record.revokedAt = nil
        record.revocationReason = nil
        records[deviceId] = record
        try persistUnlocked()
        return record
    }

    @discardableResult
    func revoke(
        deviceId: String,
        at date: Date = Date(),
        reason: String? = nil
    ) throws -> PairedPeerRecord {
        lock.lock()
        defer { lock.unlock() }
        guard var record = records[deviceId] else {
            throw DeviceRegistryError.peerNotFound(deviceId)
        }
        record.trustState = .revoked
        record.revokedAt = date
        record.revocationReason = reason
        records[deviceId] = record
        try persistUnlocked()
        return record
    }

    func isTrusted(deviceId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return records[deviceId]?.trustState == .trusted
    }

    func isRevoked(deviceId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return records[deviceId]?.trustState == .revoked
    }

    func canEstablishSession(deviceId: String) -> Bool {
        isTrusted(deviceId: deviceId)
    }

    func validate(_ credential: DeviceSessionCredential, now: Date = Date()) -> Bool {
        guard isTrusted(deviceId: credential.deviceId) else { return false }
        return now >= credential.issuedAt && now < credential.expiresAt
    }

    private func reloadUnlocked() throws {
        guard let data = try storage.load() else {
            records = [:]
            return
        }
        do {
            let decoded = try decoder.decode([String: PairedPeerRecord].self, from: data)
            for record in decoded.values {
                try Self.validate(record)
            }
            records = decoded
        } catch let error as DeviceRegistryError {
            throw error
        } catch {
            throw DeviceRegistryError.invalidRecord("Stored registry data is corrupted.")
        }
    }

    private func persistUnlocked() throws {
        let data = try encoder.encode(records)
        try storage.save(data)
    }

    private static func validate(_ record: PairedPeerRecord) throws {
        let publicKey: DevicePublicKey
        do {
            publicKey = try DevicePublicKey(spki: record.publicKeySPKI)
        } catch {
            throw DeviceRegistryError.invalidRecord("The public key SPKI is invalid.")
        }
        guard record.deviceId == publicKey.deviceId else {
            throw DeviceRegistryError.invalidRecord("The device ID does not match the public key.")
        }
        guard !record.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeviceRegistryError.invalidRecord("The display label is empty.")
        }
        if record.trustState == .revoked, record.revokedAt == nil {
            throw DeviceRegistryError.invalidRecord("A revoked peer must have a revocation time.")
        }
    }
}
