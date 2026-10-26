import XCTest
@testable import AirDesk

final class BridgeMessageTests: XCTestCase {
    func testReadyMessageIsValid() throws {
        let message = BridgeMessage(version: 1, type: "ready", sessionId: "session", runtime: "wanixDesktop")
        XCTAssertNoThrow(try message.validated())
    }

    func testUnsupportedVersionIsRejected() {
        let message = BridgeMessage(version: 2, type: "ready")
        XCTAssertThrowsError(try message.validated()) { error in
            XCTAssertEqual(error as? BridgeError, .unsupportedVersion)
        }
    }

    func testUnsupportedTypeIsRejected() {
        let message = BridgeMessage(version: 1, type: "execute")
        XCTAssertThrowsError(try message.validated()) { error in
            XCTAssertEqual(error as? BridgeError, .unsupportedType)
        }
    }

    func testOversizedMessageIsRejected() {
        let message = BridgeMessage(version: 1, type: "error", message: String(repeating: "x", count: 4001))
        XCTAssertThrowsError(try message.validated()) { error in
            XCTAssertEqual(error as? BridgeError, .messageTooLarge)
        }
    }

    func testInvalidLogLevelIsRejected() {
        let message = BridgeMessage(version: 1, type: "log", level: "verbose")
        XCTAssertThrowsError(try message.validated()) { error in
            XCTAssertEqual(error as? BridgeError, .invalidField)
        }
    }

    func testViewportBoundsAreValidated() {
        let valid = BridgeMessage(version: 1, type: "viewport", width: 1920, height: 1080)
        XCTAssertNoThrow(try valid.validated())

        let invalid = BridgeMessage(version: 1, type: "viewport", width: 20_001, height: 1080)
        XCTAssertThrowsError(try invalid.validated())
    }

    func testAllowedTypesMatchShellProtocol() {
        XCTAssertEqual(
            BridgeMessage.allowedTypes,
            Set(["ready", "ack", "log", "state", "error", "viewport", "action", "notice"])
        )
    }
}
