import XCTest
@testable import AirDesk

final class IrohFabricInputCodecTests: XCTestCase {
    func testPointerMoveUsesMovementDatagram() throws {
        let event = InputEvent.make(
            .pointerMove,
            sessionId: "ads-codec",
            generation: 7,
            seq: 42,
            x: 0.25,
            y: 0.75
        )

        let packet = try IrohFabricInputCodec.encode(event)
        XCTAssertEqual(packet.channel, .movement)
        XCTAssertEqual(packet.payload.count, PackedMovementFrame.byteCount)

        let frame = try PackedMovementFrame.decode(packet.payload)
        XCTAssertEqual(frame.leaseEpochLow, 7)
        XCTAssertEqual(frame.seq, 42)
        XCTAssertEqual(frame.x, 0.25)
        XCTAssertEqual(frame.y, 0.75)

        let decoded = try IrohFabricInputCodec.decodeMovement(
            .movement(packet.payload),
            sessionId: "ads-host",
            generation: 3
        )
        XCTAssertEqual(decoded?.type, .pointerMove)
        XCTAssertEqual(decoded?.sessionId, "ads-host")
        XCTAssertEqual(decoded?.generation, 3)
        XCTAssertEqual(decoded?.seq, 42)
    }

    func testReliableEdgesRoundTrip() throws {
        let event = InputEvent.make(
            .keyDown,
            sessionId: "ads-codec",
            generation: 2,
            seq: 9,
            key: "a",
            code: "KeyA",
            modifiers: [InputModifier.shift.rawValue]
        )

        let packet = try IrohFabricInputCodec.encode(event)
        XCTAssertEqual(packet.channel, .inputEdges)

        let decoded = try IrohFabricInputCodec.decodeReliable(
            .reliable(channel: .inputEdges, payload: packet.payload)
        )
        XCTAssertEqual(decoded, event)
    }

    func testControlEventsUseControlChannel() throws {
        let event = InputEvent.make(
            .viewportChanged,
            sessionId: "ads-codec",
            generation: 1,
            seq: 10,
            width: 1920,
            height: 1080
        )

        let packet = try IrohFabricInputCodec.encode(event)
        XCTAssertEqual(packet.channel, .control)
        XCTAssertEqual(
            try IrohFabricInputCodec.decodeReliable(
                .reliable(channel: .control, payload: packet.payload)
            ),
            event
        )
    }

    func testMovementRejectsMissingCoordinates() {
        let event = InputEvent.make(
            .pointerMove,
            sessionId: "ads-codec",
            generation: 1,
            seq: 1
        )
        XCTAssertThrowsError(try IrohFabricInputCodec.encode(event))
    }

    func testReliableDecoderIgnoresNonInputChannels() throws {
        XCTAssertNil(
            try IrohFabricInputCodec.decodeReliable(
                .reliable(channel: .runtime, payload: Data("runtime".utf8))
            )
        )
        XCTAssertNil(
            try IrohFabricInputCodec.decodeReliable(
                .movement(Data(repeating: 0, count: 16))
            )
        )
    }
}
