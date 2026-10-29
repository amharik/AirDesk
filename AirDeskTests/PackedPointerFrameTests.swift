import FlatBuffers
import XCTest
@testable import AirDesk

final class PackedPointerFrameTests: XCTestCase {
    private let sessionTag: UInt64 = 1_623_645_925_111_568_461

    func testSessionTagMatchesSharedFixture() throws {
        XCTAssertEqual(try PackedPointerFrame.sessionTag(for: "session-1"), sessionTag)
    }

    func testPointerFixtureDecodes() throws {
        let frame = try PackedPointerFrame.decode(try data(hex: Self.pointerHex))

        XCTAssertEqual(frame.kind, .pointerMove)
        XCTAssertEqual(frame.generation, 7)
        XCTAssertEqual(frame.seq, 42)
        XCTAssertEqual(frame.timestamp, 1_700_000_000_123)
        XCTAssertEqual(frame.sessionTag, sessionTag)
        XCTAssertEqual(frame.x, 0.25)
        XCTAssertEqual(frame.y, 0.75)
        XCTAssertEqual(frame.button, 0)
        XCTAssertEqual(frame.clickCount, 1)
    }

    func testFixturesRoundTripByteForByte() throws {
        for hex in [Self.pointerHex, Self.scrollHex, Self.cancelHex] {
            let encoded = try PackedPointerFrame.decode(try data(hex: hex)).encoded()
            XCTAssertEqual(encoded, try data(hex: hex))
        }
    }

    func testScrollAndCancelFixtures() throws {
        let scroll = try PackedPointerFrame.decode(try data(hex: Self.scrollHex))
        XCTAssertEqual(scroll.kind, .scroll)
        XCTAssertEqual(scroll.dx, -12.5)
        XCTAssertEqual(scroll.dy, 3.25)

        let cancel = try PackedPointerFrame.decode(try data(hex: Self.cancelHex))
        XCTAssertEqual(cancel.kind, .pointerCancel)
        XCTAssertNil(cancel.x)
    }

    func testMalformedFramesAreRejected() throws {
        var badMagic = try data(hex: Self.pointerHex)
        badMagic[0] = 0
        XCTAssertThrowsError(try PackedPointerFrame.decode(badMagic))

        var badVersion = try data(hex: Self.pointerHex)
        badVersion[2] = 2
        XCTAssertThrowsError(try PackedPointerFrame.decode(badVersion))

        XCTAssertThrowsError(try PackedPointerFrame.decode(Data([0x41, 0x44])))
        XCTAssertThrowsError(try PackedPointerFrame.sessionTag(for: String(repeating: "x", count: 65)))
    }

    func testFlatBufferControlEnvelope() throws {
        var builder = FlatBufferBuilder(initialSize: 256)
        let session = builder.create(string: "session-1")
        let appearance = builder.create(string: "light")
        let control = AirDesk_Protocol__ControlMessage.createControlMessage(
            &builder,
            type: .appearance,
            sessionIdOffset: session,
            generation: 7,
            seq: 2,
            timestamp: 1_700_000_000_123,
            appearanceOffset: appearance
        )
        let envelope = AirDesk_Protocol__Envelope.createEnvelope(
            &builder,
            payloadType: .controlmessage,
            payloadOffset: control
        )
        AirDesk_Protocol__Envelope.finish(&builder, end: envelope)
        var buffer = ByteBuffer(data: builder.data)
        let decoded: AirDesk_Protocol__Envelope = getRoot(byteBuffer: &buffer)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.payloadType, .controlmessage)
        let message = try XCTUnwrap(decoded.payload(type: AirDesk_Protocol__ControlMessage.self))
        XCTAssertEqual(message.type, .appearance)
        XCTAssertEqual(message.sessionId, "session-1")
        XCTAssertEqual(message.generation, 7)
        XCTAssertEqual(message.seq, 2)
        XCTAssertEqual(message.appearance, "light")
    }

    private func data(hex: String) throws -> Data {
        var result = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw PackedPointerFrameError.invalidLength
            }
            result.append(byte)
            index = next
        }
        return result
    }

    private static let pointerHex = "4144010000000000070000002a0000007b68e5cf8b0100004d1849cf5d5988160000803e0000403f00010000"
    private static let scrollHex = "4144010500000000070000002b0000007b68e5cf8b0100004d1849cf5d598816000048c100005040"
    private static let cancelHex = "4144010400000000070000002c0000007b68e5cf8b0100004d1849cf5d598816"
}
