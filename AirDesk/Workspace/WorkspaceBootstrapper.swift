import Foundation

enum WorkspaceRestoreOutcome: String, Equatable, Sendable {
    case created
    case restored
    case recovered
}

enum WorkspaceInstanceRestoreState: Equatable, Sendable {
    case restored(instanceId: String)
    case restarted(instanceId: String)
    case reconnected(instanceId: String)
    case lost(instanceId: String, reason: String)
}

struct WorkspaceRestoreReport: Equatable, Sendable {
    var outcome: WorkspaceRestoreOutcome
    var workspaceId: String
    var workspaceName: String
    var createdAt: Date
    var recoveryWarning: WorkspaceStoreError?
    var instances: [WorkspaceInstanceRestoreState]

    var needsAttention: Bool {
        recoveryWarning != nil || instances.contains { state in
            if case .lost = state { return true }
            return false
        }
    }
}

final class WorkspaceBootstrapper {
    let store: NativeWorkspaceStore
    let host: WorkspaceHost
    let orchestrator: WorkspaceOrchestrator

    private let bootWarning: WorkspaceStoreError?

    init(
        store: NativeWorkspaceStore,
        deviceId: String,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.store = store
        self.host = try WorkspaceHost(store: store, deviceId: deviceId, now: now)
        self.orchestrator = WorkspaceOrchestrator(host: host, now: now)
        self.bootWarning = store.lastRecoveryWarning
    }

    static func applicationSupport(
        deviceId: String,
        fileManager: FileManager = .default
    ) throws -> WorkspaceBootstrapper {
        let store = try NativeWorkspaceStore.applicationSupport(fileManager: fileManager)
        return try WorkspaceBootstrapper(store: store, deviceId: deviceId)
    }

    func restore(
        owner: WorkspaceOwner,
        name: String,
        id: String = UUID().uuidString.lowercased()
    ) throws -> WorkspaceRestoreReport {
        if let manifest = host.currentManifest {
            return makeReport(
                manifest,
                outcome: bootWarning == nil ? .restored : .recovered,
                warning: bootWarning,
                observed: []
            )
        }

        let created = try host.create(owner: owner, name: name, id: id)
        return makeReport(created, outcome: .created, warning: nil, observed: [])
    }

    func makeReport(
        _ manifest: WorkspaceManifest,
        outcome: WorkspaceRestoreOutcome,
        warning: WorkspaceStoreError?,
        observed: [ApplicationInstanceStatus]
    ) -> WorkspaceRestoreReport {
        let observedById = Dictionary(uniqueKeysWithValues: observed.map { ($0.instanceId, $0) })
        let instances = manifest.instances.map { instance in
            Self.restoreState(for: instance, observed: observedById[instance.id])
        }
        return WorkspaceRestoreReport(
            outcome: outcome,
            workspaceId: manifest.id,
            workspaceName: manifest.metadata.name,
            createdAt: manifest.metadata.createdAt,
            recoveryWarning: warning,
            instances: instances
        )
    }

    private static func restoreState(
        for instance: WorkspaceApplicationInstance,
        observed: ApplicationInstanceStatus?
    ) -> WorkspaceInstanceRestoreState {
        switch instance.desiredState {
        case .stopped, .suspended:
            return .restored(instanceId: instance.id)
        case .running:
            guard let observed else {
                return .restarted(instanceId: instance.id)
            }
            switch observed.observedState {
            case .running:
                return .reconnected(instanceId: instance.id)
            case .starting:
                return .restarted(instanceId: instance.id)
            case .stopped, .suspended, .suspendedCheckpointed:
                return .restored(instanceId: instance.id)
            case .failed:
                return .lost(
                    instanceId: instance.id,
                    reason: observed.lastError ?? "The runtime failed."
                )
            case .unavailable:
                return .lost(
                    instanceId: instance.id,
                    reason: observed.lastError ?? "The runtime is unavailable."
                )
            }
        }
    }
}
