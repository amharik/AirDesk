import CryptoKit
import Foundation

struct WorkspaceSyncSessionState: Codable, Equatable, Sendable {
    var nextOutboundSeq: UInt64
    var lastReceivedSeqBySender: [String: UInt64]
    var revokedSenderDeviceIds: [String]
    var pending: [WorkspaceSyncEnvelope]

    init(
        nextOutboundSeq: UInt64 = 1,
        lastReceivedSeqBySender: [String: UInt64] = [:],
        revokedSenderDeviceIds: [String] = [],
        pending: [WorkspaceSyncEnvelope] = []
    ) {
        self.nextOutboundSeq = nextOutboundSeq
        self.lastReceivedSeqBySender = lastReceivedSeqBySender
        self.revokedSenderDeviceIds = revokedSenderDeviceIds
        self.pending = pending
    }
}

enum WorkspaceSyncStateError: Error, Equatable, LocalizedError {
    case corrupt
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .corrupt:
            return "The workspace sync outbox is corrupt."
        case .writeFailed(let detail):
            return "Could not write the workspace sync outbox: \(detail)"
        }
    }
}

enum WorkspaceSyncStateStore {
    static func load(from url: URL, fileManager: FileManager = .default) throws -> WorkspaceSyncSessionState {
        guard fileManager.fileExists(atPath: url.path) else {
            return WorkspaceSyncSessionState()
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(WorkspaceSyncSessionState.self, from: data)
        } catch {
            throw WorkspaceSyncStateError.corrupt
        }
    }

    static func save(
        _ state: WorkspaceSyncSessionState,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
        } catch let error as WorkspaceSyncStateError {
            throw error
        } catch {
            throw WorkspaceSyncStateError.writeFailed(error.localizedDescription)
        }
    }
}

@MainActor
final class WorkspaceSyncSession {
    let workspaceId: String
    let senderDeviceId: String

    private let key: SymmetricKey
    private var hostEpoch: UInt64
    private var nextOutboundSeq: UInt64
    private var lastReceivedSeqBySender: [String: UInt64]
    private var revokedSenderDeviceIds: Set<String>
    private var outbox: [WorkspaceSyncEnvelope]
    private let encoder: JSONEncoder

    init(
        key: SymmetricKey,
        workspaceId: String,
        senderDeviceId: String,
        hostEpoch: UInt64,
        state: WorkspaceSyncSessionState = WorkspaceSyncSessionState()
    ) {
        self.key = key
        self.workspaceId = workspaceId
        self.senderDeviceId = senderDeviceId
        self.hostEpoch = hostEpoch
        self.nextOutboundSeq = state.nextOutboundSeq
        self.lastReceivedSeqBySender = state.lastReceivedSeqBySender
        self.revokedSenderDeviceIds = Set(state.revokedSenderDeviceIds)
        self.outbox = state.pending
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    var state: WorkspaceSyncSessionState {
        WorkspaceSyncSessionState(
            nextOutboundSeq: nextOutboundSeq,
            lastReceivedSeqBySender: lastReceivedSeqBySender,
            revokedSenderDeviceIds: revokedSenderDeviceIds.sorted(),
            pending: outbox
        )
    }

    var pendingCount: Int { outbox.count }

    var pendingEnvelopes: [WorkspaceSyncEnvelope] { outbox }

    func updateHostEpoch(_ hostEpoch: UInt64) {
        self.hostEpoch = hostEpoch
    }

    func revokeSender(_ senderDeviceId: String) {
        revokedSenderDeviceIds.insert(senderDeviceId)
    }

    @discardableResult
    func enqueue(plaintext: Data, aad: Data = Data()) throws -> WorkspaceSyncEnvelope {
        let envelope = try WorkspaceSyncCrypto.encrypt(
            key: key,
            workspaceId: workspaceId,
            senderDeviceId: senderDeviceId,
            hostEpoch: hostEpoch,
            syncSeq: nextOutboundSeq,
            plaintext: plaintext,
            aad: aad
        )
        nextOutboundSeq &+= 1
        outbox.append(envelope)
        return envelope
    }

    @discardableResult
    func flush(send: (Data) -> Bool) throws -> Int {
        var sent = 0
        while let envelope = outbox.first {
            let data: Data
            do {
                data = try encoder.encode(envelope)
            } catch {
                throw WorkspaceSyncEnvelopeError.invalidEnvelope("could not encode the envelope.")
            }
            guard send(data) else { break }
            outbox.removeFirst()
            sent += 1
        }
        return sent
    }

    @discardableResult
    func receive(_ data: Data) throws -> (plaintext: Data, envelope: WorkspaceSyncEnvelope) {
        let envelope: WorkspaceSyncEnvelope
        do {
            envelope = try JSONDecoder().decode(WorkspaceSyncEnvelope.self, from: data)
        } catch {
            throw WorkspaceSyncEnvelopeError.invalidEnvelope("could not decode the envelope.")
        }

        let plaintext = try WorkspaceSyncCrypto.decrypt(
            key: key,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(
                workspaceId: workspaceId,
                hostEpoch: hostEpoch,
                revokedSenderDeviceIds: revokedSenderDeviceIds,
                lastSyncSeq: lastReceivedSeqBySender[envelope.senderDeviceId]
            )
        )
        lastReceivedSeqBySender[envelope.senderDeviceId] = envelope.syncSeq
        return (plaintext, envelope)
    }

    func persist(to url: URL, fileManager: FileManager = .default) throws {
        try WorkspaceSyncStateStore.save(state, to: url, fileManager: fileManager)
    }
}
