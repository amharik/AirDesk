import XCTest
@testable import AirDesk

final class SessionRecoveryTests: XCTestCase {
    func testBackoffGrowsAndCaps() {
        XCTAssertEqual(SessionRecovery.backoff(for: 0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SessionRecovery.backoff(for: 1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SessionRecovery.backoff(for: 2), 2.0, accuracy: 0.0001)
        XCTAssertEqual(SessionRecovery.backoff(for: 3), 4.0, accuracy: 0.0001)
        XCTAssertEqual(SessionRecovery.backoff(for: 4), 8.0, accuracy: 0.0001)
        XCTAssertEqual(SessionRecovery.backoff(for: 10), 8.0, accuracy: 0.0001)
    }

    func testAttemptsStopAtMaximum() {
        var recovery = SessionRecovery()

        for expected in 1...4 {
            XCTAssertNotNil(recovery.beginAttempt())
            XCTAssertEqual(recovery.attempts, expected)
        }

        XCTAssertNil(recovery.beginAttempt())
        XCTAssertFalse(recovery.canRetry)
        XCTAssertEqual(recovery.attempts, 4)
    }

    func testResetClearsState() {
        var recovery = SessionRecovery()
        _ = recovery.beginAttempt()
        _ = recovery.beginAttempt()

        recovery.reset()

        XCTAssertEqual(recovery.attempts, 0)
        XCTAssertNil(recovery.lastAttempt)
        XCTAssertTrue(recovery.canRetry)
    }

    func testCustomMaximumAttempts() {
        var recovery = SessionRecovery()
        recovery.maximumAttempts = 1

        XCTAssertNotNil(recovery.beginAttempt())
        XCTAssertNil(recovery.beginAttempt())
        XCTAssertFalse(recovery.canRetry)
    }
}
