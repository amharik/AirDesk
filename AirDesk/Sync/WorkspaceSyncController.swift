import Foundation

enum WorkspaceSyncControllerError: Error, Equatable, LocalizedError {
    case workspaceMissing
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .workspaceMissing:
            return "No workspace exists to synchronize."
        case .invalidPayload:
            return "The workspace sync payload is invalid."
        }
    }
}

@MainActor
final class WorkspaceSyncController {
    let session: WorkspaceSyncSession

    private let host: WorkspaceHost
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: WorkspaceSyncSession, host: WorkspaceHost) {
        self.session = session
        self.host = host
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    var pendingCount: Int { session.pendingCount }

    func currentSnapshot() throws -> WorkspaceSyncSnapshot {
        guard let manifest = try host.load() else {
            throw WorkspaceSyncControllerError.workspaceMissing
        }
        return try manifest.syncSnapshot()
    }

    @discardableResult
    func enqueueCurrentSnapshot() throws -> WorkspaceSyncEnvelope {
        let snapshot = try currentSnapshot()
        return try session.enqueue(plaintext: try encoder.encode(snapshot))
    }

    @discardableResult
    func flush(send: (Data) -> Bool) throws -> Int {
        try session.flush(send: send)
    }

    func persist(to url: URL, fileManager: FileManager = .default) throws {
        try session.persist(to: url, fileManager: fileManager)
    }

    @discardableResult
    func receive(_ data: Data) throws -> WorkspaceSyncApplyResult {
        let decoded = try session.decode(data)
        guard let manifest = try host.load() else {
            throw WorkspaceSyncControllerError.workspaceMissing
        }
        let remote: WorkspaceSyncSnapshot
        do {
            remote = try decoder.decode(WorkspaceSyncSnapshot.self, from: decoded.plaintext)
        } catch {
            throw WorkspaceSyncControllerError.invalidPayload
        }

        let local = try manifest.syncSnapshot()
        let result = WorkspaceSyncMerge.mergeSnapshots(local: local, remote: remote)

        guard result.status == .applied else {
            if result.status != .rejected {
                try session.accept(decoded.envelope)
            }
            return result
        }

        _ = try host.mutate(expectedWorkspaceSeq: manifest.workspaceSeq) { next in
            let applied = try WorkspaceManifest.applying(result.snapshot, to: next)
            next.metadata = applied.metadata
            next.layout = applied.layout
            next.preferences = applied.preferences
            next.owner = applied.owner
            next.applications = applied.applications
            next.instances = applied.instances
            next.executionBindings = applied.executionBindings
            next.resources = applied.resources
            next.mergeMetadata = applied.mergeMetadata
        }
        try session.accept(decoded.envelope)
        return result
    }
}
