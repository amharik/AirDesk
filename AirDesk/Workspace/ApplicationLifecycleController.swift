import Foundation

final class ApplicationLifecycleController {
    let host: WorkspaceHost
    let registry: RuntimeRegistry

    private let lock = NSLock()
    private var observedByInstance: [String: ApplicationInstanceStatus] = [:]
    private let now: () -> Date

    init(
        host: WorkspaceHost,
        registry: RuntimeRegistry,
        now: @escaping () -> Date = Date.init
    ) {
        self.host = host
        self.registry = registry
        self.now = now
    }

    @discardableResult
    func install(_ application: WorkspaceApplication) throws -> WorkspaceManifest {
        try mutate { manifest in
            guard !manifest.applications.contains(where: { $0.id == application.id }) else {
                throw ApplicationLifecycleError.applicationAlreadyExists(application.id)
            }
            manifest.applications.append(application)
        }
    }

    @discardableResult
    func uninstall(applicationId: String) throws -> WorkspaceManifest {
        try mutate { manifest in
            guard manifest.applications.contains(where: { $0.id == applicationId }) else {
                throw ApplicationLifecycleError.applicationMissing(applicationId)
            }
            guard !manifest.instances.contains(where: { $0.applicationId == applicationId }) else {
                throw ApplicationLifecycleError.applicationInUse(applicationId)
            }
            manifest.applications.removeAll { $0.id == applicationId }
        }
    }

    @discardableResult
    func start(
        instanceId: String,
        threading: RuntimeThreadingProfile = .singleThreaded
    ) async throws -> ApplicationInstanceStatus {
        guard let manifest = try loadManifest() else {
            throw ApplicationLifecycleError.workspaceMissing
        }
        guard let instance = manifest.instances.first(where: { $0.id == instanceId }) else {
            throw ApplicationLifecycleError.instanceMissing(instanceId)
        }
        guard let application = manifest.applications.first(where: { $0.id == instance.applicationId }) else {
            throw ApplicationLifecycleError.applicationMissing(instance.applicationId)
        }

        let binding = manifest.executionBindings.first { $0.instanceId == instanceId }
        let selection = try select(
            application: application,
            binding: binding,
            placement: instance.placement,
            threading: threading
        )
        let provider = try registry.provider(id: selection.providerId)

        let request = RuntimeCreateRequest(
            instanceId: instanceId,
            application: application,
            world: selection.world,
            threading: threading
        )
        if provider.status(instanceId: instanceId) == nil {
            try await provider.create(request)
        }
        try await provider.start(instanceId: instanceId)

        do {
            _ = try mutate { manifest in
                guard let index = manifest.instances.firstIndex(where: { $0.id == instanceId }) else {
                    throw ApplicationLifecycleError.instanceMissing(instanceId)
                }
                var placement = manifest.instances[index].placement ?? WorkspacePlacement()
                placement.providerId = selection.providerId
                manifest.instances[index].placement = placement
                manifest.instances[index].desiredState = .running

                if let bindingIndex = manifest.executionBindings.firstIndex(where: {
                    $0.instanceId == instanceId
                }) {
                    manifest.executionBindings[bindingIndex].preferredProviderId = selection.providerId
                    manifest.executionBindings[bindingIndex].pinnedWorld = selection.world.rawValue
                } else {
                    manifest.executionBindings.append(WorkspaceExecutionBinding(
                        instanceId: instanceId,
                        preferredProviderId: selection.providerId,
                        fallbackPolicy: .localOnly,
                        pinnedWorld: selection.world.rawValue
                    ))
                }
            }
        } catch {
            try? await provider.destroy(instanceId: instanceId)
            throw error
        }

        return record(provider.status(instanceId: instanceId) ?? ApplicationInstanceStatus(
            instanceId: instanceId,
            observedState: .starting,
            runtimeProviderId: selection.providerId,
            lastHeartbeat: now()
        ))
    }

    @discardableResult
    func suspend(instanceId: String) async throws -> ApplicationInstanceStatus {
        let provider = try providerForInstance(instanceId)
        try await provider.suspend(instanceId: instanceId)
        try setDesiredState(instanceId, .suspended)
        return record(try requireStatus(instanceId, provider: provider))
    }

    @discardableResult
    func checkpoint(instanceId: String) async throws -> ApplicationInstanceStatus {
        let provider = try providerForInstance(instanceId)
        try await provider.checkpoint(instanceId: instanceId)
        try setDesiredState(instanceId, .suspended)
        return record(try requireStatus(instanceId, provider: provider))
    }

    @discardableResult
    func resume(
        instanceId: String,
        threading: RuntimeThreadingProfile = .singleThreaded
    ) async throws -> ApplicationInstanceStatus {
        let provider = try providerForInstance(instanceId)
        try await provider.resume(instanceId: instanceId)
        try setDesiredState(instanceId, .running)
        return record(try requireStatus(instanceId, provider: provider))
    }

    @discardableResult
    func stop(instanceId: String) async throws -> ApplicationInstanceStatus {
        guard let manifest = try loadManifest() else {
            throw ApplicationLifecycleError.workspaceMissing
        }
        guard manifest.instances.contains(where: { $0.id == instanceId }) else {
            throw ApplicationLifecycleError.instanceMissing(instanceId)
        }

        if let provider = try? providerForInstance(instanceId),
           provider.status(instanceId: instanceId) != nil {
            try await provider.stop(instanceId: instanceId)
            _ = record(try requireStatus(instanceId, provider: provider))
        } else {
            _ = record(ApplicationInstanceStatus(
                instanceId: instanceId,
                observedState: .stopped,
                lastHeartbeat: now()
            ))
        }

        try setDesiredState(instanceId, .stopped)
        return status(for: instanceId) ?? ApplicationInstanceStatus(
            instanceId: instanceId,
            observedState: .stopped,
            lastHeartbeat: now()
        )
    }

    @discardableResult
    func destroy(instanceId: String) async throws -> WorkspaceManifest {
        if let provider = try? providerForInstance(instanceId) {
            try? await provider.destroy(instanceId: instanceId)
        }
        lock.withLock {
            _ = observedByInstance.removeValue(forKey: instanceId)
        }
        return try mutate { manifest in
            guard manifest.instances.contains(where: { $0.id == instanceId }) else {
                throw ApplicationLifecycleError.instanceMissing(instanceId)
            }
            manifest.instances.removeAll { $0.id == instanceId }
            manifest.executionBindings.removeAll { $0.instanceId == instanceId }
            manifest.layout.windows.removeAll { $0.instanceId == instanceId }
            let remainingWindows = Set(manifest.layout.windows.map(\.id))
            manifest.layout.focusOrder.removeAll { !remainingWindows.contains($0) }
            if let active = manifest.layout.activeWindowId,
               !remainingWindows.contains(active) {
                manifest.layout.activeWindowId = nil
            }
        }
    }

    func status(for instanceId: String) -> ApplicationInstanceStatus? {
        lock.withLock {
            observedByInstance[instanceId]
        }
    }

    func reconcile() throws -> WorkspaceReconciliationReport {
        guard let manifest = try loadManifest() else {
            throw ApplicationLifecycleError.workspaceMissing
        }

        var statuses: [ApplicationInstanceStatus] = []
        for instance in manifest.instances {
            if let provider = try? providerForInstance(instance.id),
               let status = provider.status(instanceId: instance.id) {
                statuses.append(status)
            } else {
                statuses.append(ApplicationInstanceStatus(
                    instanceId: instance.id,
                    observedState: .unavailable,
                    lastHeartbeat: now(),
                    lastError: "No runtime provider is available."
                ))
            }
        }

        lock.withLock {
            observedByInstance = Dictionary(uniqueKeysWithValues: statuses.map { ($0.instanceId, $0) })
        }

        let observedIDs = Set(statuses.map(\.instanceId))
        return WorkspaceReconciliationReport(
            observed: statuses.sorted { $0.instanceId < $1.instanceId },
            desiredRunningWithoutObservation: manifest.instances
                .filter { $0.desiredState == .running && !observedIDs.contains($0.id) }
                .map(\.id),
            unavailable: statuses.filter { $0.observedState == .unavailable }.map(\.instanceId),
            failed: statuses.filter { $0.observedState == .failed }.map(\.instanceId),
            ignored: []
        )
    }

    private func select(
        application: WorkspaceApplication,
        binding: WorkspaceExecutionBinding?,
        placement: WorkspacePlacement?,
        threading: RuntimeThreadingProfile
    ) throws -> RuntimeProviderSelection {
        do {
            return try registry.select(
                application: application,
                binding: binding,
                placement: placement,
                threading: threading
            )
        } catch let error as RuntimeProviderError {
            throw ApplicationLifecycleError.provider(error)
        }
    }

    private func providerForInstance(_ instanceId: String) throws -> any RuntimeProvider {
        guard let manifest = try loadManifest() else {
            throw ApplicationLifecycleError.workspaceMissing
        }
        guard let instance = manifest.instances.first(where: { $0.id == instanceId }) else {
            throw ApplicationLifecycleError.instanceMissing(instanceId)
        }
        if let providerID = instance.placement?.providerId {
            do { return try registry.provider(id: providerID) }
            catch let error as RuntimeProviderError {
                throw ApplicationLifecycleError.provider(error)
            }
        }
        if let providerID = manifest.executionBindings.first(where: {
            $0.instanceId == instanceId
        })?.preferredProviderId {
            do { return try registry.provider(id: providerID) }
            catch let error as RuntimeProviderError {
                throw ApplicationLifecycleError.provider(error)
            }
        }
        throw ApplicationLifecycleError.noProvider(instanceId)
    }

    private func requireStatus(
        _ instanceId: String,
        provider: any RuntimeProvider
    ) throws -> ApplicationInstanceStatus {
        guard let status = provider.status(instanceId: instanceId) else {
            throw ApplicationLifecycleError.provider(.instanceMissing(instanceId))
        }
        return status
    }

    private func setDesiredState(
        _ instanceId: String,
        _ desiredState: WorkspaceDesiredState
    ) throws {
        _ = try mutate { manifest in
            guard let index = manifest.instances.firstIndex(where: { $0.id == instanceId }) else {
                throw ApplicationLifecycleError.instanceMissing(instanceId)
            }
            manifest.instances[index].desiredState = desiredState
        }
    }

    private func record(_ status: ApplicationInstanceStatus) -> ApplicationInstanceStatus {
        lock.withLock {
            observedByInstance[status.instanceId] = status
        }
        return status
    }

    private func mutate(
        _ body: (inout WorkspaceManifest) throws -> Void
    ) throws -> WorkspaceManifest {
        guard let current = try loadManifest() else {
            throw ApplicationLifecycleError.workspaceMissing
        }
        do {
            return try host.mutate(expectedWorkspaceSeq: current.workspaceSeq, body)
        } catch let error as WorkspaceHostError {
            throw ApplicationLifecycleError.host(error)
        }
    }

    private func loadManifest() throws -> WorkspaceManifest? {
        do {
            return try host.load()
        } catch let error as WorkspaceHostError {
            throw ApplicationLifecycleError.host(error)
        }
    }
}

enum ApplicationLifecycleError: Error, Equatable, LocalizedError {
    case workspaceMissing
    case applicationMissing(String)
    case applicationAlreadyExists(String)
    case applicationInUse(String)
    case instanceMissing(String)
    case noProvider(String)
    case host(WorkspaceHostError)
    case provider(RuntimeProviderError)

    var errorDescription: String? {
        switch self {
        case .workspaceMissing:
            return "No workspace exists yet."
        case .applicationMissing(let id):
            return "Application \(id) is not installed."
        case .applicationAlreadyExists(let id):
            return "Application \(id) is already installed."
        case .applicationInUse(let id):
            return "Application \(id) still has instances."
        case .instanceMissing(let id):
            return "Application instance \(id) does not exist."
        case .noProvider(let id):
            return "Application instance \(id) has no runtime provider."
        case .host(let error):
            return error.localizedDescription
        case .provider(let error):
            return error.localizedDescription
        }
    }
}
