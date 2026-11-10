import Foundation

enum DeviceAgentLifecycleState: String, CaseIterable, Equatable {
    case starting
    case ready
    case degraded
    case unavailable
}

enum DeviceAgentEventType: String, CaseIterable, Equatable {
    case lifecycle
    case health
    case capability
    case lease
}

enum DeviceAgentPlatformPermissionState: String, Equatable {
    case granted
    case denied
    case notDetermined = "not-determined"
    case restricted
}

enum DeviceAgentError: Error, Equatable, LocalizedError {
    case invalidIdentity
    case invalidCapability
    case capabilityUnknown(String)
    case authorizationDenied
    case authorizationRevoked
    case capabilityBusy
    case capabilityRestricted
    case capabilityUnavailable
    case operationNotAllowed(String)
    case platformPermissionDenied(String)
    case agentUnavailable
    case leaseNotFound(String)
    case invalidEventType(String)
    case invalidRequest(String)

    var code: String {
        switch self {
        case .invalidIdentity: return "invalid-identity"
        case .invalidCapability: return "invalid-capability"
        case .capabilityUnknown: return "capability-unknown"
        case .authorizationDenied: return "authorization-denied"
        case .authorizationRevoked: return "authorization-revoked"
        case .capabilityBusy: return "capability-busy"
        case .capabilityRestricted: return "capability-restricted"
        case .capabilityUnavailable: return "capability-unavailable"
        case .operationNotAllowed: return "operation-not-allowed"
        case .platformPermissionDenied: return "platform-permission-denied"
        case .agentUnavailable: return "agent-unavailable"
        case .leaseNotFound: return "lease-not-found"
        case .invalidEventType: return "invalid-event-type"
        case .invalidRequest: return "invalid-request"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidIdentity:
            return "The device agent identity is invalid."
        case .invalidCapability:
            return "A device agent capability is invalid."
        case .capabilityUnknown(let capUri):
            return "The capability \(capUri) is not advertised by this agent."
        case .authorizationDenied:
            return "The capability is not authorized."
        case .authorizationRevoked:
            return "The capability authorization was revoked."
        case .capabilityBusy:
            return "The capability is temporarily busy."
        case .capabilityRestricted:
            return "The capability is restricted by policy."
        case .capabilityUnavailable:
            return "The capability is unavailable."
        case .operationNotAllowed(let operation):
            return "The capability does not allow operation \(operation)."
        case .platformPermissionDenied(let permission):
            return "The platform permission \(permission) is not granted."
        case .agentUnavailable:
            return "The device agent is unavailable."
        case .leaseNotFound(let leaseId):
            return "The capability lease \(leaseId) is not active."
        case .invalidEventType(let eventType):
            return "The subscription event type \(eventType) is invalid."
        case .invalidRequest(let reason):
            return "The capability request is invalid: \(reason)."
        }
    }
}

struct DeviceAgentIdentity: Equatable {
    let deviceId: String
    let displayName: String
    let platform: String
    let algorithm: String
    let publicKeySpkiBase64Url: String
    let createdAtEpochMillis: Int64
}

struct DeviceAgentCapability: Equatable {
    let capUri: String
    let version: UInt32
    let providerDeviceId: String
    let operations: [String]
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
}

struct DeviceAgentCapabilityRequest: Equatable {
    let capUri: String
    let operations: [String]
    let workspaceId: String
    let applicationId: String
    let requesterDeviceId: String
    let sessionId: String
    let leaseId: String?
    let auditId: String?

    init(
        capUri: String,
        operations: [String],
        workspaceId: String,
        applicationId: String,
        requesterDeviceId: String,
        sessionId: String,
        leaseId: String? = nil,
        auditId: String? = nil
    ) {
        self.capUri = capUri
        self.operations = operations
        self.workspaceId = workspaceId
        self.applicationId = applicationId
        self.requesterDeviceId = requesterDeviceId
        self.sessionId = sessionId
        self.leaseId = leaseId
        self.auditId = auditId
    }
}

struct DeviceAgentLease: Equatable {
    let leaseId: String
    let auditId: String
    let capUri: String
    let operations: [String]
    let workspaceId: String
    let applicationId: String
    let requesterDeviceId: String
    let sessionId: String
    let issuedAtEpochMillis: Int64
    let expiresAtEpochMillis: Int64
}

struct DeviceAgentHealth: Equatable {
    let state: DeviceAgentLifecycleState
    let generation: UInt64
    let uptimeMillis: Int64
    let capabilityCount: Int
    let availableCapabilityCount: Int
    let busyCapabilityCount: Int
    let restrictedCapabilityCount: Int
    let unavailableCapabilityCount: Int
    let authorizedCapabilityCount: Int
    let activeLeaseCount: Int
}

struct DeviceAgentEvent: Equatable {
    let type: DeviceAgentEventType
    let sequence: UInt64
    let atEpochMillis: Int64
    let action: String
    let leaseId: String?
    let capUri: String?
    let state: DeviceAgentLifecycleState?
    let permission: String?
}

final class DeviceAgentSubscription {
    private let cancellation: () -> Void
    private(set) var isActive = true

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        guard isActive else { return }
        isActive = false
        cancellation()
    }
}

final class DeviceAgent {
    private struct Subscription {
        let type: DeviceAgentEventType
        let handler: (DeviceAgentEvent) -> Void
    }

    private let identityValue: DeviceAgentIdentity
    private var capabilityValues: [DeviceAgentCapability]
    private var permissions: [String: DeviceAgentPlatformPermissionState]
    private let leaseDurationMillis: Int64
    private let now: () -> Int64
    private var lifecycleState: DeviceAgentLifecycleState = .starting
    private var generation: UInt64 = 0
    private var startedAtEpochMillis: Int64?
    private var leases: [String: DeviceAgentLease] = [:]
    private var subscriptions: [UInt64: Subscription] = [:]
    private var nextSubscriptionId: UInt64 = 0
    private var nextSequence: UInt64 = 0
    private var nextLeaseOrdinal: UInt64 = 0

    init(
        identity: DeviceAgentIdentity,
        capabilities: [DeviceAgentCapability],
        permissions: [String: DeviceAgentPlatformPermissionState] = [:],
        leaseDurationMillis: Int64 = 600_000,
        now: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1000)
        }
    ) throws {
        guard isBounded(identity.deviceId, maximum: 512),
              isBounded(identity.displayName, maximum: 128),
              isBounded(identity.platform, maximum: 32),
              isBounded(identity.algorithm, maximum: 32),
              isBounded(identity.publicKeySpkiBase64Url, maximum: 4096),
              identity.createdAtEpochMillis >= 0 else {
            throw DeviceAgentError.invalidIdentity
        }
        guard leaseDurationMillis > 0 else {
            throw DeviceAgentError.invalidRequest("lease duration must be positive")
        }
        guard !capabilities.isEmpty,
              Set(capabilities.map(\.capUri)).count == capabilities.count else {
            throw DeviceAgentError.invalidCapability
        }
        for capability in capabilities {
            guard isBounded(capability.capUri, maximum: 512),
                  capability.version > 0,
                  isBounded(capability.providerDeviceId, maximum: 512),
                  !capability.operations.isEmpty,
                  Set(capability.operations).count == capability.operations.count,
                  capability.operations.allSatisfy({ isBounded($0, maximum: 128) }),
                  Set(capability.permissions).count == capability.permissions.count,
                  isBounded(capability.execution, maximum: 64),
                  isBounded(capability.transport, maximum: 64),
                  isBounded(capability.constraints, maximum: 4096),
                  capability.availability != .unknown,
                  capability.authorization != .unknown,
                  isBounded(capability.label, maximum: 128),
                  isBounded(capability.summary, maximum: 512),
                  isBounded(capability.note, maximum: 2048) else {
                throw DeviceAgentError.invalidCapability
            }
        }
        self.identityValue = identity
        self.capabilityValues = capabilities
        self.permissions = permissions
        self.leaseDurationMillis = leaseDurationMillis
        self.now = now
    }

    func identity() -> DeviceAgentIdentity {
        identityValue
    }

    func capabilities() -> [DeviceAgentCapability] {
        capabilityValues.sorted { $0.capUri < $1.capUri }
    }

    var state: DeviceAgentLifecycleState {
        lifecycleState
    }

    func start() {
        guard lifecycleState != .ready else { return }
        let action = lifecycleState == .unavailable ? "reconnected" : "started"
        lifecycleState = .ready
        generation += 1
        startedAtEpochMillis = now()
        emit(.lifecycle, action: action, state: .ready)
        emit(.health, action: "updated", state: .ready)
    }

    func reconnect() {
        start()
    }

    func disconnect() {
        guard lifecycleState != .unavailable else { return }
        let revoked = leases.values.sorted { $0.leaseId < $1.leaseId }
        leases.removeAll()
        lifecycleState = .unavailable
        generation += 1
        startedAtEpochMillis = nil
        for lease in revoked {
            emit(.lease, action: "revoked", leaseId: lease.leaseId, capUri: lease.capUri)
        }
        emit(.lifecycle, action: "disconnected", state: .unavailable)
        emit(.health, action: "updated", state: .unavailable)
    }

    func markDegraded(reason: String) {
        guard lifecycleState != .unavailable else { return }
        lifecycleState = .degraded
        generation += 1
        emit(.lifecycle, action: reason, state: .degraded)
        emit(.health, action: "updated", state: .degraded)
    }

    func restore() {
        guard lifecycleState == .degraded else { return }
        lifecycleState = .ready
        generation += 1
        emit(.lifecycle, action: "restored", state: .ready)
        emit(.health, action: "updated", state: .ready)
    }

    func health() -> DeviceAgentHealth {
        let uptime: Int64
        if let startedAtEpochMillis {
            uptime = max(0, now() - startedAtEpochMillis)
        } else {
            uptime = 0
        }
        return DeviceAgentHealth(
            state: lifecycleState,
            generation: generation,
            uptimeMillis: uptime,
            capabilityCount: capabilityValues.count,
            availableCapabilityCount: capabilityValues.filter {
                $0.availability == .available
            }.count,
            busyCapabilityCount: capabilityValues.filter {
                $0.availability == .busy
            }.count,
            restrictedCapabilityCount: capabilityValues.filter {
                $0.availability == .restricted
            }.count,
            unavailableCapabilityCount: capabilityValues.filter {
                $0.availability == .unavailable
            }.count,
            authorizedCapabilityCount: capabilityValues.filter {
                $0.authorization == .granted
            }.count,
            activeLeaseCount: leases.count
        )
    }

    func activeLeases() -> [DeviceAgentLease] {
        leases.values.sorted { $0.leaseId < $1.leaseId }
    }

    func requestCapability(_ request: DeviceAgentCapabilityRequest) throws -> DeviceAgentLease {
        guard lifecycleState == .ready || lifecycleState == .degraded else {
            throw DeviceAgentError.agentUnavailable
        }
        guard isBounded(request.capUri, maximum: 512),
              !request.operations.isEmpty,
              request.operations.allSatisfy({ isBounded($0, maximum: 128) }),
              isBounded(request.workspaceId, maximum: 512),
              isBounded(request.applicationId, maximum: 512),
              isBounded(request.requesterDeviceId, maximum: 512),
              isBounded(request.sessionId, maximum: 512) else {
            throw DeviceAgentError.invalidRequest("required request fields are missing")
        }
        guard let capability = capabilityValues.first(where: {
            $0.capUri == request.capUri
        }) else {
            throw DeviceAgentError.capabilityUnknown(request.capUri)
        }
        for operation in request.operations where !capability.operations.contains(operation) {
            throw DeviceAgentError.operationNotAllowed(operation)
        }
        switch capability.authorization {
        case .granted:
            break
        case .ungranted, .denied, .unknown:
            throw DeviceAgentError.authorizationDenied
        case .revoked:
            throw DeviceAgentError.authorizationRevoked
        }
        switch capability.availability {
        case .available:
            break
        case .busy:
            throw DeviceAgentError.capabilityBusy
        case .restricted:
            throw DeviceAgentError.capabilityRestricted
        case .unavailable, .unknown:
            throw DeviceAgentError.capabilityUnavailable
        }
        for permission in capability.permissions {
            guard permissions[permission] == .granted else {
                throw DeviceAgentError.platformPermissionDenied(permission)
            }
        }

        nextLeaseOrdinal += 1
        let leaseId = request.leaseId ?? "lease-\(nextLeaseOrdinal)"
        guard leases[leaseId] == nil else {
            throw DeviceAgentError.invalidRequest("lease id is already active")
        }
        let issuedAt = now()
        let lease = DeviceAgentLease(
            leaseId: leaseId,
            auditId: request.auditId ?? "audit-\(nextLeaseOrdinal)",
            capUri: capability.capUri,
            operations: request.operations,
            workspaceId: request.workspaceId,
            applicationId: request.applicationId,
            requesterDeviceId: request.requesterDeviceId,
            sessionId: request.sessionId,
            issuedAtEpochMillis: issuedAt,
            expiresAtEpochMillis: issuedAt + leaseDurationMillis
        )
        leases[leaseId] = lease
        emit(.lease, action: "granted", leaseId: leaseId, capUri: capability.capUri)
        emit(.health, action: "updated", state: lifecycleState)
        return lease
    }

    func releaseCapability(leaseId: String) throws {
        guard let lease = leases.removeValue(forKey: leaseId) else {
            throw DeviceAgentError.leaseNotFound(leaseId)
        }
        emit(.lease, action: "released", leaseId: leaseId, capUri: lease.capUri)
        emit(.health, action: "updated", state: lifecycleState)
    }

    func subscribe(
        eventType: String,
        handler: @escaping (DeviceAgentEvent) -> Void
    ) throws -> DeviceAgentSubscription {
        guard let type = DeviceAgentEventType(rawValue: eventType) else {
            throw DeviceAgentError.invalidEventType(eventType)
        }
        nextSubscriptionId += 1
        let subscriptionId = nextSubscriptionId
        subscriptions[subscriptionId] = Subscription(type: type, handler: handler)
        return DeviceAgentSubscription { [weak self] in
            self?.subscriptions.removeValue(forKey: subscriptionId)
        }
    }

    private func emit(
        _ type: DeviceAgentEventType,
        action: String,
        leaseId: String? = nil,
        capUri: String? = nil,
        state: DeviceAgentLifecycleState? = nil,
        permission: String? = nil
    ) {
        let matching = subscriptions.values.filter { $0.type == type }
        guard !matching.isEmpty else { return }
        for subscription in matching {
            nextSequence += 1
            subscription.handler(DeviceAgentEvent(
                type: type,
                sequence: nextSequence,
                atEpochMillis: now(),
                action: action,
                leaseId: leaseId,
                capUri: capUri,
                state: state,
                permission: permission
            ))
        }
    }

}

private func isBounded(_ value: String, maximum: Int) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        value.count <= maximum
}
