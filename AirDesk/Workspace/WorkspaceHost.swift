import Foundation

enum WorkspaceHostState: Equatable, Sendable {
    case active
    case degraded(reason: String)
    case handedOff

    var isActive: Bool {
        self == .active
    }
}

final class WorkspaceHost {
    let deviceId: String

    private let store: WorkspaceStore
    private let now: () -> Date
    private let lock = NSLock()
    private var cachedManifest: WorkspaceManifest?
    private var currentState: WorkspaceHostState

    init(
        store: WorkspaceStore,
        deviceId: String,
        state: WorkspaceHostState = .active,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.store = store
        self.deviceId = deviceId
        self.currentState = state
        self.now = now
        self.cachedManifest = try store.load()
    }

    var state: WorkspaceHostState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    var currentManifest: WorkspaceManifest? {
        lock.lock()
        defer { lock.unlock() }
        return cachedManifest
    }

    var hostEpoch: UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return cachedManifest?.recovery.hostEpoch
    }

    var workspaceSeq: UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return cachedManifest?.workspaceSeq
    }

    func load() throws -> WorkspaceManifest? {
        lock.lock()
        defer { lock.unlock() }
        return try reloadUnlocked()
    }

    @discardableResult
    func create(owner: WorkspaceOwner, name: String, id: String = UUID().uuidString.lowercased()) throws -> WorkspaceManifest {
        lock.lock()
        defer { lock.unlock() }

        try requireActiveHost()
        if let existing = try reloadUnlocked() {
            throw WorkspaceHostError.workspaceAlreadyExists(currentRevision: existing.revision)
        }

        var manifest = WorkspaceManifest.create(id: id, name: name, owner: owner, now: now())
        manifest.metadata.lastActiveDeviceId = deviceId
        manifest.recovery.hostEpoch = 1

        do {
            let committed = try store.commit(manifest, expectedRevision: nil)
            cachedManifest = committed
            return committed
        } catch let error as WorkspaceStoreError {
            throw WorkspaceHostError.store(error)
        }
    }

    @discardableResult
    func mutate(
        expectedWorkspaceSeq: UInt64,
        _ body: (inout WorkspaceManifest) throws -> Void
    ) throws -> WorkspaceManifest {
        lock.lock()
        defer { lock.unlock() }

        try requireActiveHost()
        guard let current = try reloadUnlocked() else {
            throw WorkspaceHostError.workspaceMissing
        }
        guard expectedWorkspaceSeq == current.workspaceSeq else {
            throw WorkspaceHostError.staleWorkspaceSequence(
                expected: expectedWorkspaceSeq,
                current: current.workspaceSeq
            )
        }

        var next = current
        try body(&next)

        guard next.id == current.id else {
            throw WorkspaceHostError.workspaceIdentityChanged
        }
        guard next.recovery.hostEpoch == current.recovery.hostEpoch else {
            throw WorkspaceHostError.hostEpochChangeNotAllowed
        }

        next.workspaceSeq = current.workspaceSeq + 1
        next.revision = current.revision
        next.metadata.updatedAt = now()
        next.recovery.journalSequence = current.recovery.journalSequence
        next.recovery.checkpointSeq = current.recovery.checkpointSeq
        next.recovery.lastCheckpointId = current.recovery.lastCheckpointId
        next.recovery.integrityHash = nil

        do {
            try next.validate()
            let committed = try store.commit(next, expectedRevision: current.revision)
            cachedManifest = committed
            return committed
        } catch let error as WorkspaceStoreError {
            throw WorkspaceHostError.store(error)
        }
    }

    func enterDegradedMode(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        currentState = .degraded(reason: reason)
    }

    func resumeHosting() {
        lock.lock()
        defer { lock.unlock() }
        currentState = .active
    }

    func markHandedOff() {
        lock.lock()
        defer { lock.unlock() }
        currentState = .handedOff
    }

    private func reloadUnlocked() throws -> WorkspaceManifest? {
        do {
            let manifest = try store.load()
            cachedManifest = manifest
            return manifest
        } catch let error as WorkspaceStoreError {
            throw WorkspaceHostError.store(error)
        }
    }

    private func requireActiveHost() throws {
        switch currentState {
        case .active:
            return
        case .degraded(let reason):
            throw WorkspaceHostError.hostUnavailable(reason: reason)
        case .handedOff:
            throw WorkspaceHostError.handedOff
        }
    }
}

enum WorkspaceHostError: Error, Equatable, LocalizedError {
    case hostUnavailable(reason: String)
    case handedOff
    case workspaceMissing
    case workspaceAlreadyExists(currentRevision: UInt64)
    case staleWorkspaceSequence(expected: UInt64, current: UInt64)
    case workspaceIdentityChanged
    case hostEpochChangeNotAllowed
    case store(WorkspaceStoreError)

    var errorDescription: String? {
        switch self {
        case .hostUnavailable(let reason):
            return "The workspace host is unavailable: \(reason)"
        case .handedOff:
            return "This device has handed off workspace authority."
        case .workspaceMissing:
            return "No workspace exists yet."
        case .workspaceAlreadyExists(let revision):
            return "A workspace already exists at revision \(revision)."
        case .staleWorkspaceSequence(let expected, let current):
            return "Stale workspace sequence: expected \(expected), current \(current)."
        case .workspaceIdentityChanged:
            return "Workspace identity cannot be changed by a structural mutation."
        case .hostEpochChangeNotAllowed:
            return "Host epoch changes require a completed handoff."
        case .store(let error):
            return error.localizedDescription
        }
    }
}
