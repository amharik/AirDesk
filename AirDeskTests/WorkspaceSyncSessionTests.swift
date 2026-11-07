import CryptoKit
import XCTest
@testable import AirDesk

@MainActor
final class WorkspaceSyncSessionTests: XCTestCase {
    private let keyBase64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="

    func testQueuesPersistsAndFlushesPendingEnvelopes() throws {
        let session = try makeSession(senderDeviceId: "dev-a")
        try session.enqueue(plaintext: Data("first".utf8))
        try session.enqueue(plaintext: Data("second".utf8))

        var sent: [Data] = []
        let flushed = try session.flush { data in
            sent.append(data)
            return sent.count == 1
        }

        XCTAssertEqual(flushed, 1)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(session.pendingCount, 1)
        XCTAssertEqual(session.state.nextOutboundSeq, 3)

        let url = temporaryURL()
        try session.persist(to: url)
        let restoredState = try WorkspaceSyncStateStore.load(from: url)
        XCTAssertEqual(restoredState, session.state)
        XCTAssertEqual(restoredState.pending.count, 1)
        XCTAssertEqual(restoredState.nextOutboundSeq, 3)

        let restored = try WorkspaceSyncSession(
            key: WorkspaceSyncCrypto.importKey(try decode(keyBase64)),
            workspaceId: "ws-1",
            senderDeviceId: "dev-a",
            hostEpoch: 2,
            state: restoredState
        )
        XCTAssertEqual(restored.pendingCount, 1)
        XCTAssertEqual(try restored.flush { _ in true }, 1)
        XCTAssertEqual(restored.pendingCount, 0)
    }

    func testReceivesPayloadsAndRejectsReplayPerSender() throws {
        let sender = try makeSession(senderDeviceId: "dev-a")
        let receiver = try makeSession(senderDeviceId: "host")
        let envelope = try sender.enqueue(plaintext: Data("patch".utf8))
        let encoded = try JSONEncoder().encode(envelope)

        let received = try receiver.receive(encoded)
        XCTAssertEqual(String(decoding: received.plaintext, as: UTF8.self), "patch")
        XCTAssertEqual(receiver.state.lastReceivedSeqBySender, ["dev-a": 1])

        XCTAssertThrowsError(try receiver.receive(encoded)) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "StaleSequence")
        }

        let otherSender = try makeSession(senderDeviceId: "dev-b")
        let otherEnvelope = try otherSender.enqueue(plaintext: Data("other".utf8))
        XCTAssertNoThrow(try receiver.receive(try JSONEncoder().encode(otherEnvelope)))
        XCTAssertEqual(receiver.state.lastReceivedSeqBySender, ["dev-a": 1, "dev-b": 1])
    }

    func testDecodeDoesNotAdvanceReplayStateUntilAccepted() throws {
        let sender = try makeSession(senderDeviceId: "dev-a")
        let receiver = try makeSession(senderDeviceId: "host")
        let envelope = try sender.enqueue(plaintext: Data("patch".utf8))
        let encoded = try JSONEncoder().encode(envelope)

        let decoded = try receiver.decode(encoded)
        XCTAssertEqual(String(decoding: decoded.plaintext, as: UTF8.self), "patch")
        XCTAssertNil(receiver.state.lastReceivedSeqBySender["dev-a"])

        try receiver.accept(decoded.envelope)
        XCTAssertEqual(receiver.state.lastReceivedSeqBySender["dev-a"], 1)
        XCTAssertThrowsError(try receiver.accept(decoded.envelope)) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "StaleSequence")
        }
    }

    func testRejectsRevokedSenderAndCorruptOutbox() throws {
        let sender = try makeSession(senderDeviceId: "dev-a")
        let receiver = try makeSession(senderDeviceId: "host")
        receiver.revokeSender("dev-a")
        let envelope = try sender.enqueue(plaintext: Data("patch".utf8))

        XCTAssertThrowsError(try receiver.receive(try JSONEncoder().encode(envelope))) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "SenderRevoked")
        }

        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: url)
        XCTAssertThrowsError(try WorkspaceSyncStateStore.load(from: url)) {
            XCTAssertEqual($0 as? WorkspaceSyncStateError, .corrupt)
        }
    }

    func testEnvelopeRoundTripsOverExistingIrohConnection() async throws {
        let hostPeer = IrohFabricPeer(identitySeed: Data(repeating: 0x55, count: 32))
        let controllerPeer = IrohFabricPeer(identitySeed: Data(repeating: 0x66, count: 32))
        defer {
            Task { @MainActor in
                await hostPeer.stop()
                await controllerPeer.stop()
            }
        }

        let key = try WorkspaceSyncCrypto.importKey(try decode(keyBase64))
        let hostSession = WorkspaceSyncSession(
            key: key,
            workspaceId: "ws-1",
            senderDeviceId: "host",
            hostEpoch: 2
        )
        let controllerSession = WorkspaceSyncSession(
            key: key,
            workspaceId: "ws-1",
            senderDeviceId: "controller",
            hostEpoch: 2
        )

        let connected = expectation(description: "connected")
        let receivedByHost = expectation(description: "host received sync")
        let receivedByController = expectation(description: "controller received sync")
        hostPeer.onPeerConnected = { _ in connected.fulfill() }
        hostPeer.onSyncEnvelope = { data in
            do {
                let result = try hostSession.receive(data)
                if String(decoding: result.plaintext, as: UTF8.self) == "from-controller" {
                    receivedByHost.fulfill()
                }
            } catch {
                XCTFail("Host failed to receive sync envelope: \(error)")
            }
        }
        controllerPeer.onSyncEnvelope = { data in
            do {
                let result = try controllerSession.receive(data)
                if String(decoding: result.plaintext, as: UTF8.self) == "from-host" {
                    receivedByController.fulfill()
                }
            } catch {
                XCTFail("Controller failed to receive sync envelope: \(error)")
            }
        }

        await hostPeer.start(relayPolicy: .directOnly)
        await controllerPeer.start(relayPolicy: .directOnly)
        try await controllerPeer.connect(to: hostPeer.ticket)
        await fulfillment(of: [connected], timeout: 10)

        try controllerSession.enqueue(plaintext: Data("from-controller".utf8))
        XCTAssertEqual(try controllerSession.flush { controllerPeer.sendSync($0) }, 1)
        await fulfillment(of: [receivedByHost], timeout: 5)

        try hostSession.enqueue(plaintext: Data("from-host".utf8))
        XCTAssertEqual(try hostSession.flush { hostPeer.sendSync($0) }, 1)
        await fulfillment(of: [receivedByController], timeout: 5)
    }

    private func makeSession(senderDeviceId: String) throws -> WorkspaceSyncSession {
        try WorkspaceSyncSession(
            key: WorkspaceSyncCrypto.importKey(try decode(keyBase64)),
            workspaceId: "ws-1",
            senderDeviceId: senderDeviceId,
            hostEpoch: 2
        )
    }

    private func decode(_ value: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: value))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("airdesk-sync-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
    }
}
