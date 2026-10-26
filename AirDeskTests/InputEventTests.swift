import XCTest
@testable import AirDesk

final class InputEventTests: XCTestCase {
    func testValidPointerEvent() throws {
        let event = InputEvent.make(.pointerMove, sessionId: "session", seq: 4, x: 0.25, y: 0.75)
        XCTAssertNoThrow(try event.validated())
    }

    func testPointerCoordinatesAreBounded() {
        let event = InputEvent.make(.pointerClick, sessionId: "session", seq: 1, x: 1.2, y: 0.5)
        XCTAssertThrowsError(try event.validated()) { error in
            XCTAssertEqual(error as? InputEventError, .invalidCoordinates)
        }
    }

    func testEmptyTextIsRejected() {
        let event = InputEvent.make(.textInput, sessionId: "session", seq: 1, text: "")
        XCTAssertThrowsError(try event.validated()) { error in
            XCTAssertEqual(error as? InputEventError, .invalidText)
        }
    }

    func testUnsupportedModifierIsRejected() {
        let event = InputEvent.make(
            .keyDown,
            sessionId: "session",
            seq: 1,
            key: "a",
            modifiers: ["Hyper"]
        )
        XCTAssertThrowsError(try event.validated()) { error in
            XCTAssertEqual(error as? InputEventError, .invalidModifiers)
        }
    }

    func testInvalidViewportIsRejected() {
        let event = InputEvent.make(.viewportChanged, sessionId: "session", seq: 1, width: 0, height: 1080)
        XCTAssertThrowsError(try event.validated()) { error in
            XCTAssertEqual(error as? InputEventError, .invalidViewport)
        }
    }

    func testJSONObjectUsesProtocolFields() throws {
        let event = InputEvent.make(.scroll, sessionId: "session", seq: 9, dx: 12, dy: -8)
        let object = try event.jsonObject()
        XCTAssertEqual(object["type"] as? String, "scroll")
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["sessionId"] as? String, "session")
    }

    func testSessionStartDoesNotRequireCoordinates() throws {
        let event = InputEvent.make(.sessionStart, sessionId: "session", seq: 0)
        XCTAssertNoThrow(try event.validated())
    }
}
