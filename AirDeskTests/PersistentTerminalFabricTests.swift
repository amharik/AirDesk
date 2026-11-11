import Foundation
import XCTest
@testable import AirDesk

final class PersistentTerminalFabricTests: XCTestCase {
    func testDataFrameRoundTripsThroughADFP() throws {
        let frame = TerminalFabricFrame(
            frameType: .data,
            sessionId: "session-1",
            clientId: "client-1",
            leaseId: "lease-1",
            sequence: 7,
            replayFromSequence: 0,
            oldestSequence: 3,
            data: Data([0x1B, 0x5B, 0x41]),
            columns: 132,
            rows: 43,
            truncated: true
        )

        let encoded = try TerminalFabricCodec.encode(frame)
        let decoded = try TerminalFabricCodec.decode(encoded)

        XCTAssertEqual(decoded, frame)
        XCTAssertEqual(decoded.leaseId, "lease-1")
        XCTAssertEqual(decoded.data, Data([0x1B, 0x5B, 0x41]))
    }

    func testLengthPrefixedStreamHandlesSplitFrames() throws {
        let first = try TerminalFabricCodec.encodeLengthPrefixed(
            TerminalFabricFrame(frameType: .attached, sessionId: "session-1", sequence: 1)
        )
        let second = try TerminalFabricCodec.encodeLengthPrefixed(
            TerminalFabricFrame(frameType: .exit, sessionId: "session-1", exitCode: 7)
        )
        let combined = first + second

        var buffer = Data(combined.prefix(9))
        XCTAssertNil(try TerminalFabricCodec.takeLengthPrefixedFrame(from: &buffer))
        buffer.append(combined.dropFirst(9))

        let decodedFirst = try XCTUnwrap(
            try TerminalFabricCodec.takeLengthPrefixedFrame(from: &buffer)
        )
        let decodedSecond = try XCTUnwrap(
            try TerminalFabricCodec.takeLengthPrefixedFrame(from: &buffer)
        )

        XCTAssertEqual(decodedFirst.frameType, .attached)
        XCTAssertEqual(decodedFirst.sequence, 1)
        XCTAssertEqual(decodedSecond.frameType, .exit)
        XCTAssertEqual(decodedSecond.exitCode, 7)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testReplayStateDropsDuplicateDataAndResumesFromLastSequence() throws {
        var state = PersistentTerminalReplayState()
        XCTAssertTrue(state.accept(
            TerminalFabricFrame(
                frameType: .attached,
                sessionId: "session-1",
                oldestSequence: 2,
                truncated: true
            )
        ))
        XCTAssertTrue(state.accept(
            TerminalFabricFrame(frameType: .data, sessionId: "session-1", sequence: 4)
        ))
        XCTAssertFalse(state.accept(
            TerminalFabricFrame(frameType: .data, sessionId: "session-1", sequence: 4)
        ))
        XCTAssertFalse(state.accept(
            TerminalFabricFrame(frameType: .data, sessionId: "session-1", sequence: 3)
        ))
        XCTAssertTrue(state.accept(
            TerminalFabricFrame(frameType: .data, sessionId: "session-1", sequence: 5)
        ))

        XCTAssertEqual(state.lastSequence, 5)
        XCTAssertEqual(state.oldestSequence, 2)
        XCTAssertTrue(state.truncated)

        let request = state.attachRequest(
            sessionId: "session-1",
            clientId: "client-1",
            leaseId: "lease-1"
        )
        XCTAssertEqual(request.frameType, .attach)
        XCTAssertEqual(request.replayFromSequence, 5)
    }

    func testInvalidFramesAreRejected() throws {
        XCTAssertThrowsError(try TerminalFabricCodec.decode(Data())) { error in
            XCTAssertEqual(error as? TerminalFabricError, .empty)
        }
        XCTAssertThrowsError(try TerminalFabricCodec.encode(
            TerminalFabricFrame(frameType: .attach, sessionId: "")
        )) { error in
            XCTAssertEqual(error as? TerminalFabricError, .missingSession)
        }

        var buffer = Data([0, 0, 0, 0])
        XCTAssertThrowsError(try TerminalFabricCodec.takeLengthPrefixedFrame(from: &buffer)) { error in
            XCTAssertEqual(error as? TerminalFabricError, .empty)
        }
    }
}
