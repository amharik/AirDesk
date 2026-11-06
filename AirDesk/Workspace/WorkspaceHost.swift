import Foundation

enum WorkspaceHostState: Equatable, Sendable {
    case active
    case degraded(reason: String)
    case handoffPending(targetDeviceId: String)
    case handedOff

    var isActive: Bool {
        self == .active
    }
}

enum WorkspaceHandoffPhase: String, Equatable, Sendable {
    case quiesced
    case staged
    case activated
    case retired
}

struct WorkspaceHandoffSession: Equatable, Sendable {
    let workspaceId: String
    let sourceDeviceId: String
    let targetDeviceId: String
    let baseWorkspaceSeq: UInt64
    let sourceHostEpoch: UInt64
    let checkpointSeq: UInt64
    let journalSequence: UInt64
    var targetHostEpoch: UInt64?
    var phase: WorkspaceHandoffPhase
}

final class WorkspaceHost {
    let deviceId: String

    private let store: WorkspaceStore
    private let now: () -> Date
    private let lock = NSLock()
    private var cachedManifest: WorkspaceManifest?
    private var authorityEpoch: UInt64?
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
        self.authorityEpoch = cachedManifest?.recovery.hostEpoch
    }

    var state: WorkspaceHostState {
        lock.lock()
        defer { lock.unlock() }
        if let latest = try? store.load() {
            cachedManifest = latest
            if authorityEpoch == nil {
                authorityEpoch = latest.recovery.hostEpoch
            }
            refreshAuthorityUnlocked()
        }
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
        try requireActiveHost()

        var manifest = WorkspaceManifest.create(id: id, name: name, owner: owner, now: now())
        manifest.metadata.lastActiveDeviceId = deviceId
        manifest.recovery.hostEpoch = 1

        do {
            let committed = try store.commit(manifest, expectedRevision: nil)
            cachedManifest = committed
            authorityEpoch = committed.recovery.hostEpoch
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
        try requireActiveHost()
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

    func quiesceForHandoff(targetDeviceId: String) throws -> WorkspaceHandoffSession {
        lock.lock()
        defer { lock.unlock() }

        guard !targetDeviceId.isEmpty else { throw WorkspaceHostError.invalidHandoffTarget }
        guard targetDeviceId != deviceId else { throw WorkspaceHostError.invalidHandoffTarget }
        try requireActiveHost()
        guard let current = try reloadUnlocked() else {
            throw WorkspaceHostError.workspaceMissing
        }
        try requireActiveHost()

        currentState = .handoffPending(targetDeviceId: targetDeviceId)
        return WorkspaceHandoffSession(
            workspaceId: current.id,
            sourceDeviceId: deviceId,
            targetDeviceId: targetDeviceId,
            baseWorkspaceSeq: current.workspaceSeq,
            sourceHostEpoch: current.recovery.hostEpoch,
            checkpointSeq: current.recovery.checkpointSeq,
            journalSequence: current.recovery.journalSequence,
            targetHostEpoch: nil,
            phase: .quiesced
        )
    }

    func stageHandoff(_ session: WorkspaceHandoffSession) throws -> WorkspaceHandoffSession {
        lock.lock()
        defer { lock.unlock() }

        try requireHandoffSourceLocked(session)
        guard let current = try reloadUnlocked() else {
            throw WorkspaceHostError.workspaceMissing
        }
        try requireHandoffSourceLocked(session)
        try verifyHandoffSnapshotLocked(session, manifest: current)

        guard session.phase == .quiesced || session.phase == .staged else {
            throw WorkspaceHostError.handoffNotQuiesced
        }
        var staged = session
        staged.phase = .staged
        return staged
    }

    func activateHandoff(
        _ session: WorkspaceHandoffSession,
        force: Bool = false
    ) throws -> WorkspaceHandoffSession {
        lock.lock()
        defer { lock.unlock() }

        guard session.targetDeviceId == deviceId else {
            throw WorkspaceHostError.handoffTargetMismatch(
                expected: session.targetDeviceId,
                actual: deviceId
            )
        }
        if !force && session.phase != .staged {
            throw WorkspaceHostError.handoffNotStaged
        }
        guard let current = try reloadUnlocked() else {
            throw WorkspaceHostError.workspaceMissing
        }
        guard current.id == session.workspaceId else {
            throw WorkspaceHostError.handoffWorkspaceMismatch
        }
        if !force {
            guard current.workspaceSeq == session.baseWorkspaceSeq else {
                throw WorkspaceHostError.staleHandoff(
                    workspaceSeq: session.baseWorkspaceSeq,
                    hostEpoch: current.recovery.hostEpoch
                )
            }
            try verifyHandoffSnapshotLocked(session, manifest: current)
        }

        var next = current
        next.workspaceSeq = current.workspaceSeq + 1
        next.revision = current.revision
        next.metadata.updatedAt = now()
        next.metadata.lastActiveDeviceId = deviceId
        next.recovery.hostEpoch = max(
            current.recovery.hostEpoch,
            session.sourceHostEpoch
        ) + 1
        next.recovery.journalSequence = current.recovery.journalSequence
        next.recovery.checkpointSeq = current.recovery.checkpointSeq
        next.recovery.lastCheckpointId = current.recovery.lastCheckpointId
        next.recovery.integrityHash = nil

        do {
            try next.validate()
            let committed = try store.commit(next, expectedRevision: current.revision)
            cachedManifest = committed
            authorityEpoch = committed.recovery.hostEpoch
            currentState = .active
            var activated = session
            activated.targetHostEpoch = committed.recovery.hostEpoch
            activated.phase = .activated
            return activated
        } catch let error as WorkspaceStoreError {
            throw WorkspaceHostError.store(error)
        }
    }

    func retireAfterHandoff(_ session: WorkspaceHandoffSession) throws -> WorkspaceHandoffSession {
        lock.lock()
        defer { lock.unlock() }

        guard let current = try reloadUnlocked() else {
            throw WorkspaceHostError.workspaceMissing
        }
        guard current.id == session.workspaceId else {
            throw WorkspaceHostError.handoffWorkspaceMismatch
        }
        let expectedTargetEpoch = session.targetHostEpoch
        guard current.recovery.hostEpoch > session.sourceHostEpoch,
              expectedTargetEpoch == nil || current.recovery.hostEpoch == expectedTargetEpoch else {
            throw WorkspaceHostError.handoffNotActivated(
                currentHostEpoch: current.recovery.hostEpoch
            )
        }

        currentState = .handedOff
        var retired = session
        retired.targetHostEpoch = current.recovery.hostEpoch
        retired.phase = .retired
        return retired
    }

    private func requireHandoffSourceLocked(_ session: WorkspaceHandoffSession) throws {
        guard session.sourceDeviceId == deviceId else {
            throw WorkspaceHostError.handoffSourceMismatch(
                expected: session.sourceDeviceId,
                actual: deviceId
            )
        }
        guard currentState == .handoffPending(targetDeviceId: session.targetDeviceId) else {
            throw WorkspaceHostError.handoffNotQuiesced
        }
    }

    private func verifyHandoffSnapshotLocked(
        _ session: WorkspaceHandoffSession,
        manifest: WorkspaceManifest
    ) throws {
        guard manifest.id == session.workspaceId,
              manifest.workspaceSeq == session.baseWorkspaceSeq,
              manifest.recovery.hostEpoch == session.sourceHostEpoch,
              manifest.recovery.checkpointSeq == session.checkpointSeq,
              manifest.recovery.journalSequence == session.journalSequence else {
            throw WorkspaceHostError.staleHandoff(
                workspaceSeq: manifest.workspaceSeq,
                hostEpoch: manifest.recovery.hostEpoch
            )
        }
    }

    private func reloadUnlocked() throws -> WorkspaceManifest? {
        do {
            let manifest = try store.load()
            cachedManifest = manifest
            if let manifest, authorityEpoch == nil {
                authorityEpoch = manifest.recovery.hostEpoch
            }
            refreshAuthorityUnlocked()
            return manifest
        } catch let error as WorkspaceStoreError {
            throw WorkspaceHostError.store(error)
        }
    }

    private func refreshAuthorityUnlocked() {
        guard let manifest = cachedManifest, let authorityEpoch else { return }
        if manifest.recovery.hostEpoch > authorityEpoch {
            currentState = .handedOff
        }
    }

    private func requireActiveHost() throws {
        switch currentState {
        case .active:
            return
        case .degraded(let reason):
            throw WorkspaceHostError.hostUnavailable(reason: reason)
        case .handoffPending:
            throw WorkspaceHostError.hostUnavailable(reason: "handoff in progress")
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
    case invalidHandoffTarget
    case handoffSourceMismatch(expected: String, actual: String)
    case handoffTargetMismatch(expected: String, actual: String)
    case handoffWorkspaceMismatch
    case handoffNotQuiesced
    case handoffNotStaged
    case staleHandoff(workspaceSeq: UInt64, hostEpoch: UInt64)
    case handoffNotActivated(currentHostEpoch: UInt64)
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
        case .invalidHandoffTarget:
            return "A handoff target must be a different, non-empty device identifier."
        case .handoffSourceMismatch(let expected, let actual):
            return "Handoff source mismatch: expected \(expected), actual \(actual)."
        case .handoffTargetMismatch(let expected, let actual):
            return "Handoff target mismatch: expected \(expected), actual \(actual)."
        case .handoffWorkspaceMismatch:
            return "The handoff session belongs to a different workspace."
        case .handoffNotQuiesced:
            return "The workspace host must be quiesced for this handoff."
        case .handoffNotStaged:
            return "The handoff must be staged before activation."
        case .staleHandoff(let workspaceSeq, let hostEpoch):
            return "Stale handoff snapshot at workspace sequence \(workspaceSeq), host epoch \(hostEpoch)."
        case .handoffNotActivated(let currentHostEpoch):
            return "The target has not activated this handoff (current host epoch \(currentHostEpoch))."
        case .store(let error):
            return error.localizedDescription
        }
    }
}
