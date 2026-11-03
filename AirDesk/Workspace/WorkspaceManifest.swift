import Foundation

struct WorkspaceManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: String
    var revision: UInt64
    var workspaceSeq: UInt64
    var owner: WorkspaceOwner
    var metadata: WorkspaceMetadata
    var layout: WorkspaceLayout
    var applications: [WorkspaceApplication]
    var instances: [WorkspaceApplicationInstance]
    var executionBindings: [WorkspaceExecutionBinding]
    var resources: [WorkspaceResourceReference]
    var preferences: WorkspacePreferences
    var mergeMetadata: WorkspaceMergeMetadata
    var recovery: WorkspaceRecovery

    var hostEpoch: UInt64 {
        get { recovery.hostEpoch }
        set { recovery.hostEpoch = newValue }
    }

    init(
        schemaVersion: Int = WorkspaceManifest.currentSchemaVersion,
        id: String,
        revision: UInt64 = 1,
        workspaceSeq: UInt64 = 0,
        owner: WorkspaceOwner,
        metadata: WorkspaceMetadata,
        layout: WorkspaceLayout = WorkspaceLayout(),
        applications: [WorkspaceApplication] = [],
        instances: [WorkspaceApplicationInstance] = [],
        executionBindings: [WorkspaceExecutionBinding] = [],
        resources: [WorkspaceResourceReference] = [],
        preferences: WorkspacePreferences = WorkspacePreferences(),
        mergeMetadata: WorkspaceMergeMetadata = .default,
        recovery: WorkspaceRecovery = WorkspaceRecovery()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.workspaceSeq = workspaceSeq
        self.owner = owner
        self.metadata = metadata
        self.layout = layout
        self.applications = applications
        self.instances = instances
        self.executionBindings = executionBindings
        self.resources = resources
        self.preferences = preferences
        self.mergeMetadata = mergeMetadata
        self.recovery = recovery
    }

    static func create(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        owner: WorkspaceOwner,
        now: Date = Date()
    ) -> WorkspaceManifest {
        WorkspaceManifest(
            id: id,
            owner: owner,
            metadata: WorkspaceMetadata(
                name: name,
                createdAt: now,
                updatedAt: now,
                lastActiveDeviceId: nil
            )
        )
    }
}

struct WorkspaceOwner: Codable, Equatable, Sendable {
    var identityId: String
    var displayName: String
}

struct WorkspaceMetadata: Codable, Equatable, Sendable {
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var lastActiveDeviceId: String?
}

struct WorkspaceLayout: Codable, Equatable, Sendable {
    var displays: [WorkspaceDisplay]
    var windows: [WorkspaceWindow]
    var focusOrder: [String]
    var activeWindowId: String?

    init(
        displays: [WorkspaceDisplay] = [],
        windows: [WorkspaceWindow] = [],
        focusOrder: [String] = [],
        activeWindowId: String? = nil
    ) {
        self.displays = displays
        self.windows = windows
        self.focusOrder = focusOrder
        self.activeWindowId = activeWindowId
    }
}

struct WorkspaceDisplay: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var bounds: WorkspaceRect
    var isPrimary: Bool
}

struct WorkspaceWindow: Codable, Equatable, Sendable {
    var id: String
    var instanceId: String
    var displayId: String
    var bounds: WorkspaceRect
    var isMinimized: Bool
    var surface: String
}

struct WorkspaceRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isFinite: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
    }

    var hasNonNegativeSize: Bool {
        width >= 0 && height >= 0
    }
}

struct WorkspaceApplication: Codable, Equatable, Sendable {
    var id: String
    var version: String
    var name: String
    var entrypoint: String
    var runtimeTargets: [WorkspaceRuntimeTarget]
    var requiredCapabilities: [String]
    var presentation: WorkspacePresentation
    var permissions: [String]
    var quotas: WorkspaceQuotas?
}

struct WorkspaceRuntimeTarget: Codable, Equatable, Sendable {
    var provider: String
    var world: String
    var architectures: [String]
}

struct WorkspaceQuotas: Codable, Equatable, Sendable {
    var workers: Int?
    var memoryBytes: UInt64?
    var cpuMillis: UInt64?
    var handles: Int?
    var persistedBytes: UInt64?
}

enum WorkspacePresentation: String, Codable, CaseIterable, Sendable {
    case foreground
    case background
}

struct WorkspaceApplicationInstance: Codable, Equatable, Sendable {
    var id: String
    var applicationId: String
    var desiredState: WorkspaceDesiredState
    var placement: WorkspacePlacement?
    var configuration: [String: String]
}

enum WorkspaceDesiredState: String, Codable, CaseIterable, Sendable {
    case running
    case stopped
    case suspended
}

struct WorkspacePlacement: Codable, Equatable, Sendable {
    var deviceId: String?
    var providerId: String?
}

struct WorkspaceExecutionBinding: Codable, Equatable, Sendable {
    var instanceId: String
    var preferredProviderId: String
    var fallbackPolicy: WorkspaceFallbackPolicy
    var pinnedWorld: String?

    init(
        instanceId: String,
        preferredProviderId: String,
        fallbackPolicy: WorkspaceFallbackPolicy,
        pinnedWorld: String? = nil
    ) {
        self.instanceId = instanceId
        self.preferredProviderId = preferredProviderId
        self.fallbackPolicy = fallbackPolicy
        self.pinnedWorld = pinnedWorld
    }
}

enum WorkspaceFallbackPolicy: String, Codable, CaseIterable, Sendable {
    case deny
    case localOnly = "local-only"
    case allowRemote = "allow-remote"
}

struct WorkspaceResourceReference: Codable, Equatable, Sendable {
    var id: String
    var kind: WorkspaceResourceKind
    var providerId: String
    var resourceId: String
    var accessPolicy: WorkspaceResourceAccessPolicy
    var persistence: WorkspaceResourcePersistence
}

enum WorkspaceResourceKind: String, Codable, CaseIterable, Sendable {
    case file
    case document
    case database
    case applicationData = "application-data"
    case runtimeVolume = "runtime-volume"
}

enum WorkspaceResourceAccessPolicy: String, Codable, CaseIterable, Sendable {
    case owner
    case workspace
    case readOnly = "read-only"
}

enum WorkspaceResourcePersistence: String, Codable, CaseIterable, Sendable {
    case durable
    case evictable
    case unknown
}

struct WorkspacePreferences: Codable, Equatable, Sendable {
    var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }
}

struct WorkspaceMergeMetadata: Codable, Equatable, Sendable {
    var fields: [WorkspaceFieldMetadata]

    init(fields: [WorkspaceFieldMetadata] = []) {
        self.fields = fields
    }

    static let `default` = WorkspaceMergeMetadata(fields: [
        WorkspaceFieldMetadata(path: "metadata.name", merge: .lww, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "metadata.updatedAt", merge: .lww, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "metadata.lastActiveDeviceId", merge: .lww, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "layout.displays", merge: .lww, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "layout.windows", merge: .lww, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "layout.focusOrder", merge: .lww, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "layout.activeWindowId", merge: .lww, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "preferences", merge: .lww, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "applications", merge: .manual, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "instances", merge: .manual, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "executionBindings", merge: .manual, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "resources", merge: .manual, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "owner", merge: .manual, sinceSchemaVersion: 1),
        WorkspaceFieldMetadata(path: "recovery", merge: .manual, sinceSchemaVersion: 1)
    ])

    func mergeClass(for path: String) -> WorkspaceMergeClass {
        let match = fields
            .filter { path == $0.path || path.hasPrefix($0.path + ".") }
            .max { $0.path.count < $1.path.count }
        return match?.merge ?? .manual
    }
}

struct WorkspaceFieldMetadata: Codable, Equatable, Sendable {
    var path: String
    var merge: WorkspaceMergeClass
    var sinceSchemaVersion: Int
}

enum WorkspaceMergeClass: String, Codable, CaseIterable, Sendable {
    case lww
    case appendLog = "append-log"
    case manual
}

struct WorkspaceRecovery: Codable, Equatable, Sendable {
    var journalSequence: UInt64
    var checkpointSeq: UInt64
    var hostEpoch: UInt64
    var lastCheckpointId: String?
    var integrityHash: String?

    init(
        journalSequence: UInt64 = 0,
        checkpointSeq: UInt64 = 0,
        hostEpoch: UInt64 = 1,
        lastCheckpointId: String? = nil,
        integrityHash: String? = nil
    ) {
        self.journalSequence = journalSequence
        self.checkpointSeq = checkpointSeq
        self.hostEpoch = hostEpoch
        self.lastCheckpointId = lastCheckpointId
        self.integrityHash = integrityHash
    }
}

enum WorkspaceManifestError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case duplicateIdentifier(kind: String, id: String)
    case missingApplication(instanceId: String, applicationId: String)
    case missingInstance(owner: String, instanceId: String)
    case missingInstanceForWindow(windowId: String, instanceId: String)
    case missingWindowReference(owner: String, windowId: String)
    case missingDisplay(windowId: String, displayId: String)
    case duplicateMergePath(String)
    case invalidMergeVersion(path: String, version: Int)
    case invalidLayout(String)
    case invalidRevision
    case invalidHostEpoch

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported workspace schema version \(version)."
        case .emptyField(let field):
            return "Workspace field \(field) must not be empty."
        case .duplicateIdentifier(let kind, let id):
            return "Duplicate \(kind) identifier \(id)."
        case .missingApplication(let instanceId, let applicationId):
            return "Instance \(instanceId) references missing application \(applicationId)."
        case .missingInstance(let owner, let instanceId):
            return "\(owner) references missing instance \(instanceId)."
        case .missingInstanceForWindow(let windowId, let instanceId):
            return "Window \(windowId) references missing instance \(instanceId)."
        case .missingWindowReference(let owner, let windowId):
            return "\(owner) references missing window \(windowId)."
        case .missingDisplay(let windowId, let displayId):
            return "Window \(windowId) references missing display \(displayId)."
        case .duplicateMergePath(let path):
            return "Duplicate merge metadata for \(path)."
        case .invalidMergeVersion(let path, let version):
            return "Merge metadata for \(path) targets unsupported schema version \(version)."
        case .invalidLayout(let detail):
            return "Invalid workspace layout: \(detail)."
        case .invalidRevision:
            return "Workspace revision must be at least 1."
        case .invalidHostEpoch:
            return "Workspace host epoch must be at least 1."
        }
    }
}

extension WorkspaceManifest {
    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw WorkspaceManifestError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.requireNonEmpty(id, field: "id")
        try Self.requireNonEmpty(owner.identityId, field: "owner.identityId")
        try Self.requireNonEmpty(owner.displayName, field: "owner.displayName")
        try Self.requireNonEmpty(metadata.name, field: "metadata.name")

        guard revision >= 1 else { throw WorkspaceManifestError.invalidRevision }
        guard recovery.hostEpoch >= 1 else { throw WorkspaceManifestError.invalidHostEpoch }

        try Self.requireUnique(applications.map(\.id), kind: "application")
        try Self.requireUnique(instances.map(\.id), kind: "instance")
        try Self.requireUnique(executionBindings.map(\.instanceId), kind: "binding")
        try Self.requireUnique(resources.map(\.id), kind: "resource")
        try Self.requireUnique(layout.displays.map(\.id), kind: "display")
        try Self.requireUnique(layout.windows.map(\.id), kind: "window")
        try Self.requireUnique(layout.focusOrder, kind: "focus entry")

        let applicationIds = Set(applications.map(\.id))
        let instanceIds = Set(instances.map(\.id))
        let displayIds = Set(layout.displays.map(\.id))
        let windowIds = Set(layout.windows.map(\.id))

        for application in applications {
            try Self.requireNonEmpty(application.version, field: "applications.\(application.id).version")
            try Self.requireNonEmpty(application.name, field: "applications.\(application.id).name")
            try Self.requireNonEmpty(application.entrypoint, field: "applications.\(application.id).entrypoint")
            try Self.requireUnique(application.runtimeTargets.map { "\($0.provider)|\($0.world)" }, kind: "runtime target")
            for target in application.runtimeTargets {
                try Self.requireNonEmpty(target.provider, field: "applications.\(application.id).runtimeTargets.provider")
                try Self.requireNonEmpty(target.world, field: "applications.\(application.id).runtimeTargets.world")
            }
        }

        for instance in instances {
            guard applicationIds.contains(instance.applicationId) else {
                throw WorkspaceManifestError.missingApplication(
                    instanceId: instance.id,
                    applicationId: instance.applicationId
                )
            }
        }

        for binding in executionBindings {
            guard instanceIds.contains(binding.instanceId) else {
                throw WorkspaceManifestError.missingInstance(
                    owner: "executionBindings",
                    instanceId: binding.instanceId
                )
            }
            try Self.requireNonEmpty(
                binding.preferredProviderId,
                field: "executionBindings.\(binding.instanceId).preferredProviderId"
            )
            if let pinnedWorld = binding.pinnedWorld {
                try Self.requireNonEmpty(
                    pinnedWorld,
                    field: "executionBindings.\(binding.instanceId).pinnedWorld"
                )
            }
        }

        for resource in resources {
            try Self.requireNonEmpty(resource.providerId, field: "resources.\(resource.id).providerId")
            try Self.requireNonEmpty(resource.resourceId, field: "resources.\(resource.id).resourceId")
        }

        for display in layout.displays {
            try Self.requireNonEmpty(display.name, field: "layout.displays.\(display.id).name")
            try Self.requireValidRect(display.bounds, context: "layout.displays.\(display.id).bounds")
        }

        for window in layout.windows {
            guard instanceIds.contains(window.instanceId) else {
                throw WorkspaceManifestError.missingInstanceForWindow(
                    windowId: window.id,
                    instanceId: window.instanceId
                )
            }
            if !window.displayId.isEmpty {
                guard displayIds.contains(window.displayId) else {
                    throw WorkspaceManifestError.missingDisplay(
                        windowId: window.id,
                        displayId: window.displayId
                    )
                }
            }
            try Self.requireNonEmpty(window.surface, field: "layout.windows.\(window.id).surface")
            try Self.requireValidRect(window.bounds, context: "layout.windows.\(window.id).bounds")
        }

        for windowId in layout.focusOrder {
            guard windowIds.contains(windowId) else {
                throw WorkspaceManifestError.missingWindowReference(
                    owner: "layout.focusOrder",
                    windowId: windowId
                )
            }
        }

        if let activeWindowId = layout.activeWindowId {
            guard windowIds.contains(activeWindowId) else {
                throw WorkspaceManifestError.missingWindowReference(
                    owner: "layout.activeWindowId",
                    windowId: activeWindowId
                )
            }
        }

        var mergePaths = Set<String>()
        for field in mergeMetadata.fields {
            try Self.requireNonEmpty(field.path, field: "mergeMetadata.path")
            guard mergePaths.insert(field.path).inserted else {
                throw WorkspaceManifestError.duplicateMergePath(field.path)
            }
            guard field.sinceSchemaVersion >= 1,
                  field.sinceSchemaVersion <= Self.currentSchemaVersion else {
                throw WorkspaceManifestError.invalidMergeVersion(
                    path: field.path,
                    version: field.sinceSchemaVersion
                )
            }
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceManifestError.emptyField(field)
        }
    }

    private static func requireUnique(_ values: [String], kind: String) throws {
        var seen = Set<String>()
        for value in values {
            try requireNonEmpty(value, field: "\(kind).id")
            guard seen.insert(value).inserted else {
                throw WorkspaceManifestError.duplicateIdentifier(kind: kind, id: value)
            }
        }
    }

    private static func requireValidRect(_ rect: WorkspaceRect, context: String) throws {
        guard rect.isFinite, rect.hasNonNegativeSize else {
            throw WorkspaceManifestError.invalidLayout(context)
        }
    }
}
