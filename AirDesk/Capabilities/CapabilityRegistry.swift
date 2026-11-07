import Foundation

enum CapabilityRegistryError: Error, Equatable, LocalizedError {
    case invalidCapUri
    case invalidProviderDeviceId
    case invalidVersion
    case invalidPermissions
    case invalidExecution
    case invalidTransport
    case invalidConstraints
    case invalidAvailability
    case invalidAuthorization
    case invalidLabel
    case invalidSummary
    case invalidNote

    var errorDescription: String? {
        switch self {
        case .invalidCapUri:
            return "The capability URI is invalid."
        case .invalidProviderDeviceId:
            return "The capability provider device ID is invalid."
        case .invalidVersion:
            return "The capability version is invalid."
        case .invalidPermissions:
            return "The capability permissions are invalid."
        case .invalidExecution:
            return "The capability execution mode is invalid."
        case .invalidTransport:
            return "The capability transport is invalid."
        case .invalidConstraints:
            return "The capability constraints are invalid."
        case .invalidAvailability:
            return "The capability availability is invalid."
        case .invalidAuthorization:
            return "The capability authorization is invalid."
        case .invalidLabel:
            return "The capability label is invalid."
        case .invalidSummary:
            return "The capability summary is invalid."
        case .invalidNote:
            return "The capability note is invalid."
        }
    }
}

final class CapabilityRegistry {
    private struct Key: Hashable {
        var providerDeviceId: String
        var capUri: String
        var version: UInt32
    }

    private var entries: [Key: CapabilityDescriptor] = [:]

    var count: Int {
        entries.count
    }

    @discardableResult
    func register(_ descriptor: CapabilityDescriptor) throws -> Bool {
        let validated = try validate(descriptor)
        let key = Key(
            providerDeviceId: validated.providerDeviceId,
            capUri: validated.capUri,
            version: validated.version
        )
        let added = entries[key] == nil
        entries[key] = validated
        return added
    }

    @discardableResult
    func remove(
        providerDeviceId: String,
        capUri: String,
        version: UInt32? = nil
    ) -> Int {
        let keys = entries.keys.filter {
            $0.providerDeviceId == providerDeviceId &&
                $0.capUri == capUri &&
                (version == nil || $0.version == version)
        }
        for key in keys {
            entries.removeValue(forKey: key)
        }
        return keys.count
    }

    @discardableResult
    func updateAvailability(
        providerDeviceId: String,
        capUri: String,
        version: UInt32,
        availability: CapabilityAvailability
    ) throws -> Bool {
        try update(
            providerDeviceId: providerDeviceId,
            capUri: capUri,
            version: version,
            availability: availability,
            authorization: nil
        )
    }

    @discardableResult
    func updateAuthorization(
        providerDeviceId: String,
        capUri: String,
        version: UInt32,
        authorization: CapabilityAuthorization
    ) throws -> Bool {
        try update(
            providerDeviceId: providerDeviceId,
            capUri: capUri,
            version: version,
            availability: nil,
            authorization: authorization
        )
    }

    func descriptor(
        providerDeviceId: String,
        capUri: String,
        version: UInt32
    ) -> CapabilityDescriptor? {
        entries[Key(
            providerDeviceId: providerDeviceId,
            capUri: capUri,
            version: version
        )]
    }

    @discardableResult
    func applyRevokedReferences(_ references: [String]) -> Int {
        let revoked = Set(references)
        let keys = entries.keys.filter { key in
            guard let descriptor = entries[key],
                  descriptor.authorization != .revoked,
                  let authorizationRef = descriptor.authorizationRef else {
                return false
            }
            return revoked.contains(authorizationRef)
        }
        var updated = 0
        for key in keys {
            guard let existing = entries[key],
                  let validated = try? validate(replacing(existing, authorization: .revoked)) else {
                continue
            }
            entries[key] = validated
            updated += 1
        }
        return updated
    }

    func descriptors() -> [CapabilityDescriptor] {
        entries.values.sorted { left, right in
            if left.capUri != right.capUri {
                return left.capUri < right.capUri
            }
            if left.providerDeviceId != right.providerDeviceId {
                return left.providerDeviceId < right.providerDeviceId
            }
            if left.version != right.version {
                return left.version > right.version
            }
            if left.transport != right.transport {
                return left.transport < right.transport
            }
            return left.execution < right.execution
        }
    }

    func removeAll() {
        entries.removeAll()
    }

    private func update(
        providerDeviceId: String,
        capUri: String,
        version: UInt32,
        availability: CapabilityAvailability?,
        authorization: CapabilityAuthorization?
    ) throws -> Bool {
        let key = Key(
            providerDeviceId: providerDeviceId,
            capUri: capUri,
            version: version
        )
        guard let existing = entries[key] else { return false }
        entries[key] = try validate(replacing(
            existing,
            availability: availability,
            authorization: authorization
        ))
        return true
    }

    private func replacing(
        _ existing: CapabilityDescriptor,
        availability: CapabilityAvailability? = nil,
        authorization: CapabilityAuthorization? = nil
    ) -> CapabilityDescriptor {
        CapabilityDescriptor(
            capUri: existing.capUri,
            version: existing.version,
            providerDeviceId: existing.providerDeviceId,
            permissions: existing.permissions,
            execution: existing.execution,
            transport: existing.transport,
            constraints: existing.constraints,
            availability: availability ?? existing.availability,
            authorization: authorization ?? existing.authorization,
            label: existing.label,
            summary: existing.summary,
            note: existing.note,
            authorizationRef: existing.authorizationRef
        )
    }

    private func validate(_ descriptor: CapabilityDescriptor) throws -> CapabilityDescriptor {
        guard isBounded(descriptor.providerDeviceId, maximum: 512) else {
            throw CapabilityRegistryError.invalidProviderDeviceId
        }
        guard isBounded(descriptor.capUri, maximum: 512),
              descriptor.capUri.range(
                  of: #"^airdesk://[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)*$"#,
                  options: .regularExpression
              ) != nil else {
            throw CapabilityRegistryError.invalidCapUri
        }
        guard descriptor.version > 0 else {
            throw CapabilityRegistryError.invalidVersion
        }
        guard descriptor.permissions.count <= 32,
              descriptor.permissions.allSatisfy({
                  isBounded($0, maximum: 128)
              }),
              Set(descriptor.permissions).count == descriptor.permissions.count else {
            throw CapabilityRegistryError.invalidPermissions
        }
        guard isBounded(descriptor.execution, maximum: 64) else {
            throw CapabilityRegistryError.invalidExecution
        }
        guard isBounded(descriptor.transport, maximum: 64) else {
            throw CapabilityRegistryError.invalidTransport
        }
        guard validateConstraints(descriptor.constraints) else {
            throw CapabilityRegistryError.invalidConstraints
        }
        guard descriptor.availability != .unknown else {
            throw CapabilityRegistryError.invalidAvailability
        }
        guard descriptor.authorization != .unknown else {
            throw CapabilityRegistryError.invalidAuthorization
        }
        guard isBounded(descriptor.label, maximum: 128) else {
            throw CapabilityRegistryError.invalidLabel
        }
        guard isBounded(descriptor.summary, maximum: 512) else {
            throw CapabilityRegistryError.invalidSummary
        }
        guard isBounded(descriptor.note, maximum: 2_048) else {
            throw CapabilityRegistryError.invalidNote
        }
        if let authorizationRef = descriptor.authorizationRef,
           !isBounded(authorizationRef, maximum: 256) {
            throw CapabilityRegistryError.invalidAuthorization
        }
        return descriptor
    }

    private func isBounded(_ value: String, maximum: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximum
    }

    private func validateConstraints(_ constraints: String) -> Bool {
        guard let data = constraints.data(using: .utf8),
              data.count <= 4_096,
              let object = try? JSONSerialization.jsonObject(with: data),
              let map = object as? [String: Any],
              map.count <= 32 else {
            return false
        }
        for (key, value) in map {
            guard key == key.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty,
                  key.count <= 64,
                  !(value is [Any]),
                  !(value is [String: Any]),
                  value is String || value is NSNumber else {
                return false
            }
            if let string = value as? String, string.count > 256 {
                return false
            }
        }
        return true
    }
}
