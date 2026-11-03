import XCTest
@testable import AirDesk

final class InputLeaseManagerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testPrimaryLeaseGrantsEpochAndReleasesInputOnHandoff() throws {
        let manager = makeManager()
        var changes: [InputLeaseChange] = []
        manager.onLeaseChange = { changes.append($0) }
        try manager.attach(controllerId: "c1", deviceId: "d1", role: .primaryDriver, now: start)
        try manager.attach(controllerId: "c2", deviceId: "d2", role: .primaryDriver, now: start)

        let first = try manager.requestLease(controllerId: "c1", now: start)
        XCTAssertEqual(first.leaseEpoch, 1)
        XCTAssertEqual(manager.activeControllerId, "c1")

        let key = InputEvent.make(.keyDown, sessionId: "s", generation: 1, seq: 1, key: "a")
        _ = try manager.validateEdge(key, on: context("c1", epoch: 1), now: start)
        XCTAssertEqual(manager.pressedKeys(for: "c1"), ["a"])

        let second = try manager.requestLease(
            controllerId: "c2",
            forcePreempt: true,
            confirmed: true,
            now: start.addingTimeInterval(1)
        )
        XCTAssertEqual(second.leaseEpoch, 2)
        XCTAssertEqual(second.previousControllerId, "c1")
        XCTAssertTrue(second.releasedAllInput)
        XCTAssertTrue(manager.pressedKeys(for: "c1").isEmpty)
        XCTAssertEqual(changes.count, 2)
    }

    func testBusyLeaseAndUnconfirmedPreemptionAreRejected() throws {
        let manager = makeManager()
        try manager.attach(controllerId: "c1", deviceId: "d1", role: .primaryDriver, now: start)
        try manager.attach(controllerId: "c2", deviceId: "d2", role: .primaryDriver, now: start)
        _ = try manager.requestLease(controllerId: "c1", now: start)

        XCTAssertThrowsError(try manager.requestLease(
            controllerId: "c2",
            now: start.addingTimeInterval(0.1)
        )) { error in
            XCTAssertEqual(error as? InputLeaseError, .leaseBusy(activeControllerId: "c1"))
        }
        XCTAssertThrowsError(try manager.requestLease(
            controllerId: "c2",
            forcePreempt: true,
            confirmed: false,
            now: start.addingTimeInterval(0.2)
        )) { error in
            XCTAssertEqual(error as? InputLeaseError, .preemptionNotConfirmed)
        }
        XCTAssertEqual(manager.audit.last?.accepted, false)
    }

    func testStaleEpochAndDuplicateSequenceAreRejected() throws {
        let manager = makeManager()
        try manager.attach(controllerId: "c1", deviceId: "d1", role: .primaryDriver, now: start)
        _ = try manager.requestLease(controllerId: "c1", now: start)

        let event = InputEvent.make(.pointerDown, sessionId: "s", generation: 1, seq: 4, x: 0.2, y: 0.2, button: 0)
        XCTAssertThrowsError(try manager.validateEdge(event, on: context("c1", epoch: 0), now: start)) { error in
            XCTAssertEqual(error as? InputLeaseError, .epochRejected(currentEpoch: 1))
        }
        _ = try manager.validateEdge(event, on: context("c1", epoch: 1), now: start)
        XCTAssertThrowsError(try manager.validateEdge(event, on: context("c1", epoch: 1), now: start)) { error in
            XCTAssertEqual(error as? InputLeaseError, .sequenceRejected(controllerId: "c1", sequence: 4))
        }
    }

    func testPinnedDriverCannotMoveSharedCursorOrSendKeyboard() throws {
        let manager = makeManager()
        try manager.attach(
            controllerId: "pin",
            deviceId: "d1",
            role: .pinnedSurfaceDriver,
            targetWindowId: "window.1",
            now: start
        )

        let pointer = InputEvent.make(
            .pointerDown,
            sessionId: "s",
            generation: 1,
            seq: 1,
            x: 0.2,
            y: 0.2,
            button: 0,
            target: "window.1"
        )
        _ = try manager.validateEdge(pointer, on: context("pin", epoch: 0), now: start)

        let wrongTarget = InputEvent.make(
            .pointerDown,
            sessionId: "s",
            generation: 1,
            seq: 2,
            x: 0.2,
            y: 0.2,
            button: 0,
            target: "window.2"
        )
        XCTAssertThrowsError(try manager.validateEdge(wrongTarget, on: context("pin", epoch: 0), now: start)) { error in
            XCTAssertEqual(error as? InputLeaseError, .targetMismatch(controllerId: "pin"))
        }

        let key = InputEvent.make(.keyDown, sessionId: "s", generation: 1, seq: 3, key: "a")
        XCTAssertThrowsError(try manager.validateEdge(key, on: context("pin", epoch: 0), now: start)) { error in
            XCTAssertEqual(
                error as? InputLeaseError,
                .roleNotPermitted(controllerId: "pin", role: .pinnedSurfaceDriver)
            )
        }

        let frame = PackedMovementFrame(leaseEpochLow: 0, seq: 1, x: 0.1, y: 0.1)
        XCTAssertNotNil(manager.acceptMovement(frame, on: context("pin", epoch: 0)))
        XCTAssertNil(manager.sharedCursor)
    }

    func testPrimaryAndPinnedControllersKeepDistinctCursors() throws {
        let manager = makeManager()
        try manager.attach(controllerId: "primary", deviceId: "d1", role: .primaryDriver, now: start)
        try manager.attach(
            controllerId: "pinned",
            deviceId: "d2",
            role: .pinnedSurfaceDriver,
            targetWindowId: "window.1",
            now: start
        )
        _ = try manager.requestLease(controllerId: "primary", now: start)

        let primary = try manager.moveCursor(
            controllerId: "primary",
            to: InputPoint(x: 0.2, y: 0.3),
            epoch: 1
        )
        let pinned = try manager.moveCursor(
            controllerId: "pinned",
            to: InputPoint(x: 0.8, y: 0.7),
            epoch: 1
        )

        XCTAssertEqual(primary.local, InputPoint(x: 0.2, y: 0.3))
        XCTAssertEqual(primary.shared, InputPoint(x: 0.2, y: 0.3))
        XCTAssertEqual(pinned.local, InputPoint(x: 0.8, y: 0.7))
        XCTAssertNil(pinned.shared)
        XCTAssertEqual(manager.sharedCursor, InputPoint(x: 0.2, y: 0.3))

        let key = InputEvent.make(.keyDown, sessionId: "s", generation: 1, seq: 1, key: "a")
        XCTAssertNoThrow(try manager.validateEdge(key, on: context("primary", epoch: 1), now: start))
        let pinnedKey = InputEvent.make(.keyDown, sessionId: "s", generation: 1, seq: 1, key: "b")
        XCTAssertThrowsError(try manager.validateEdge(
            pinnedKey,
            on: context("pinned", epoch: 1),
            now: start
        ))
    }

    func testMovementFramesAreStaleDroppedAndUpdateSharedCursorForPrimary() throws {
        let manager = makeManager()
        try manager.attach(controllerId: "c1", deviceId: "d1", role: .primaryDriver, now: start)
        _ = try manager.requestLease(controllerId: "c1", now: start)

        let frame = PackedMovementFrame(leaseEpochLow: 1, seq: 10, x: 0.25, y: 0.75)
        XCTAssertNotNil(manager.acceptMovement(frame, on: context("c1", epoch: 1)))
        XCTAssertEqual(manager.sharedCursor, InputPoint(x: 0.25, y: 0.75))
        XCTAssertNil(manager.acceptMovement(frame, on: context("c1", epoch: 1)))
        XCTAssertNil(manager.acceptMovement(
            PackedMovementFrame(leaseEpochLow: 0, seq: 11, x: 0.4, y: 0.4),
            on: context("c1", epoch: 1)
        ))
        XCTAssertEqual(manager.sharedCursor, InputPoint(x: 0.25, y: 0.75))
    }

    func testDisconnectAndTimeoutReleaseLeaseAndPressedState() throws {
        let manager = makeManager()
        try manager.attach(controllerId: "c1", deviceId: "d1", role: .primaryDriver, now: start)
        _ = try manager.requestLease(controllerId: "c1", now: start)
        let key = InputEvent.make(.keyDown, sessionId: "s", generation: 1, seq: 1, key: "a")
        _ = try manager.validateEdge(key, on: context("c1", epoch: 1), now: start)

        manager.detach(controllerId: "c1", now: start)
        XCTAssertNil(manager.activeControllerId)
        XCTAssertEqual(manager.leaseEpoch, 2)
        XCTAssertTrue(manager.pressedKeys(for: "c1").isEmpty)

        try manager.attach(controllerId: "c2", deviceId: "d2", role: .primaryDriver, now: start)
        _ = try manager.requestLease(controllerId: "c2", now: start)
        let change = manager.expireLease(now: start.addingTimeInterval(4))
        XCTAssertEqual(change?.leaseEpoch, 4)
        XCTAssertNil(manager.activeControllerId)
    }

    func testStaleEpochWinsOverDuplicateSequence() throws {
        let manager = makeManager()
        try manager.attach(controllerId: "c1", deviceId: "d1", role: .primaryDriver, now: start)
        _ = try manager.requestLease(controllerId: "c1", now: start)

        let event = InputEvent.make(.pointerDown, sessionId: "s", generation: 1, seq: 4, x: 0.2, y: 0.2, button: 0)
        _ = try manager.validateEdge(event, on: context("c1", epoch: 1), now: start)
        XCTAssertThrowsError(try manager.validateEdge(event, on: context("c1", epoch: 0), now: start)) { error in
            XCTAssertEqual(error as? InputLeaseError, .epochRejected(currentEpoch: 1))
        }
    }

    func testEndSessionInvalidatesLeaseAndPressedState() throws {
        let manager = makeManager()
        try manager.attach(controllerId: "c1", deviceId: "d1", role: .primaryDriver, now: start)
        _ = try manager.requestLease(controllerId: "c1", now: start)
        let key = InputEvent.make(.keyDown, sessionId: "s", generation: 1, seq: 1, key: "a")
        _ = try manager.validateEdge(key, on: context("c1", epoch: 1), now: start)

        manager.endSession()

        XCTAssertEqual(manager.sessionId, "")
        XCTAssertEqual(manager.generation, 0)
        XCTAssertEqual(manager.leaseEpoch, 0)
        XCTAssertNil(manager.activeControllerId)
        XCTAssertNil(manager.sharedCursor)
        XCTAssertTrue(manager.pressedKeys(for: "c1").isEmpty)
        let old = InputConnectionContext(
            sessionId: "s",
            generation: 1,
            deviceId: "d",
            controllerId: "c1",
            leaseEpoch: 1
        )
        XCTAssertThrowsError(try manager.validateEdge(key, on: old, now: start))
    }

    func testGenerationResetInvalidatesOldContext() throws {
        let manager = makeManager()
        try manager.attach(controllerId: "c1", deviceId: "d1", role: .primaryDriver, now: start)
        _ = try manager.requestLease(controllerId: "c1", now: start)

        manager.beginSession(sessionId: "s", generation: 2, now: start)
        XCTAssertEqual(manager.leaseEpoch, 0)
        XCTAssertNil(manager.activeControllerId)

        let event = InputEvent.make(.pointerDown, sessionId: "s", generation: 1, seq: 1, x: 0.2, y: 0.2, button: 0)
        XCTAssertThrowsError(try manager.validateEdge(event, on: context("c1", epoch: 0), now: start)) { error in
            XCTAssertEqual(error as? InputLeaseError, .generationMismatch(expected: 2, received: 1))
        }
    }

    private func makeManager() -> InputLeaseManager {
        let manager = InputLeaseManager()
        manager.beginSession(sessionId: "s", generation: 1, now: start)
        return manager
    }

    private func context(_ controllerId: String, epoch: UInt64) -> InputConnectionContext {
        InputConnectionContext(
            sessionId: "s",
            generation: 1,
            deviceId: "d",
            controllerId: controllerId,
            leaseEpoch: epoch
        )
    }
}
