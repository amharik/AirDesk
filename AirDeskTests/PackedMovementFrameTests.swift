import XCTest
@testable import AirDesk

final class PackedMovementFrameTests: XCTestCase {
    func testFixtureDecodesAndRoundTrips() throws {
        let data = try bytes("a52407002a0000000000803e0000403f")
        let frame = try PackedMovementFrame.decode(data)

        XCTAssertEqual(frame.leaseEpochLow, 7)
        XCTAssertEqual(frame.seq, 42)
        XCTAssertEqual(frame.x, 0.25)
        XCTAssertEqual(frame.y, 0.75)
        XCTAssertEqual(frame.buttonMask, 1)
        XCTAssertEqual(frame.modifiers, .shift)
        XCTAssertEqual(try frame.encoded(), data)
    }

    func testRejectsUnnegotiatedPackedFormat() throws {
        let data = try bytes("a52407002a0000000000803e0000403f")
        XCTAssertThrowsError(try PackedMovementFrame.decode(data, negotiated: false)) { error in
            XCTAssertEqual(error as? PackedMovementFrameError, .packedFormatNotNegotiated)
        }
    }

    func testRejectsEdgesOnMovementFrame() throws {
        var data = try bytes("a52407002a0000000000803e0000403f")
        data[1] = 0x25
        XCTAssertThrowsError(try PackedMovementFrame.decode(data)) { error in
            XCTAssertEqual(error as? PackedMovementFrameError, .edgeNotAllowed)
        }
    }

    func testRejectsMalformedFrames() throws {
        XCTAssertThrowsError(try PackedMovementFrame.decode(Data([0xA5])))
        var badMagic = try bytes("a52407002a0000000000803e0000403f")
        badMagic[0] = 0
        XCTAssertThrowsError(try PackedMovementFrame.decode(badMagic))
        var badCoordinates = try bytes("a52407002a0000000000803e0000403f")
        badCoordinates.replaceSubrange(8..<12, with: Float(1.5).bitPattern.littleEndianBytes)
        XCTAssertThrowsError(try PackedMovementFrame.decode(badCoordinates))
        XCTAssertThrowsError(try PackedMovementFrame(
            leaseEpochLow: 1,
            seq: 1,
            x: 0.2,
            y: 0.2,
            buttonMask: 8
        ).encoded())
    }

    func testRandomAndBitFlippedInputsNeverCrash() throws {
        var generator = SeededGenerator(seed: 0xA1DE5C)
        for _ in 0..<5_000 {
            let length = Int.random(in: 0...32, using: &generator)
            let data = Data((0..<length).map { _ in
                UInt8.random(in: 0...UInt8.max, using: &generator)
            })
            _ = try? PackedMovementFrame.decode(data)
        }

        let valid = try bytes("a52407002a0000000000803e0000403f")
        for bit in 0..<(valid.count * 8) {
            var mutated = valid
            mutated[bit / 8] ^= 1 << UInt8(bit % 8)
            _ = try? PackedMovementFrame.decode(mutated)
        }
    }

    func testNegotiatesPackedV12AndFallsBackToLegacy() throws {
        let modern = try InputProtocolNegotiator.negotiate(local: .current, remote: .current)
        XCTAssertEqual(modern.version, .packedMovement)
        XCTAssertEqual(modern.packedVersion, 12)
        XCTAssertTrue(modern.usesReliableEdgeChannel)

        let legacy = try InputProtocolNegotiator.negotiate(local: .legacyOnly, remote: .legacyOnly)
        XCTAssertEqual(legacy.version, .legacy)
        XCTAssertNil(legacy.packedVersion)
        XCTAssertFalse(legacy.usesReliableEdgeChannel)

        XCTAssertThrowsError(try InputProtocolNegotiator.negotiate(
            local: .current,
            remote: InputProtocolOffer(versions: [2], packedVersions: [], supportsReliableEdgeChannel: false)
        ))
    }

    func testChannelFirstRouting() throws {
        let move = InputEvent.make(.pointerMove, sessionId: "s", generation: 1, seq: 1, x: 0.2, y: 0.2)
        let click = InputEvent.make(.pointerDown, sessionId: "s", generation: 1, seq: 2, x: 0.2, y: 0.2, button: 0)
        let viewport = InputEvent.make(.viewportChanged, sessionId: "s", generation: 1, seq: 3, width: 100, height: 100)

        XCTAssertEqual(try InputChannelRouter.route(move), .movement)
        XCTAssertEqual(try InputChannelRouter.route(click), .reliableEdges)
        XCTAssertEqual(try InputChannelRouter.route(viewport), .control)
        XCTAssertNoThrow(try InputChannelRouter.validate(move, on: .movement))
        XCTAssertThrowsError(try InputChannelRouter.validate(click, on: .movement)) { error in
            XCTAssertEqual(error as? InputProtocolError, .edgeOnMovementChannel)
        }
        XCTAssertThrowsError(try InputChannelRouter.validate(move, on: .reliableEdges)) { error in
            XCTAssertEqual(error as? InputProtocolError, .movementOnReliableChannel)
        }
        XCTAssertThrowsError(try InputChannelRouter.validate(
            PackedMovementFrame(leaseEpochLow: 1, seq: 1, x: 0.5, y: 0.5),
            on: .reliableEdges
        )) { error in
            XCTAssertEqual(error as? InputProtocolError, .movementOnReliableChannel)
        }
    }

    func testChannelFirstClassifierUsesTheChannelBeforeThePayload() throws {
        let negotiated = try InputProtocolNegotiator.negotiate(local: .current, remote: .current)
        let legacy = try InputProtocolNegotiator.negotiate(local: .legacyOnly, remote: .legacyOnly)
        let movement = try PackedMovementFrame(leaseEpochLow: 1, seq: 1, x: 0.5, y: 0.5).encoded()
        let envelope = Data([8, 0, 0, 0, 0x41, 0x44, 0x45, 0x4E, 0, 0, 0, 0])

        XCTAssertEqual(
            try InputChannelRouter.classify(movement, on: .movement, negotiated: negotiated),
            .packedMovement
        )
        XCTAssertEqual(
            try InputChannelRouter.classify(envelope, on: .reliableEdges, negotiated: negotiated),
            .flatBufferEnvelope
        )
        XCTAssertEqual(
            try InputChannelRouter.classify(envelope, on: .control, negotiated: legacy),
            .flatBufferEnvelope
        )
        XCTAssertThrowsError(try InputChannelRouter.classify(
            movement,
            on: .reliableEdges,
            negotiated: negotiated
        )) { error in
            XCTAssertEqual(error as? InputProtocolError, .movementOnReliableChannel)
        }
        XCTAssertThrowsError(try InputChannelRouter.classify(
            movement,
            on: .movement,
            negotiated: legacy
        )) { error in
            XCTAssertEqual(error as? InputProtocolError, .packedFormatNotNegotiated)
        }
        XCTAssertThrowsError(try InputChannelRouter.classify(
            envelope,
            on: .movement,
            negotiated: negotiated
        )) { error in
            XCTAssertEqual(error as? InputProtocolError, .unknownMultiplexedFrame)
        }
    }

    func testMultiplexedDiscriminator() throws {
        let negotiated = try InputProtocolNegotiator.negotiate(local: .current, remote: .current)
        XCTAssertEqual(
            try InputChannelRouter.classifyMultiplexed(Data([0xA5, 0, 0, 0]), negotiated: negotiated),
            .packedMovement
        )
        XCTAssertEqual(
            try InputChannelRouter.classifyMultiplexed(Data([8, 0, 0, 0, 0x41, 0x44, 0x45, 0x4E, 0, 0, 0, 0]), negotiated: negotiated),
            .flatBufferEnvelope
        )
        XCTAssertThrowsError(try InputChannelRouter.classifyMultiplexed(Data([1, 2, 3]), negotiated: negotiated))
        XCTAssertThrowsError(try InputChannelRouter.classifyMultiplexed(
            Data([0xA5, 0, 0, 0]),
            negotiated: NegotiatedInputProtocol(version: .legacy, packedVersion: nil, usesReliableEdgeChannel: false)
        ))
    }

    func testConnectionContextRejectsMismatches() throws {
        let context = InputConnectionContext(
            sessionId: "session-1",
            generation: 7,
            deviceId: "device-1",
            controllerId: "controller-1",
            leaseEpoch: 3
        )
        let event = InputEvent.make(.pointerMove, sessionId: "session-1", generation: 7, seq: 1, x: 0.5, y: 0.5)
        XCTAssertNoThrow(try InputContextResolver.resolve(event, on: context))

        let wrongSession = InputEvent.make(.pointerMove, sessionId: "session-2", generation: 7, seq: 2, x: 0.5, y: 0.5)
        XCTAssertThrowsError(try InputContextResolver.resolve(wrongSession, on: context))

        let wrongGeneration = InputEvent.make(.pointerMove, sessionId: "session-1", generation: 8, seq: 3, x: 0.5, y: 0.5)
        XCTAssertThrowsError(try InputContextResolver.resolve(wrongGeneration, on: context))

        let validMovement = PackedMovementFrame(leaseEpochLow: 3, seq: 4, x: 0.5, y: 0.5)
        XCTAssertEqual(try InputContextResolver.resolveMovement(validMovement, on: context), validMovement)
        let staleMovement = PackedMovementFrame(leaseEpochLow: 2, seq: 5, x: 0.5, y: 0.5)
        XCTAssertThrowsError(try InputContextResolver.resolveMovement(staleMovement, on: context)) { error in
            XCTAssertEqual(
                error as? InputProtocolError,
                .epochRejected(currentEpoch: 3, received: 2)
            )
        }
    }

    func testLatencyProbeUsesControlExchange() throws {
        let tracker = InputLatencyProbeTracker()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let probe = tracker.begin(now: start)
        XCTAssertEqual(probe.id, 1)
        XCTAssertNil(tracker.lastLatency)
        XCTAssertEqual(tracker.complete(probe, echoAt: start.addingTimeInterval(0.042)) ?? -1, 0.042, accuracy: 0.0001)
        XCTAssertEqual(tracker.lastLatency ?? -1, 0.042, accuracy: 0.0001)
        XCTAssertNil(tracker.complete(probe, echoAt: start))
    }

    private func bytes(_ hex: String) throws -> Data {
        var result = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw PackedMovementFrameError.invalidLength
            }
            result.append(byte)
            index = next
        }
        return result
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
