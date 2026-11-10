import Combine
import Foundation

struct WorkspaceApplicationInstancePresentation: Equatable, Identifiable {
    var id: String
    var applicationId: String
    var applicationName: String
    var applicationVersion: String
    var desiredState: WorkspaceDesiredState
    var observedState: WorkspaceObservedState
    var runtimeProviderId: String?
    var lastError: String?
    var supportsCooperativeCheckpoint: Bool

    var canStart: Bool {
        observedState != .running && observedState != .starting
    }

    var canSuspend: Bool {
        observedState == .running
    }

    var canResume: Bool {
        observedState == .suspended || observedState == .suspendedCheckpointed
    }

    var canCheckpoint: Bool {
        supportsCooperativeCheckpoint
            && (observedState == .running || observedState == .suspended)
    }

    var canStop: Bool {
        observedState != .stopped
    }
}

@MainActor
final class WorkspaceLifecycleStore: ObservableObject {
    let host: WorkspaceHost
    let controller: ApplicationLifecycleController

    @Published private(set) var instances: [WorkspaceApplicationInstancePresentation] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var busyInstanceId: String?

    init(
        host: WorkspaceHost,
        registry: RuntimeRegistry? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.host = host
        self.controller = ApplicationLifecycleController(
            host: host,
            registry: registry ?? RuntimeRegistry.standard(hostDeviceId: host.deviceId),
            now: now
        )
        refresh()
    }

    func refresh() {
        do {
            _ = try controller.reconcile()
            try publish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(_ instanceId: String) async {
        await perform(instanceId) {
            _ = try await controller.start(instanceId: instanceId)
        }
    }

    func suspend(_ instanceId: String) async {
        await perform(instanceId) {
            _ = try await controller.suspend(instanceId: instanceId)
        }
    }

    func checkpoint(_ instanceId: String) async {
        await perform(instanceId) {
            _ = try await controller.checkpoint(instanceId: instanceId)
        }
    }

    func resume(_ instanceId: String) async {
        await perform(instanceId) {
            _ = try await controller.resume(instanceId: instanceId)
        }
    }

    func stop(_ instanceId: String) async {
        await perform(instanceId) {
            _ = try await controller.stop(instanceId: instanceId)
        }
    }

    private func perform(
        _ instanceId: String,
        _ action: () async throws -> Void
    ) async {
        guard busyInstanceId == nil else { return }
        busyInstanceId = instanceId
        errorMessage = nil
        defer { busyInstanceId = nil }

        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    private func publish() throws {
        guard let manifest = try host.load() else {
            instances = []
            return
        }
        let applications = Dictionary(
            uniqueKeysWithValues: manifest.applications.map { ($0.id, $0) }
        )
        instances = manifest.instances.map { instance in
            let application = applications[instance.applicationId]
            let status = controller.status(for: instance.id)
            return WorkspaceApplicationInstancePresentation(
                id: instance.id,
                applicationId: instance.applicationId,
                applicationName: application?.name ?? instance.applicationId,
                applicationVersion: application?.version ?? "unknown",
                desiredState: instance.desiredState,
                observedState: status?.observedState ?? .unavailable,
                runtimeProviderId: status?.runtimeProviderId ?? instance.placement?.providerId,
                lastError: status?.lastError,
                supportsCooperativeCheckpoint: application?.supportsCooperativeCheckpoint == true
            )
        }
        .sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }
    }
}

extension WorkspaceObservedState {
    var title: String {
        switch self {
        case .starting: return "Starting"
        case .running: return "Running"
        case .suspended: return "Suspended"
        case .suspendedCheckpointed: return "Checkpointed"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        case .unavailable: return "Unavailable"
        }
    }
}

extension WorkspaceDesiredState {
    var title: String {
        switch self {
        case .running: return "Running"
        case .suspended: return "Suspended"
        case .stopped: return "Stopped"
        }
    }
}
