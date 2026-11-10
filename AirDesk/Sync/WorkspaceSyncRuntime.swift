import CryptoKit
import Foundation

@MainActor
final class WorkspaceSyncRuntime {
    let controller: WorkspaceSyncController

    private let fabric: IrohFabricPeer
    private let stateURL: URL
    private let fileManager: FileManager
    private let keyStore: WorkspaceSyncKeyStoring?
    private(set) var keyGeneration: UInt64
    private(set) var rotationIssuerDeviceId: String?
    private var pendingRotations: [String: Data]
    private(set) var lastError: Error?

    init(
        key: SymmetricKey,
        workspaceId: String,
        senderDeviceId: String,
        hostEpoch: UInt64,
        host: WorkspaceHost,
        fabric: IrohFabricPeer,
        stateURL: URL,
        keyStore: WorkspaceSyncKeyStoring? = nil,
        keyGeneration: UInt64? = nil,
        fileManager: FileManager = .default
    ) throws {
        let state = try WorkspaceSyncStateStore.load(from: stateURL, fileManager: fileManager)
        let storedKeyState = try keyStore?.loadState(workspaceId: workspaceId)
            ?? WorkspaceSyncKeyStoreState()
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
        self.keyStore = keyStore
        self.keyGeneration = max(1, keyGeneration ?? storedKeyState.generation)
        self.rotationIssuerDeviceId = storedKeyState.rotationIssuerDeviceId
        self.pendingRotations = storedKeyState.pendingRotations
    }

    var pendingCount: Int { controller.pendingCount }

    var currentKey: SymmetricKey { controller.session.currentKey }

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

    func revokeSender(_ deviceId: String) throws {
        controller.revokeSender(deviceId)
        try persist()
        lastError = nil
    }

    @discardableResult
    func rotateKey(
        for endpointIds: [String],
        newKey: SymmetricKey? = nil
    ) throws -> WorkspaceSyncKeyRotation {
        guard keyGeneration < UInt64.max else {
            throw WorkspaceSyncKeyRotationError.generationGap
        }
        let rotation = try WorkspaceSyncKeyRotationCrypto.rotate(
            currentKey: controller.session.currentKey,
            workspaceId: controller.session.workspaceId,
            issuerDeviceId: controller.session.senderDeviceId,
            nextGeneration: keyGeneration + 1,
            newKey: newKey
        )
        controller.session.rotate(to: rotation.key)
        keyGeneration = rotation.message.generation
        let encoded = try JSONEncoder().encode(rotation.message)
        for endpointId in Set(endpointIds) where !endpointId.isEmpty {
            pendingRotations[endpointId] = encoded
        }
        try saveKeyState()
        try persist()
        lastError = nil
        return rotation.message
    }

    func pendingRotation(for endpointId: String) -> Data? {
        pendingRotations[endpointId]
    }

    func setRotationIssuerDeviceId(_ deviceId: String?) throws {
        guard rotationIssuerDeviceId != deviceId else { return }
        rotationIssuerDeviceId = deviceId
        try saveKeyState()
        lastError = nil
    }

    func markRotationSent(for endpointId: String) throws {
        guard pendingRotations.removeValue(forKey: endpointId) != nil else { return }
        try saveKeyState()
    }

    @discardableResult
    func acceptRotation(
        _ message: WorkspaceSyncKeyRotation,
        expectedIssuerDeviceId: String
    ) throws -> Bool {
        guard message.generation > keyGeneration else {
            return false
        }
        let accepted = try WorkspaceSyncKeyRotationCrypto.accept(
            message,
            currentKey: controller.session.currentKey,
            workspaceId: controller.session.workspaceId,
            currentGeneration: keyGeneration,
            expectedIssuerDeviceId: expectedIssuerDeviceId
        )
        controller.session.rotate(to: accepted.key)
        keyGeneration = accepted.generation
        pendingRotations.removeAll()
        try saveKeyState()
        try persist()
        lastError = nil
        return true
    }

    @discardableResult
    func acceptKeyGrant(
        _ message: WorkspaceSyncKeyGrant,
        bootstrapKey: SymmetricKey,
        expectedIssuerDeviceId: String
    ) throws -> Bool {
        guard message.generation >= keyGeneration else {
            return false
        }
        let accepted = try WorkspaceSyncKeyGrantCrypto.accept(
            message,
            bootstrapKey: bootstrapKey,
            workspaceId: controller.session.workspaceId,
            expectedIssuerDeviceId: expectedIssuerDeviceId
        )
        controller.session.rotate(to: accepted.key)
        keyGeneration = accepted.generation
        rotationIssuerDeviceId = message.issuerDeviceId
        pendingRotations.removeAll()
        try saveKeyState()
        try persist()
        lastError = nil
        return true
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

    private func saveKeyState() throws {
        guard let keyStore else { return }
        let workspaceId = controller.session.workspaceId
        try keyStore.saveKey(controller.session.currentKey, workspaceId: workspaceId)
        try keyStore.saveState(
            WorkspaceSyncKeyStoreState(
                generation: keyGeneration,
                pendingRotations: pendingRotations,
                rotationIssuerDeviceId: rotationIssuerDeviceId
            ),
            workspaceId: workspaceId
        )
    }
}
