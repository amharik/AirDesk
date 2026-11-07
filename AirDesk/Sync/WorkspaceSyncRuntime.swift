import CryptoKit
import Foundation

@MainActor
final class WorkspaceSyncRuntime {
    let controller: WorkspaceSyncController

    private let fabric: IrohFabricPeer
    private let stateURL: URL
    private let fileManager: FileManager
    private(set) var lastError: Error?

    init(
        key: SymmetricKey,
        workspaceId: String,
        senderDeviceId: String,
        hostEpoch: UInt64,
        host: WorkspaceHost,
        fabric: IrohFabricPeer,
        stateURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let state = try WorkspaceSyncStateStore.load(from: stateURL, fileManager: fileManager)
        let session = WorkspaceSyncSession(
            key: key,
            workspaceId: workspaceId,
            senderDeviceId: senderDeviceId,
            hostEpoch: hostEpoch,
            state: state
        )
        self.controller = WorkspaceSyncController(session: session, host: host)
        self.fabric = fabric
        self.stateURL = stateURL
        self.fileManager = fileManager
    }

    var pendingCount: Int { controller.pendingCount }

    @discardableResult
    func publishLocalSnapshot() throws -> WorkspaceSyncEnvelope {
        let envelope = try controller.enqueueCurrentSnapshot()
        try persist()
        lastError = nil
        return envelope
    }

    @discardableResult
    func flushPending() throws -> Int {
        let sent = try controller.flush { fabric.sendSync($0) }
        if sent > 0 {
            try persist()
        }
        lastError = nil
        return sent
    }

    func peerDidConnect() {
        do {
            try flushPending()
        } catch {
            lastError = error
        }
    }

    @discardableResult
    func receive(_ data: Data) throws -> WorkspaceSyncApplyResult {
        let result = try controller.receive(data)
        try persist()
        lastError = nil
        return result
    }

    func handleEnvelope(_ data: Data) {
        do {
            _ = try receive(data)
        } catch {
            lastError = error
        }
    }

    func persist() throws {
        try controller.persist(to: stateURL, fileManager: fileManager)
    }
}
