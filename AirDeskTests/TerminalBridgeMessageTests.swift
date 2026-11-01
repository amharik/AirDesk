import XCTest
@testable import AirDesk

final class TerminalBridgeMessageTests: XCTestCase {
    func testAcceptsSupportedActions() throws {
        XCTAssertNoThrow(try TerminalBridgeMessage(version: 1, action: "start").validated())
        XCTAssertNoThrow(try TerminalBridgeMessage(version: 1, action: "stop").validated())
        XCTAssertNoThrow(try TerminalBridgeMessage(
            version: 1,
            action: "write",
            data: Data("hello".utf8).base64EncodedString()
        ).validated())
        XCTAssertNoThrow(try TerminalBridgeMessage(
            version: 1,
            action: "resize",
            columns: 120,
            rows: 40
        ).validated())
    }

    func testRejectsUnsupportedVersionAndAction() {
        XCTAssertThrowsError(try TerminalBridgeMessage(version: 2, action: "start").validated()) { error in
            XCTAssertEqual(error as? TerminalBridgeError, .unsupportedVersion)
        }
        XCTAssertThrowsError(try TerminalBridgeMessage(version: 1, action: "shell").validated()) { error in
            XCTAssertEqual(error as? TerminalBridgeError, .unsupportedAction)
        }
    }

    func testRejectsInvalidWriteAndResizeFields() {
        XCTAssertThrowsError(try TerminalBridgeMessage(version: 1, action: "write").validated()) { error in
            XCTAssertEqual(error as? TerminalBridgeError, .invalidField)
        }
        XCTAssertThrowsError(try TerminalBridgeMessage(
            version: 1,
            action: "write",
            data: "not base64!"
        ).validated()) { error in
            XCTAssertEqual(error as? TerminalBridgeError, .invalidField)
        }
        XCTAssertThrowsError(try TerminalBridgeMessage(
            version: 1,
            action: "resize",
            columns: 0,
            rows: 40
        ).validated()) { error in
            XCTAssertEqual(error as? TerminalBridgeError, .invalidField)
        }
        XCTAssertThrowsError(try TerminalBridgeMessage(
            version: 1,
            action: "resize",
            columns: 80,
            rows: 1_001
        ).validated()) { error in
            XCTAssertEqual(error as? TerminalBridgeError, .invalidField)
        }
    }

    func testRejectsOversizedInput() {
        let data = Data(repeating: 0x61, count: TerminalBridgeMessage.maximumDataLength + 1)
        XCTAssertThrowsError(try TerminalBridgeMessage(
            version: 1,
            action: "write",
            data: data.base64EncodedString()
        ).validated()) { error in
            XCTAssertEqual(error as? TerminalBridgeError, .payloadTooLarge)
        }
    }

    func testRejectsLongSessionIdentifier() {
        XCTAssertThrowsError(try TerminalBridgeMessage(
            version: 1,
            sessionId: String(repeating: "a", count: 65),
            action: "start"
        ).validated()) { error in
            XCTAssertEqual(error as? TerminalBridgeError, .invalidSession)
        }
    }
}
