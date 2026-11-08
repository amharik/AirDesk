import XCTest
@testable import AirDesk

@MainActor
final class IrohFabricPeerTests: XCTestCase {
    func testPeerForwardsReliableInputAndMovement() async throws {
        let host = IrohFabricPeer(identitySeed: Data(repeating: 0x33, count: 32))
        let controller = IrohFabricPeer(identitySeed: Data(repeating: 0x44, count: 32))
        defer {
            Task { @MainActor in
                await host.stop()
                await controller.stop()
            }
        }

        let connected = expectation(description: "peer connected")
        host.onPeerConnected = { _ in connected.fulfill() }
        let inputReceived = expectation(description: "reliable input")
        let movementReceived = expectation(description: "movement")
        let syncReceived = expectation(description: "sync envelope")
        let pairingReceived = expectation(description: "pairing message")
        host.onInputEvent = { event in
            if event.type == .keyDown, event.key == "a" {
                inputReceived.fulfill()
            }
        }
        host.onMovementFrame = { frame in
            if frame.x == 0.25, frame.y == 0.75 {
                movementReceived.fulfill()
            }
        }
        host.onSyncEnvelope = { payload in
            if payload == Data("sync-envelope".utf8) {
                syncReceived.fulfill()
            }
        }
        host.onPairingMessage = { payload in
            if payload == Data("pairing-message".utf8) {
                pairingReceived.fulfill()
            }
        }

        await host.start(relayPolicy: .directOnly)
        await controller.start(relayPolicy: .directOnly)
        XCTAssertEqual(host.state, .ready)
        XCTAssertEqual(controller.state, .ready)
        XCTAssertFalse(host.ticket.isEmpty)

        try await controller.connect(to: host.ticket)
        await fulfillment(of: [connected], timeout: 10)
        XCTAssertTrue(host.isConnected)
        XCTAssertTrue(controller.isConnected)
        XCTAssertNotNil(host.selectedPath)

        XCTAssertTrue(controller.sendInput(InputEvent.make(
            .keyDown,
            sessionId: "ads-peer",
            generation: 1,
            seq: 1,
            key: "a"
        )))
        await fulfillment(of: [inputReceived], timeout: 5)

        XCTAssertTrue(controller.sendInput(InputEvent.make(
            .pointerMove,
            sessionId: "ads-peer",
            generation: 1,
            seq: 2,
            x: 0.25,
            y: 0.75
        )))
        await fulfillment(of: [movementReceived], timeout: 5)

        XCTAssertTrue(controller.sendSync(Data("sync-envelope".utf8)))
        await fulfillment(of: [syncReceived], timeout: 5)

        XCTAssertTrue(controller.sendPairing(Data("pairing-message".utf8)))
        await fulfillment(of: [pairingReceived], timeout: 5)
    }

    func testPairingRepliesToIncomingPeerWhileAnotherConnectionIsActive() async throws {
        let host = IrohFabricPeer(identitySeed: Data(repeating: 0x55, count: 32))
        let controller = IrohFabricPeer(identitySeed: Data(repeating: 0x66, count: 32))
        let syncPeer = IrohFabricPeer(identitySeed: Data(repeating: 0x77, count: 32))
        defer {
            Task { @MainActor in
                await host.stop()
                await controller.stop()
                await syncPeer.stop()
            }
        }

        await host.start(relayPolicy: .directOnly)
        await controller.start(relayPolicy: .directOnly)
        await syncPeer.start(relayPolicy: .directOnly)

        try await host.connect(to: syncPeer.ticket)

        let incomingConnected = expectation(description: "controller connected to host")
        host.onPeerConnected = { id in
            if id == controller.endpointID {
                incomingConnected.fulfill()
            }
        }
        try await controller.connect(to: host.ticket)
        await fulfillment(of: [incomingConnected], timeout: 10)

        let requestReceived = expectation(description: "host received pairing request")
        let replyReceived = expectation(description: "controller received pairing reply")
        host.onPairingMessage = { payload in
            if payload == Data("pairing-request".utf8) {
                XCTAssertTrue(host.sendPairing(Data("pairing-reply".utf8)))
                requestReceived.fulfill()
            }
        }
        controller.onPairingMessage = { payload in
            if payload == Data("pairing-reply".utf8) {
                replyReceived.fulfill()
            }
        }

        XCTAssertTrue(controller.sendPairing(Data("pairing-request".utf8)))
        await fulfillment(of: [requestReceived, replyReceived], timeout: 5)
    }
}
