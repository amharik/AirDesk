import CoreGraphics
import XCTest
@testable import AirDesk

@MainActor
final class InputDispatcherTests: XCTestCase {
    func testClickFlushesPendingMoveAndAdvancesSequence() {
        let dispatcher = InputDispatcher(autoFlush: false)
        var events: [InputEvent] = []
        dispatcher.transport = ClosureInputTransport { events.append($0) }

        dispatcher.startSession(id: "session", viewport: CGSize(width: 1920, height: 1080))
        dispatcher.move(to: CGPoint(x: 0.25, y: 0.75))
        dispatcher.click(count: 2)

        XCTAssertEqual(events.map(\.type), [.sessionStart, .pointerMove, .pointerClick])
        XCTAssertEqual(events.map(\.seq), [0, 1, 2])
        XCTAssertEqual(events[1].x, 0.25)
        XCTAssertEqual(events[1].y, 0.75)
        XCTAssertEqual(events[2].clickCount, 2)
    }

    func testCancelAllInputReleasesActiveButtonsAndKeys() {
        let dispatcher = InputDispatcher(autoFlush: false)
        var events: [InputEvent] = []
        dispatcher.transport = ClosureInputTransport { events.append($0) }

        dispatcher.startSession(id: "session")
        dispatcher.pointerDown(button: 0)
        dispatcher.keyDown("a")
        dispatcher.cancelAllInput()

        XCTAssertEqual(events.map(\.type), [.sessionStart, .pointerDown, .keyDown, .pointerCancel, .pointerUp, .keyUp])
        XCTAssertEqual(events.last?.key, "a")
    }

    func testEndSessionStopsFurtherInput() {
        let dispatcher = InputDispatcher(autoFlush: false)
        var events: [InputEvent] = []
        dispatcher.transport = ClosureInputTransport { events.append($0) }

        dispatcher.startSession(id: "session")
        dispatcher.endSession()
        dispatcher.move(to: CGPoint(x: 0.8, y: 0.8))
        dispatcher.click()

        XCTAssertEqual(events.map(\.type), [.sessionStart, .pointerCancel, .sessionEnd])
        XCTAssertEqual(dispatcher.sequence, 3)
    }

    func testTextInputIsTruncatedToProtocolLimit() {
        let dispatcher = InputDispatcher(autoFlush: false)
        var events: [InputEvent] = []
        dispatcher.transport = ClosureInputTransport { events.append($0) }

        dispatcher.startSession(id: "session")
        dispatcher.textInput(String(repeating: "x", count: 5000))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].text?.count, 4096)
    }

    func testValidationHookCanDropRejectedEdges() {
        let dispatcher = InputDispatcher(autoFlush: false)
        var events: [InputEvent] = []
        dispatcher.transport = ClosureInputTransport { events.append($0) }
        dispatcher.validateOutgoing = { $0.type != .keyDown }

        dispatcher.startSession(id: "session")
        dispatcher.click()
        dispatcher.keyDown("a")

        XCTAssertEqual(events.map(\.type), [.sessionStart, .pointerClick])
    }

    func testDispatcherSeparatesMovementEdgesAndControlChannels() {
        let dispatcher = InputDispatcher(autoFlush: false)
        var routed: [(InputEvent, InputTransportChannel)] = []
        dispatcher.transport = ClosureInputTransport { event, channel in
            routed.append((event, channel))
        }

        dispatcher.startSession(id: "session", viewport: CGSize(width: 100, height: 100))
        dispatcher.move(to: CGPoint(x: 0.25, y: 0.75))
        dispatcher.flushPendingMove()
        dispatcher.click()
        dispatcher.updateViewport(CGSize(width: 200, height: 200))

        XCTAssertEqual(routed.map(\.1), [.control, .movement, .reliableEdges, .control])
        XCTAssertEqual(routed.map(\.0.type), [.sessionStart, .pointerMove, .pointerClick, .viewportChanged])
    }

    func testEventIsNotSentWithoutTransport() {
        let dispatcher = InputDispatcher(autoFlush: false)
        dispatcher.startSession(id: "session")
        dispatcher.click()
        XCTAssertEqual(dispatcher.sequence, 2)
    }
}
