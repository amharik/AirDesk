import FlatBuffers
import Foundation

typealias CapabilityAvailability = AirDesk_Protocol__Availability
typealias CapabilityAuthorization = AirDesk_Protocol__Authorization

extension AirDesk_Protocol__Availability {
    var displayName: String {
        switch self {
        case .unknown: return "unknown"
        case .available: return "available"
        case .busy: return "busy"
        case .restricted: return "restricted"
        case .unavailable: return "unavailable"
        }
    }
}

extension AirDesk_Protocol__Authorization {
    var displayName: String {
        switch self {
        case .unknown: return "unknown"
        case .ungranted: return "ungranted"
        case .granted: return "granted"
        case .denied: return "denied"
        case .revoked: return "revoked"
        }
    }
}

struct CapabilityDescriptor: Equatable, Identifiable {
    static let currentVersion: UInt32 = 1

    let capUri: String
    let version: UInt32
    let providerDeviceId: String
    let permissions: [String]
    let execution: String
    let transport: String
    let constraints: String
    let availability: CapabilityAvailability
    let authorization: CapabilityAuthorization
    let label: String
    let summary: String
    let note: String
    let authorizationRef: String?

    var id: String { capUri }

    init(
        capUri: String,
        version: UInt32 = CapabilityDescriptor.currentVersion,
        providerDeviceId: String,
        permissions: [String] = [],
        execution: String,
        transport: String,
        constraints: String,
        availability: CapabilityAvailability,
        authorization: CapabilityAuthorization,
        label: String,
        summary: String,
        note: String,
        authorizationRef: String? = nil
    ) {
        self.capUri = capUri
        self.version = version
        self.providerDeviceId = providerDeviceId
        self.permissions = permissions
        self.execution = execution
        self.transport = transport
        self.constraints = constraints
        self.availability = availability
        self.authorization = authorization
        self.label = label
        self.summary = summary
        self.note = note
        self.authorizationRef = authorizationRef
    }

    func adfpEncoded() -> Data {
        var builder = FlatBufferBuilder(initialSize: 512)
        let capUriOffset = builder.create(string: capUri)
        let providerOffset = builder.create(string: providerDeviceId)
        let permissionOffsets = permissions.map { builder.create(string: $0) }
        let permissionsVector = permissions.isEmpty
            ? Offset()
            : builder.createVector(ofOffsets: permissionOffsets)
        let executionOffset = builder.create(string: execution)
        let transportOffset = builder.create(string: transport)
        let constraintsOffset = builder.create(string: constraints)
        let descriptor = AirDesk_Protocol__CapabilityDescriptor.createCapabilityDescriptor(
            &builder,
            capUriOffset: capUriOffset,
            version: version,
            providerDeviceIdOffset: providerOffset,
            availability: availability,
            authorization: authorization,
            permissionsVectorOffset: permissionsVector,
            executionOffset: executionOffset,
            transportOffset: transportOffset,
            constraintsOffset: constraintsOffset
        )
        AirDesk_Protocol__CapabilityDescriptor.finish(&builder, end: descriptor)
        return Data(builder.data)
    }
}
