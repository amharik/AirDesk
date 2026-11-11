import CoreGraphics
import XCTest
@testable import AirDesk

@MainActor
final class LocalCursorPresentationTests: XCTestCase {
    func testDisplayClockCoalescesInputToTheLatestPoint() {
        let presentation = LocalCursorPresentation(frameInterval: 1.0 / 60.0)
        var hostVisibility: [Bool] = []
        presentation.onHostCursorVisibleChanged = { hostVisibility.append($0) }

        presentation.start(sessionId: "session", generation: 4)
        XCTAssertTrue(presentation.isHostCursorSuppressed)
        XCTAssertEqual(hostVisibility, [false])

        presentation.move(to: CGPoint(x: 0.1, y: 0.2))
        XCTAssertEqual(presentation.frame(at: 0)?.point, CGPoint(x: 0.1, y: 0.2))

        presentation.move(to: CGPoint(x: 0.3, y: 0.4))
        presentation.move(to: CGPoint(x: 0.7, y: 0.8))
        XCTAssertNil(presentation.frame(at: 0.004))
        XCTAssertEqual(presentation.frame(at: 0.02)?.point, CGPoint(x: 0.7, y: 0.8))
    }

    func testMetadataUpdatesShapeAndHotspotWithoutDoubleCursor() throws {
        let presentation = LocalCursorPresentation()
        presentation.start(sessionId: "session", generation: 2)

        let remote = try metadata(seq: 0, shape: .iBeam, hotspotX: 0.3, hotspotY: 0.7, visible: true)
        XCTAssertFalse(try presentation.apply(remote))
        XCTAssertEqual(presentation.shape, .iBeam)
        XCTAssertEqual(presentation.hotspot, CGPoint(x: 0.3, y: 0.7))
        XCTAssertFalse(presentation.isRemoteCursorVisible)

        presentation.setLocalCursorEnabled(false)
        let visibleRemote = try metadata(seq: 1, shape: .pointingHand, visible: true)
        XCTAssertTrue(try presentation.apply(visibleRemote))
        XCTAssertTrue(presentation.isRemoteCursorVisible)

        presentation.setLocalCursorEnabled(true)
        XCTAssertFalse(presentation.isRemoteCursorVisible)
        XCTAssertTrue(presentation.isHostCursorSuppressed)
    }

    func testMetadataValidationRejectsInvalidAndStaleValues() throws {
        XCTAssertThrowsError(try metadata(sessionId: "", seq: 0).validated())
        XCTAssertThrowsError(try metadata(generation: -1, seq: 0).validated())
        XCTAssertThrowsError(try metadata(seq: -1).validated())
        XCTAssertThrowsError(try metadata(seq: 0, hotspotX: 1.1).validated())
        XCTAssertThrowsError(try metadata(seq: 0, shape: .hidden, visible: true).validated())

        let presentation = LocalCursorPresentation()
        presentation.start(sessionId: "session", generation: 2)
        try presentation.apply(metadata(seq: 5))

        XCTAssertThrowsError(try presentation.apply(metadata(seq: 4))) { error in
            XCTAssertEqual(error as? CursorMetadataError, .staleSequence)
        }
        XCTAssertThrowsError(try presentation.apply(metadata(sessionId: "other", seq: 6))) { error in
            XCTAssertEqual(error as? CursorMetadataError, .sessionMismatch)
        }
    }

    func testEndRestoresHostCursorExactlyOnce() {
        let presentation = LocalCursorPresentation()
        var hostVisibility: [Bool] = []
        presentation.onHostCursorVisibleChanged = { hostVisibility.append($0) }

        presentation.start(sessionId: "session")
        presentation.end()
        presentation.end()

        XCTAssertFalse(presentation.isActive)
        XCTAssertFalse(presentation.isHostCursorSuppressed)
        XCTAssertEqual(hostVisibility, [false, true])
        XCTAssertNil(presentation.frame(at: 1))
    }

    func testCursorMetadataJSONRoundTrips() throws {
        let original = try metadata(seq: 9, shape: .resizeDiagonal, hotspotX: 0.5, hotspotY: 0.5)
        let decoded = try CursorMetadata.decode(from: original.jsonObject())
        XCTAssertEqual(decoded, original)
        XCTAssertNoThrow(try decoded.validated())
    }

    private func metadata(
        sessionId: String = "session",
        generation: Int = 2,
        seq: Int,
        shape: CursorShape = .arrow,
        hotspotX: Double = 0.5,
        hotspotY: Double = 0.5,
        visible: Bool = false
    ) throws -> CursorMetadata {
        try CursorMetadata(
            sessionId: sessionId,
            generation: generation,
            seq: seq,
            shape: shape,
            hotspotX: hotspotX,
            hotspotY: hotspotY,
            visible: visible
        ).validated()
    }
}
