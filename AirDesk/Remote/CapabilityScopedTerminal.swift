import Foundation

enum CapabilityTerminalOperation: String, CaseIterable, Sendable {
    case connect
    case write
    case resize
}

struct CapabilityLease: Equatable, Sendable {
    var leaseId: String
    var capUri: String
    var workspaceId: String
    var applicationId: String
    var requesterDeviceId: String
    var sessionId: String
    var issuedAt: Date = Date()
    var expiresAt: Date? = nil
    var revoked: Bool = false
    var revocationReason: String? = nil
    var operations: Set<CapabilityTerminalOperation> = Set(CapabilityTerminalOperation.allCases)
    var auditId: String = UUID().uuidString
}

struct CapabilityTerminalContext: Equatable, Sendable {
    var capUri: String = CapabilityScopedTerminal.capabilityURI
    var workspaceId: String
    var applicationId: String
    var requesterDeviceId: String
    var sessionId: String
    var leaseId: String?
}

struct CapabilityLeaseRequest: Equatable, Sendable {
    var leaseId: String?
    var capUri: String
    var workspaceId: String
    var applicationId: String
    var requesterDeviceId: String
    var sessionId: String
    var operation: CapabilityTerminalOperation

    init(
        context: CapabilityTerminalContext,
        operation: CapabilityTerminalOperation
    ) {
        self.leaseId = context.leaseId
        self.capUri = context.capUri
        self.workspaceId = context.workspaceId
        self.applicationId = context.applicationId
        self.requesterDeviceId = context.requesterDeviceId
        self.sessionId = context.sessionId
        self.operation = operation
    }
}

enum CapabilityTerminalError: Error, Equatable, LocalizedError {
    case invalidLease(String)
    case leaseDenied
    case leaseRevoked
    case leaseExpired
    case leaseBusy(String)
    case notRunning
    case sessionRequired

    var errorDescription: String? {
        switch self {
        case .invalidLease(let reason):
            return "InvalidLease: \(reason)"
        case .leaseDenied:
            return "LeaseDenied: no matching capability lease authorizes this operation."
        case .leaseRevoked:
            return "LeaseRevoked: the capability lease was revoked."
        case .leaseExpired:
            return "LeaseExpired: the capability lease has expired."
        case .leaseBusy:
            return "LeaseBusy: the capability lease is already in use by another terminal."
        case .notRunning:
            return "TerminalNotRunning: the capability-scoped terminal is not running."
        case .sessionRequired:
            return "SessionRequired: connect to a desktop session before authorizing the remote terminal."
        }
    }
}

struct CapabilityLeaseAuditEvent: Equatable, Sendable {
    enum Decision: String, Sendable {
        case allowed
        case denied
        case revoked
        case expired
        case busy
    }

    let timestamp: Date
    let leaseId: String?
    let auditId: String?
    let capUri: String
    let workspaceId: String
    let sessionId: String
    let operation: CapabilityTerminalOperation
    let decision: Decision
    let reason: String?
}

final class CapabilityLeaseRegistry {
    private var leases: [String: CapabilityLease] = [:]
    private var activeOwners: [String: String] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    func grant(_ lease: CapabilityLease) throws -> CapabilityLease {
        try validate(lease)
        leases[lease.leaseId] = lease
        return lease
    }

    @discardableResult
    func revoke(leaseId: String, reason: String = "Revoked") -> Bool {
        guard var lease = leases[leaseId] else { return false }
        lease.revoked = true
        lease.revocationReason = reason
        leases[leaseId] = lease
        activeOwners.removeValue(forKey: leaseId)
        return true
    }

    @discardableResult
    func remove(leaseId: String) -> Bool {
        activeOwners.removeValue(forKey: leaseId)
        return leases.removeValue(forKey: leaseId) != nil
    }

    func lease(id: String) -> CapabilityLease? {
        leases[id]
    }

    func authorize(_ request: CapabilityLeaseRequest, owner: String) throws -> CapabilityLease {
        guard let leaseId = request.leaseId, !leaseId.isEmpty,
              let lease = leases[leaseId] else {
            throw CapabilityTerminalError.leaseDenied
        }
        guard !lease.revoked else {
            throw CapabilityTerminalError.leaseRevoked
        }
        if let expiresAt = lease.expiresAt, expiresAt <= now() {
            throw CapabilityTerminalError.leaseExpired
        }
        guard lease.capUri == request.capUri,
              lease.workspaceId == request.workspaceId,
              lease.applicationId == request.applicationId,
              lease.requesterDeviceId == request.requesterDeviceId,
              lease.sessionId.isEmpty || lease.sessionId == request.sessionId,
              lease.operations.contains(request.operation) else {
            throw CapabilityTerminalError.leaseDenied
        }
        if let activeOwner = activeOwners[leaseId], activeOwner != owner {
            throw CapabilityTerminalError.leaseBusy(leaseId)
        }
        if request.operation == .connect {
            activeOwners[leaseId] = owner
        } else {
            guard activeOwners[leaseId] == owner else {
                throw CapabilityTerminalError.leaseDenied
            }
        }
        return lease
    }

    func release(leaseId: String, owner: String) {
        guard activeOwners[leaseId] == owner else { return }
        activeOwners.removeValue(forKey: leaseId)
    }

    func isActive(leaseId: String, owner: String) -> Bool {
        activeOwners[leaseId] == owner
    }

    private func validate(_ lease: CapabilityLease) throws {
        guard isValid(lease.leaseId, maximumBytes: 128) else {
            throw CapabilityTerminalError.invalidLease("lease id")
        }
        guard isValid(lease.capUri, maximumBytes: 256), lease.capUri.hasPrefix("airdesk://") else {
            throw CapabilityTerminalError.invalidLease("capability URI")
        }
        guard isValid(lease.workspaceId, maximumBytes: 128) else {
            throw CapabilityTerminalError.invalidLease("workspace id")
        }
        guard isValid(lease.applicationId, maximumBytes: 128) else {
            throw CapabilityTerminalError.invalidLease("application id")
        }
        guard isValid(lease.requesterDeviceId, maximumBytes: 128) else {
            throw CapabilityTerminalError.invalidLease("requester device id")
        }
        guard lease.sessionId.utf8.count <= 128 else {
            throw CapabilityTerminalError.invalidLease("session id")
        }
        guard isValid(lease.auditId, maximumBytes: 128) else {
            throw CapabilityTerminalError.invalidLease("audit id")
        }
        guard !lease.operations.isEmpty else {
            throw CapabilityTerminalError.invalidLease("operations")
        }
        if let revocationReason = lease.revocationReason,
           revocationReason.utf8.count > 256 {
            throw CapabilityTerminalError.invalidLease("revocation reason")
        }
    }

    private func isValid(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty
            && value.utf8.count <= maximumBytes
            && !value.contains("\0")
    }
}

@MainActor
protocol RemoteTerminalDriving: AnyObject {
    var isRunning: Bool { get }
    var onEvent: ((RemoteTerminalEvent) -> Void)? { get set }

    func start(configuration: SSHPTYConfiguration) async throws
    func write(_ data: Data)
    func resize(columns: Int, rows: Int)
    func stop()
}

extension RemoteTerminalController: RemoteTerminalDriving {}

@MainActor
final class CapabilityScopedTerminal {
    static let capabilityURI = "airdesk://pty/spawn"
    static let maximumAuditEvents = 256

    private let controller: any RemoteTerminalDriving
    private let leases: CapabilityLeaseRegistry
    private let now: () -> Date
    private let owner = UUID().uuidString
    private var activeLeaseId: String?
    private var context: CapabilityTerminalContext?

    private(set) var auditEvents: [CapabilityLeaseAuditEvent] = []
    var onAudit: ((CapabilityLeaseAuditEvent) -> Void)?
    var onEvent: ((RemoteTerminalEvent) -> Void)?

    var isRunning: Bool {
        activeLeaseId != nil && controller.isRunning
    }

    init(
        controller: (any RemoteTerminalDriving)? = nil,
        leases: CapabilityLeaseRegistry,
        now: @escaping () -> Date = Date.init
    ) {
        let controller = controller ?? RemoteTerminalController()
        self.controller = controller
        self.leases = leases
        self.now = now
        controller.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    func start(
        configuration: SSHPTYConfiguration,
        context: CapabilityTerminalContext
    ) async throws {
        stop()

        var context = context
        if context.capUri.isEmpty {
            context.capUri = Self.capabilityURI
        }
        let request = CapabilityLeaseRequest(context: context, operation: .connect)
        let lease = try authorize(request, auditSuccess: true)
        activeLeaseId = lease.leaseId
        self.context = context

        do {
            try await controller.start(configuration: configuration)
        } catch {
            releaseActiveLease()
            self.context = nil
            throw error
        }
    }

    func write(_ data: Data) {
        guard !data.isEmpty, isRunning, let context, let leaseId = activeLeaseId else { return }
        var requestContext = context
        requestContext.leaseId = leaseId
        let request = CapabilityLeaseRequest(context: requestContext, operation: .write)
        do {
            _ = try authorize(request, auditSuccess: false)
            controller.write(data)
        } catch {
            fail(error)
        }
    }

    func resize(columns: Int, rows: Int) {
        guard isRunning, let context, let leaseId = activeLeaseId else { return }
        var requestContext = context
        requestContext.leaseId = leaseId
        let request = CapabilityLeaseRequest(context: requestContext, operation: .resize)
        do {
            _ = try authorize(request, auditSuccess: false)
            controller.resize(columns: columns, rows: rows)
        } catch {
            fail(error)
        }
    }

    func stop() {
        if controller.isRunning || activeLeaseId != nil {
            controller.stop()
        }
        releaseActiveLease()
        context = nil
    }

    private func authorize(
        _ request: CapabilityLeaseRequest,
        auditSuccess: Bool
    ) throws -> CapabilityLease {
        do {
            let lease = try leases.authorize(request, owner: owner)
            if auditSuccess {
                record(request, lease: lease, decision: .allowed, reason: nil)
            }
            return lease
        } catch {
            let typed = error as? CapabilityTerminalError ?? .leaseDenied
            let lease = request.leaseId.flatMap(leases.lease(id:))
            record(
                request,
                lease: lease,
                decision: decision(for: typed),
                reason: typed.localizedDescription
            )
            throw error
        }
    }

    private func fail(_ error: Error) {
        controller.stop()
        releaseActiveLease()
        context = nil
        onEvent?(.exit(error.localizedDescription))
    }

    private func handle(_ event: RemoteTerminalEvent) {
        if case .exit = event {
            releaseActiveLease()
            context = nil
        }
        onEvent?(event)
    }

    private func releaseActiveLease() {
        if let activeLeaseId {
            leases.release(leaseId: activeLeaseId, owner: owner)
        }
        activeLeaseId = nil
    }

    private func record(
        _ request: CapabilityLeaseRequest,
        lease: CapabilityLease?,
        decision: CapabilityLeaseAuditEvent.Decision,
        reason: String?
    ) {
        let event = CapabilityLeaseAuditEvent(
            timestamp: now(),
            leaseId: request.leaseId,
            auditId: lease?.auditId,
            capUri: request.capUri,
            workspaceId: request.workspaceId,
            sessionId: request.sessionId,
            operation: request.operation,
            decision: decision,
            reason: reason
        )
        auditEvents.append(event)
        if auditEvents.count > Self.maximumAuditEvents {
            auditEvents.removeFirst(auditEvents.count - Self.maximumAuditEvents)
        }
        onAudit?(event)
    }

    private func decision(
        for error: CapabilityTerminalError
    ) -> CapabilityLeaseAuditEvent.Decision {
        switch error {
        case .leaseRevoked:
            return .revoked
        case .leaseExpired:
            return .expired
        case .leaseBusy:
            return .busy
        default:
            return .denied
        }
    }
}
