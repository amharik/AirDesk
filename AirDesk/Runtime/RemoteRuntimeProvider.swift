import Foundation

enum RemoteRuntimeTransportError: Error, Equatable, LocalizedError, Sendable {
    case unavailable
    case unauthorized
    case protocolFailure(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The remote runtime transport is unavailable."
        case .unauthorized:
            return "The remote runtime transport rejected authorization."
        case .protocolFailure(let message):
            return message
        }
    }
}

protocol RemoteRuntimeTransport: AnyObject {
    func create(_ request: RuntimeCreateRequest) async throws -> ApplicationInstanceStatus?
    func start(instanceId: String) async throws -> ApplicationInstanceStatus?
    func suspend(instanceId: String) async throws -> ApplicationInstanceStatus?
    func checkpoint(instanceId: String) async throws -> ApplicationInstanceStatus?
    func resume(instanceId: String) async throws -> ApplicationInstanceStatus?
    func stop(instanceId: String) async throws -> ApplicationInstanceStatus?
    func destroy(instanceId: String) async throws
    func status(instanceId: String) async throws -> ApplicationInstanceStatus?
}

final class RemoteRuntimeProvider: RuntimeProvider {
    private let transport: any RemoteRuntimeTransport
    private let now: () -> Date
    private let lock = NSLock()
    private var currentDescriptor: RuntimeProviderDescriptor
    private var statuses: [String: ApplicationInstanceStatus] = [:]

    init(
        transport: any RemoteRuntimeTransport,
        descriptor: RuntimeProviderDescriptor,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.currentDescriptor = descriptor
        self.now = now
    }

    var descriptor: RuntimeProviderDescriptor {
        lock.withLock { currentDescriptor }
    }

    func reconnect() {
        lock.withLock {
            currentDescriptor.availability = .available
            currentDescriptor.health = .healthy
            for instanceId in Array(statuses.keys) {
                statuses[instanceId]?.lastError = nil
            }
        }
    }

    func create(_ request: RuntimeCreateRequest) async throws {
        let descriptor = self.descriptor
        guard descriptor.supportedWorlds.contains(request.world) else {
            throw RuntimeProviderError.unsupportedWorld(providerId: descriptor.id, world: request.world)
        }
        guard descriptor.threadingProfiles.contains(request.threading) else {
            throw RuntimeProviderError.synchronizationUnavailable(providerId: descriptor.id)
        }
        guard request.application.runtimeTargets.contains(where: {
            $0.provider == descriptor.id && $0.world == request.world.rawValue
        }) else {
            throw RuntimeProviderError.unsupportedWorld(providerId: descriptor.id, world: request.world)
        }
        if lock.withLock({ statuses[request.instanceId] != nil }) {
            throw RuntimeProviderError.instanceAlreadyExists(request.instanceId)
        }
        _ = try await perform(
            instanceId: request.instanceId,
            expectedState: .stopped,
            operation: { try await self.transport.create(request) }
        )
    }

    func start(instanceId: String) async throws {
        _ = try await perform(
            instanceId: instanceId,
            expectedState: .running,
            operation: { try await self.transport.start(instanceId: instanceId) }
        )
    }

    func suspend(instanceId: String) async throws {
        _ = try await perform(
            instanceId: instanceId,
            expectedState: .suspended,
            operation: { try await self.transport.suspend(instanceId: instanceId) }
        )
    }

    func checkpoint(instanceId: String) async throws {
        _ = try await perform(
            instanceId: instanceId,
            expectedState: .suspendedCheckpointed,
            operation: { try await self.transport.checkpoint(instanceId: instanceId) }
        )
    }

    func resume(instanceId: String) async throws {
        _ = try await perform(
            instanceId: instanceId,
            expectedState: .running,
            operation: { try await self.transport.resume(instanceId: instanceId) }
        )
    }

    func stop(instanceId: String) async throws {
        _ = try await perform(
            instanceId: instanceId,
            expectedState: .stopped,
            operation: { try await self.transport.stop(instanceId: instanceId) }
        )
    }

    func destroy(instanceId: String) async throws {
        do {
            try await transport.destroy(instanceId: instanceId)
        } catch {
            throw markFailure(error)
        }
        lock.withLock {
            statuses.removeValue(forKey: instanceId)
        }
    }

    func status(instanceId: String) -> ApplicationInstanceStatus? {
        lock.withLock { statuses[instanceId] }
    }

    @discardableResult
    func refreshStatus(instanceId: String) async throws -> ApplicationInstanceStatus? {
        let refreshed: ApplicationInstanceStatus?
        do {
            refreshed = try await transport.status(instanceId: instanceId)
        } catch {
            throw markFailure(error)
        }
        guard let refreshed else {
            return status(instanceId: instanceId)
        }
        let status = normalize(refreshed, instanceId: instanceId)
        lock.withLock {
            statuses[instanceId] = status
        }
        return status
    }

    private func perform(
        instanceId: String,
        expectedState: WorkspaceObservedState,
        operation: () async throws -> ApplicationInstanceStatus?
    ) async throws -> ApplicationInstanceStatus {
        let reported: ApplicationInstanceStatus?
        do {
            reported = try await operation()
        } catch {
            throw markFailure(error)
        }
        let status = normalize(
            reported ?? ApplicationInstanceStatus(
                instanceId: instanceId,
                observedState: expectedState
            ),
            instanceId: instanceId
        )
        lock.withLock {
            statuses[instanceId] = status
        }
        return status
    }

    private func normalize(
        _ status: ApplicationInstanceStatus,
        instanceId: String
    ) -> ApplicationInstanceStatus {
        let descriptor = lock.withLock { currentDescriptor }
        var normalized = status
        normalized.instanceId = instanceId
        normalized.runtimeProviderId = descriptor.id
        if normalized.deviceId == nil {
            normalized.deviceId = descriptor.deviceId
        }
        if normalized.lastHeartbeat == nil {
            normalized.lastHeartbeat = now()
        }
        return normalized
    }

    private func markFailure(_ error: Error) -> RuntimeProviderError {
        let mapped: RuntimeProviderError
        lock.lock()
        if let transportError = error as? RemoteRuntimeTransportError {
            switch transportError {
            case .unavailable:
                currentDescriptor.availability = .unavailable
                currentDescriptor.health = .open
                mapped = .transportUnavailable(providerId: currentDescriptor.id)
            case .unauthorized:
                currentDescriptor.availability = .restricted
                currentDescriptor.health = .degraded
                mapped = .authorizationDenied(providerId: currentDescriptor.id)
            case .protocolFailure(let message):
                currentDescriptor.health = .degraded
                mapped = .providerFailure(message)
            }
        } else if let runtimeError = error as? RuntimeProviderError {
            mapped = runtimeError
        } else {
            currentDescriptor.health = .degraded
            mapped = .providerFailure(error.localizedDescription)
        }
        for instanceId in Array(statuses.keys) {
            statuses[instanceId]?.lastError = mapped.localizedDescription
            statuses[instanceId]?.lastHeartbeat = now()
        }
        lock.unlock()
        return mapped
    }
}
