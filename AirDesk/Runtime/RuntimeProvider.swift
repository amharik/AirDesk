import Foundation

enum RuntimeWorld: String, Codable, CaseIterable, Sendable {
    case wasip1
    case wasiCLI02 = "wasi-cli@0.2"
    case wasiHTTP02 = "wasi-http@0.2"
    case wasiFilesystem02 = "wasi-filesystem@0.2"
    case wasiSockets02 = "wasi-sockets@0.2"
    case native
    case browser
}

enum RuntimeThreadingProfile: String, Codable, CaseIterable, Sendable {
    case singleThreaded = "single-threaded"
    case sharedMemory = "shared-memory"
}

enum RuntimeProviderAvailability: String, Codable, CaseIterable, Sendable {
    case available
    case busy
    case unavailable
    case restricted
}

enum RuntimeProviderHealth: String, Codable, CaseIterable, Sendable {
    case healthy
    case degraded
    case open
    case halfOpen = "half-open"
}

struct RuntimeProviderDescriptor: Equatable, Sendable {
    var id: String
    var displayName: String
    var location: RuntimeLocation
    var deviceId: String?
    var version: String
    var supportedWorlds: Set<RuntimeWorld>
    var architectures: Set<String>
    var capabilities: RuntimeCapabilities
    var availability: RuntimeProviderAvailability
    var health: RuntimeProviderHealth
    var threadingProfiles: Set<RuntimeThreadingProfile>
    var enforcedQuotas: Set<WorkspaceQuotaKind>

    init(
        id: String,
        displayName: String,
        location: RuntimeLocation,
        deviceId: String? = nil,
        version: String,
        supportedWorlds: Set<RuntimeWorld>,
        architectures: Set<String>,
        capabilities: RuntimeCapabilities,
        availability: RuntimeProviderAvailability = .available,
        health: RuntimeProviderHealth = .healthy,
        threadingProfiles: Set<RuntimeThreadingProfile> = [.singleThreaded],
        enforcedQuotas: Set<WorkspaceQuotaKind> = Set(WorkspaceQuotaKind.allCases)
    ) {
        self.id = id
        self.displayName = displayName
        self.location = location
        self.deviceId = deviceId
        self.version = version
        self.supportedWorlds = supportedWorlds
        self.architectures = architectures
        self.capabilities = capabilities
        self.availability = availability
        self.health = health
        self.threadingProfiles = threadingProfiles
        self.enforcedQuotas = enforcedQuotas
    }
}

enum RuntimePlacementOutcome: String, Codable, Sendable {
    case selected
    case eligible
    case deviceMismatch = "device-mismatch"
    case placementMismatch = "placement-mismatch"
    case unavailable
    case pinnedWorldMismatch = "pinned-world-mismatch"
    case unsupportedWorld = "unsupported-world"
    case unsupportedArchitecture = "unsupported-architecture"
    case capabilityUnsupported = "capability-unsupported"
    case quotaUnenforceable = "quota-unenforceable"
    case synchronizationUnavailable = "synchronization-unavailable"
}

struct RuntimePlacementDiagnostic: Equatable, Sendable {
    var providerId: String
    var deviceId: String?
    var world: String?
    var location: RuntimeLocation
    var outcome: RuntimePlacementOutcome
    var reason: String
}

struct RuntimeProviderSelection: Equatable, Sendable {
    var providerId: String
    var deviceId: String?
    var world: RuntimeWorld
    var rationale: String
    var diagnostics: [RuntimePlacementDiagnostic]

    init(
        providerId: String,
        deviceId: String? = nil,
        world: RuntimeWorld,
        rationale: String,
        diagnostics: [RuntimePlacementDiagnostic] = []
    ) {
        self.providerId = providerId
        self.deviceId = deviceId
        self.world = world
        self.rationale = rationale
        self.diagnostics = diagnostics
    }
}

struct RuntimeCreateRequest: Equatable, Sendable {
    var instanceId: String
    var application: WorkspaceApplication
    var world: RuntimeWorld
    var threading: RuntimeThreadingProfile = .singleThreaded
}

protocol RuntimeProvider: AnyObject {
    var descriptor: RuntimeProviderDescriptor { get }

    func create(_ request: RuntimeCreateRequest) async throws
    func start(instanceId: String) async throws
    func suspend(instanceId: String) async throws
    func checkpoint(instanceId: String) async throws
    func resume(instanceId: String) async throws
    func stop(instanceId: String) async throws
    func destroy(instanceId: String) async throws
    func status(instanceId: String) -> ApplicationInstanceStatus?
}

enum RuntimeProviderError: Error, Equatable, LocalizedError {
    case duplicateProvider(String)
    case unknownProvider(String)
    case noQualifiedProvider(applicationId: String)
    case providerUnavailable(String)
    case deviceMismatch(deviceId: String)
    case transportUnavailable(providerId: String)
    case authorizationDenied(providerId: String)
    case unsupportedWorld(providerId: String, world: RuntimeWorld)
    case unknownWorld(providerId: String, world: String)
    case unsupportedArchitecture(providerId: String, architecture: String)
    case capabilityUnsupported(String)
    case versionMismatch(providerId: String, expected: String)
    case quotaUnenforceable(providerId: String, quota: WorkspaceQuotaKind)
    case synchronizationUnavailable(providerId: String)
    case cooperativeCheckpointUnsupported(instanceId: String)
    case instanceMissing(String)
    case instanceAlreadyExists(String)
    case invalidTransition(instanceId: String, from: WorkspaceObservedState, to: WorkspaceObservedState)
    case providerFailure(String)

    var errorDescription: String? {
        switch self {
        case .duplicateProvider(let id):
            return "Runtime provider \(id) is already registered."
        case .unknownProvider(let id):
            return "Runtime provider \(id) is not registered."
        case .noQualifiedProvider(let applicationId):
            return "No available runtime provider can place application \(applicationId)."
        case .providerUnavailable(let id):
            return "Runtime provider \(id) is unavailable."
        case .deviceMismatch(let deviceId):
            return "No registered runtime provider belongs to device \(deviceId)."
        case .transportUnavailable(let providerId):
            return "Runtime provider \(providerId) cannot reach its transport."
        case .authorizationDenied(let providerId):
            return "Runtime provider \(providerId) denied authorization."
        case .unsupportedWorld(let providerId, let world):
            return "Runtime provider \(providerId) does not support world \(world.rawValue)."
        case .unknownWorld(let providerId, let world):
            return "Runtime provider \(providerId) does not recognize world \(world)."
        case .unsupportedArchitecture(let providerId, let architecture):
            return "Runtime provider \(providerId) does not support architecture \(architecture)."
        case .capabilityUnsupported(let capability):
            return "The selected runtime provider does not advertise \(capability)."
        case .versionMismatch(let providerId, let expected):
            return "Runtime provider \(providerId) does not satisfy version \(expected)."
        case .quotaUnenforceable(let providerId, let quota):
            return "Runtime provider \(providerId) cannot enforce the required \(quota.rawValue) quota."
        case .synchronizationUnavailable(let providerId):
            return "Runtime provider \(providerId) cannot provide the requested synchronization profile."
        case .cooperativeCheckpointUnsupported(let id):
            return "Runtime instance \(id) does not support app-cooperative checkpoints."
        case .instanceMissing(let id):
            return "Runtime instance \(id) does not exist."
        case .instanceAlreadyExists(let id):
            return "Runtime instance \(id) already exists."
        case .invalidTransition(let id, let from, let to):
            return "Runtime instance \(id) cannot transition from \(from.rawValue) to \(to.rawValue)."
        case .providerFailure(let message):
            return message
        }
    }
}

extension RuntimeCapabilities {
    func supports(capability: String) -> Bool {
        switch capability {
        case "windows", "desktop-windows": return desktopWindows
        case "terminal": return terminal
        case "filesystem", "files": return filesystem
        case "workbench": return workbench
        case "browser": return browser
        case "persistent-storage": return persistentStorage
        case "live-kernel": return liveKernel
        case "tasks", "task-execution": return taskExecution
        default: return false
        }
    }
}

class ManagedRuntimeProvider: RuntimeProvider {
    private struct Instance {
        var request: RuntimeCreateRequest
        var state: WorkspaceObservedState
        var lastError: String?
        var checkpointed: Bool
    }

    private(set) var descriptor: RuntimeProviderDescriptor
    private var instances: [String: Instance] = [:]
    private let lock = NSLock()

    init(descriptor: RuntimeProviderDescriptor) {
        self.descriptor = descriptor
    }

    func setAvailability(_ availability: RuntimeProviderAvailability) {
        lock.lock()
        descriptor.availability = availability
        lock.unlock()
    }

    func setHealth(_ health: RuntimeProviderHealth) {
        lock.lock()
        descriptor.health = health
        lock.unlock()
    }

    func create(_ request: RuntimeCreateRequest) async throws {
        try lock.withLock {
            guard descriptor.supportedWorlds.contains(request.world) else {
                throw RuntimeProviderError.unsupportedWorld(providerId: descriptor.id, world: request.world)
            }
            guard descriptor.threadingProfiles.contains(request.threading) else {
                throw RuntimeProviderError.synchronizationUnavailable(providerId: descriptor.id)
            }
            guard !instances.keys.contains(request.instanceId) else {
                throw RuntimeProviderError.instanceAlreadyExists(request.instanceId)
            }
            guard request.application.runtimeTargets.contains(where: {
                $0.provider == descriptor.id && $0.world == request.world.rawValue
            }) else {
                throw RuntimeProviderError.unsupportedWorld(providerId: descriptor.id, world: request.world)
            }
            instances[request.instanceId] = Instance(
                request: request,
                state: .stopped,
                lastError: nil,
                checkpointed: false
            )
        }
    }

    func start(instanceId: String) async throws {
        try transition(instanceId, to: .running) { instance in
            guard instance.state == .stopped || instance.state == .suspended
                    || instance.state == .suspendedCheckpointed || instance.state == .failed else {
                throw RuntimeProviderError.invalidTransition(
                    instanceId: instanceId,
                    from: instance.state,
                    to: .running
                )
            }
            instance.state = .running
            instance.lastError = nil
        }
    }

    func suspend(instanceId: String) async throws {
        try transition(instanceId, to: .suspended) { instance in
            guard instance.state == .running else {
                throw RuntimeProviderError.invalidTransition(
                    instanceId: instanceId,
                    from: instance.state,
                    to: .suspended
                )
            }
            instance.state = .suspended
            instance.checkpointed = false
        }
    }

    func checkpoint(instanceId: String) async throws {
        try transition(instanceId, to: .suspendedCheckpointed) { instance in
            guard instance.request.application.supportsCooperativeCheckpoint else {
                throw RuntimeProviderError.cooperativeCheckpointUnsupported(instanceId: instanceId)
            }
            guard instance.state == .running || instance.state == .suspended else {
                throw RuntimeProviderError.invalidTransition(
                    instanceId: instanceId,
                    from: instance.state,
                    to: .suspendedCheckpointed
                )
            }
            instance.state = .suspendedCheckpointed
            instance.checkpointed = true
        }
    }

    func resume(instanceId: String) async throws {
        try transition(instanceId, to: .running) { instance in
            guard instance.state == .suspended || instance.state == .suspendedCheckpointed else {
                throw RuntimeProviderError.invalidTransition(
                    instanceId: instanceId,
                    from: instance.state,
                    to: .running
                )
            }
            instance.state = .running
            instance.checkpointed = false
        }
    }

    func stop(instanceId: String) async throws {
        try transition(instanceId, to: .stopped) { instance in
            if instance.state != .stopped {
                instance.state = .stopped
            }
            instance.checkpointed = false
        }
    }

    func destroy(instanceId: String) async throws {
        try lock.withLock {
            guard instances.removeValue(forKey: instanceId) != nil else {
                throw RuntimeProviderError.instanceMissing(instanceId)
            }
        }
    }

    func status(instanceId: String) -> ApplicationInstanceStatus? {
        lock.withLock {
            guard let instance = instances[instanceId] else { return nil }
            return ApplicationInstanceStatus(
                instanceId: instanceId,
                observedState: instance.state,
                runtimeProviderId: descriptor.id,
                deviceId: nil,
                lastHeartbeat: Date(),
                lastError: instance.lastError
            )
        }
    }

    func markFailed(instanceId: String, reason: String) throws {
        try transition(instanceId, to: .failed) { instance in
            instance.state = .failed
            instance.lastError = reason
        }
    }

    private func transition(
        _ instanceId: String,
        to: WorkspaceObservedState,
        _ body: (inout Instance) throws -> Void
    ) throws {
        try lock.withLock {
            guard var instance = instances[instanceId] else {
                throw RuntimeProviderError.instanceMissing(instanceId)
            }
            try body(&instance)
            instances[instanceId] = instance
        }
    }
}

final class WanixRuntimeProvider: ManagedRuntimeProvider {
    init(
        availability: RuntimeProviderAvailability = .available,
        health: RuntimeProviderHealth = .healthy
    ) {
        super.init(descriptor: RuntimeProviderDescriptor(
            id: "wanix",
            displayName: "Wanix",
            location: .phone,
            version: "1.0",
            supportedWorlds: [.wasip1],
            architectures: ["wasm32"],
            capabilities: .wanixDesktop,
            availability: availability,
            health: health,
            threadingProfiles: [.singleThreaded],
            enforcedQuotas: Set(WorkspaceQuotaKind.allCases)
        ))
    }
}

final class NativeRuntimeProvider: ManagedRuntimeProvider {
    init(
        availability: RuntimeProviderAvailability = .available,
        health: RuntimeProviderHealth = .healthy
    ) {
        super.init(descriptor: RuntimeProviderDescriptor(
            id: "native",
            displayName: "Native",
            location: .phone,
            version: "1.0",
            supportedWorlds: [
                .wasiCLI02,
                .wasiHTTP02,
                .wasiFilesystem02,
                .wasiSockets02,
                .native
            ],
            architectures: ["arm64"],
            capabilities: RuntimeCapabilities(
                desktopWindows: true,
                terminal: true,
                filesystem: true,
                workbench: false,
                browser: false,
                persistentStorage: true,
                liveKernel: false,
                taskExecution: true
            ),
            availability: availability,
            health: health,
            threadingProfiles: [.singleThreaded, .sharedMemory],
            enforcedQuotas: Set(WorkspaceQuotaKind.allCases)
        ))
    }
}

struct RuntimeCircuitBreaker: Equatable, Sendable {
    var failureThreshold: Int = 3
    var cooldown: TimeInterval = 30
    private(set) var health: RuntimeProviderHealth = .healthy
    private(set) var consecutiveFailures: Int = 0
    private(set) var openedAt: Date?

    mutating func recordSuccess() {
        health = .healthy
        consecutiveFailures = 0
        openedAt = nil
    }

    mutating func recordFailure(now: Date = Date()) {
        consecutiveFailures += 1
        if health == .halfOpen || consecutiveFailures >= failureThreshold {
            health = .open
            openedAt = now
        } else {
            health = .degraded
        }
    }

    mutating func probeAllowed(now: Date = Date()) -> Bool {
        switch health {
        case .healthy, .degraded:
            return true
        case .open:
            guard let openedAt, now.timeIntervalSince(openedAt) >= cooldown else {
                return false
            }
            health = .halfOpen
            return true
        case .halfOpen:
            return false
        }
    }
}
