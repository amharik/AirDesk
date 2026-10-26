import CoreGraphics
import XCTest
@testable import AirDesk

final class PointerStateTests: XCTestCase {
    func testMoveAppliesGainWithoutAcceleration() {
        var pointer = PointerState(position: CGPoint(x: 0.5, y: 0.5), sensitivity: 0.9, accelerationEnabled: false)
        let point = pointer.move(
            delta: CGSize(width: 100, height: -50),
            viewport: CGSize(width: 1000, height: 1000),
            timestamp: 10
        )
        XCTAssertEqual(point.x, 0.7025, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.39875, accuracy: 0.0001)
    }

    func testMoveClampsToDesktopBounds() {
        var pointer = PointerState(position: CGPoint(x: 0.95, y: 0.05), sensitivity: 2, accelerationEnabled: false)
        let point = pointer.move(
            delta: CGSize(width: 4000, height: -4000),
            viewport: CGSize(width: 100, height: 100),
            timestamp: 20
        )
        XCTAssertEqual(point.x, 1)
        XCTAssertEqual(point.y, 0)
    }

    func testSetPositionClamps() {
        var pointer = PointerState()
        pointer.setPosition(CGPoint(x: -0.4, y: 1.8))
        XCTAssertEqual(pointer.position.x, 0)
        XCTAssertEqual(pointer.position.y, 1)
    }

    func testCenterResetsPosition() {
        var pointer = PointerState(position: CGPoint(x: 0.1, y: 0.9))
        pointer.center()
        XCTAssertEqual(pointer.position, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(pointer.lastMoveTime, 0)
    }

    func testScrollDirection() {
        XCTAssertEqual(PointerState.scrollDelta(dx: 4, dy: 8, naturalScrolling: true).0, -4)
        XCTAssertEqual(PointerState.scrollDelta(dx: 4, dy: 8, naturalScrolling: true).1, -8)
        XCTAssertEqual(PointerState.scrollDelta(dx: 4, dy: 8, naturalScrolling: false).1, 8)
    }

    func testInvalidViewportDoesNotMovePointer() {
        var pointer = PointerState(position: CGPoint(x: 0.3, y: 0.3))
        let point = pointer.move(
            delta: CGSize(width: 40, height: 40),
            viewport: .zero,
            timestamp: 30
        )
        XCTAssertEqual(point, CGPoint(x: 0.3, y: 0.3))
    }
}
