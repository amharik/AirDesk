import Foundation

final class WorkspaceOrchestrator {
    let host: WorkspaceHost

    private let now: () -> Date
    private let lock = NSLock()
    private var observedByInstance: [String: ApplicationInstanceStatus] = [:]

    init(host: WorkspaceHost, now: @escaping () -> Date = Date.init) {
        self.host = host
        self.now = now
    }

    @discardableResult
    func open(
        owner: WorkspaceOwner,
        name: String,
        id: String = UUID().uuidString.lowercased()
    ) throws -> WorkspaceSnapshot {
        if let manifest = try loadManifest() {
            return makeSnapshot(manifest)
        }

        do {
            let created = try host.create(owner: owner, name: name, id: id)
            return makeSnapshot(created)
        } catch let error as WorkspaceHostError {
            throw WorkspaceOrchestratorError.host(error)
        }
    }

    @discardableResult
    func attach(
        _ instance: WorkspaceApplicationInstance,
        preferredProviderId: String? = nil
    ) throws -> WorkspaceManifest {
        guard let current = try loadManifest() else {
            throw WorkspaceOrchestratorError.workspaceMissing
        }

        do {
            return try host.mutate(expectedWorkspaceSeq: current.workspaceSeq) { manifest in
                guard manifest.applications.contains(where: { $0.id == instance.applicationId }) else {
                    throw WorkspaceOrchestratorError.applicationMissing(
                        instanceId: instance.id,
                        applicationId: instance.applicationId
                    )
                }
                guard !manifest.instances.contains(where: { $0.id == instance.id }) else {
                    throw WorkspaceOrchestratorError.instanceAlreadyExists(instance.id)
                }

                manifest.instances.append(instance)
                if let preferredProviderId {
                    manifest.executionBindings.append(
                        WorkspaceExecutionBinding(
                            instanceId: instance.id,
                            preferredProviderId: preferredProviderId,
                            fallbackPolicy: .deny
                        )
                    )
                }
            }
        } catch let error as WorkspaceHostError {
            throw WorkspaceOrchestratorError.host(error)
        }
    }

    @discardableResult
    func place(
        instanceId: String,
        deviceId: String?,
        providerId: String?
    ) throws -> WorkspaceManifest {
        guard let current = try loadManifest() else {
            throw WorkspaceOrchestratorError.workspaceMissing
        }

        do {
            return try host.mutate(expectedWorkspaceSeq: current.workspaceSeq) { manifest in
                guard let index = manifest.instances.firstIndex(where: { $0.id == instanceId }) else {
                    throw WorkspaceOrchestratorError.instanceMissing(instanceId)
                }
                manifest.instances[index].placement = WorkspacePlacement(
                    deviceId: deviceId,
                    providerId: providerId
                )
            }
        } catch let error as WorkspaceHostError {
            throw WorkspaceOrchestratorError.host(error)
        }
    }

    @discardableResult
    func reconcile(_ statuses: [ApplicationInstanceStatus]) throws -> WorkspaceReconciliationReport {
        guard let manifest = try loadManifest() else {
            throw WorkspaceOrchestratorError.workspaceMissing
        }

        let known = Set(manifest.instances.map(\.id))
        let accepted = statuses.filter { known.contains($0.instanceId) }
        let ignored = statuses.map(\.instanceId).filter { !known.contains($0) }

        lock.lock()
        for status in accepted {
            observedByInstance[status.instanceId] = status
        }
        let observed = observedByInstance.values.sorted { $0.instanceId < $1.instanceId }
        lock.unlock()

        let observedIds = Set(observed.map(\.instanceId))
        let desiredRunningWithoutObservation = manifest.instances
            .filter { $0.desiredState == .running && !observedIds.contains($0.id) }
            .map(\.id)
        let unavailable = observed
            .filter { $0.observedState == .unavailable }
            .map(\.instanceId)
        let failed = observed
            .filter { $0.observedState == .failed }
            .map(\.instanceId)

        return WorkspaceReconciliationReport(
            observed: observed,
            desiredRunningWithoutObservation: desiredRunningWithoutObservation,
            unavailable: unavailable,
            failed: failed,
            ignored: ignored
        )
    }

    @discardableResult
    func markUnavailable(instanceId: String, reason: String) throws -> ApplicationInstanceStatus {
        guard let manifest = try loadManifest() else {
            throw WorkspaceOrchestratorError.workspaceMissing
        }
        guard manifest.instances.contains(where: { $0.id == instanceId }) else {
            throw WorkspaceOrchestratorError.instanceMissing(instanceId)
        }

        let status = ApplicationInstanceStatus(
            instanceId: instanceId,
            observedState: .unavailable,
            lastHeartbeat: now(),
            lastError: reason
        )
        lock.lock()
        observedByInstance[instanceId] = status
        lock.unlock()
        return status
    }

    func snapshot() throws -> WorkspaceSnapshot {
        guard let manifest = try loadManifest() else {
            throw WorkspaceOrchestratorError.workspaceMissing
        }
        return makeSnapshot(manifest)
    }

    func status(for instanceId: String) -> ApplicationInstanceStatus? {
        lock.lock()
        defer { lock.unlock() }
        return observedByInstance[instanceId]
    }

    private func makeSnapshot(_ manifest: WorkspaceManifest) -> WorkspaceSnapshot {
        lock.lock()
        let observed = observedByInstance.values.sorted { $0.instanceId < $1.instanceId }
        lock.unlock()
        return WorkspaceSnapshot(manifest: manifest, observed: observed)
    }

    private func loadManifest() throws -> WorkspaceManifest? {
        do {
            return try host.load()
        } catch let error as WorkspaceHostError {
            throw WorkspaceOrchestratorError.host(error)
        }
    }
}

enum WorkspaceOrchestratorError: Error, Equatable, LocalizedError {
    case workspaceMissing
    case applicationMissing(instanceId: String, applicationId: String)
    case instanceMissing(String)
    case instanceAlreadyExists(String)
    case host(WorkspaceHostError)

    var errorDescription: String? {
        switch self {
        case .workspaceMissing:
            return "No workspace exists yet."
        case .applicationMissing(let instanceId, let applicationId):
            return "Instance \(instanceId) references missing application \(applicationId)."
        case .instanceMissing(let instanceId):
            return "Application instance \(instanceId) does not exist."
        case .instanceAlreadyExists(let instanceId):
            return "Application instance \(instanceId) already exists."
        case .host(let error):
            return error.localizedDescription
        }
    }
}
