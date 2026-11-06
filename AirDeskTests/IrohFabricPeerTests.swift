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
    }
}
