import Foundation

enum WorkspaceObservedState: String, Codable, CaseIterable, Sendable {
    case starting
    case running
    case suspended
    case suspendedCheckpointed = "suspended-checkpointed"
    case stopped
    case failed
    case unavailable
}

struct ApplicationInstanceStatus: Codable, Equatable, Sendable {
    var instanceId: String
    var observedState: WorkspaceObservedState
    var runtimeProviderId: String?
    var runtimeInstanceId: String?
    var deviceId: String?
    var lastHeartbeat: Date?
    var lastError: String?

    init(
        instanceId: String,
        observedState: WorkspaceObservedState,
        runtimeProviderId: String? = nil,
        runtimeInstanceId: String? = nil,
        deviceId: String? = nil,
        lastHeartbeat: Date? = nil,
        lastError: String? = nil
    ) {
        self.instanceId = instanceId
        self.observedState = observedState
        self.runtimeProviderId = runtimeProviderId
        self.runtimeInstanceId = runtimeInstanceId
        self.deviceId = deviceId
        self.lastHeartbeat = lastHeartbeat
        self.lastError = lastError
    }
}

struct WorkspaceSnapshot: Equatable, Sendable {
    var manifest: WorkspaceManifest
    var observed: [ApplicationInstanceStatus]
}

struct WorkspaceReconciliationReport: Equatable, Sendable {
    var observed: [ApplicationInstanceStatus]
    var desiredRunningWithoutObservation: [String]
    var unavailable: [String]
    var failed: [String]
    var ignored: [String]
}
