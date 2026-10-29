import XCTest

final class InputDiagnosticsTests: XCTestCase {
    private func launchProbeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AirDeskAutoDemo", "-AirDeskUITestProbe"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["Session menu"].waitForExistence(timeout: 150), app.debugDescription)
        return app
    }

    private func probeLabel(_ app: XCUIApplication) -> String {
        app.staticTexts["JSLogProbe"].label
    }

    @discardableResult
    private func waitForProbe(_ app: XCUIApplication, containing text: String, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if probeLabel(app).contains(text) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return probeLabel(app).contains(text)
    }

    func testVirtualDeckTypingDeliversInputMode() throws {
        let app = launchProbeApp()
        XCTAssertTrue(waitForProbe(app, containing: "inputMode captured=true", timeout: 15), "probe=\(probeLabel(app))")

        let captureButton = app.buttons["Physical input captured. Tap to release."]
        XCTAssertTrue(captureButton.waitForExistence(timeout: 5), app.debugDescription)
        captureButton.tap()
        XCTAssertTrue(waitForProbe(app, containing: "inputMode captured=false"), "probe=\(probeLabel(app))")

        let keyA = app.buttons["A"]
        XCTAssertTrue(keyA.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertGreaterThan(keyA.frame.width, 44)
        XCTAssertGreaterThan(keyA.frame.height, 30)
        keyA.tap()
        XCTAssertTrue(waitForProbe(app, containing: "sendTerminalData ok"), "probe=\(probeLabel(app))")
    }

    func testHardwareKeyboardCaptureTyping() throws {
        let app = launchProbeApp()
        sleep(2)
        app.typeText("a")
        XCTAssertTrue(waitForProbe(app, containing: "sendTerminalData ok"), "probe=\(probeLabel(app))")
    }

    func testTrackpadLongPressKeepsAppResponsive() throws {
        let app = launchProbeApp()
        sleep(2)

        let captureButton = app.buttons["Physical input captured. Tap to release."]
        if captureButton.waitForExistence(timeout: 5) {
            captureButton.tap()
        }

        let keyA = app.buttons["A"]
        if !keyA.waitForExistence(timeout: 8), captureButton.exists {
            captureButton.tap()
        }
        XCTAssertTrue(keyA.waitForExistence(timeout: 20), app.debugDescription)

        let trackpad = app.otherElements["MacTrackpad"]
        XCTAssertTrue(trackpad.waitForExistence(timeout: 20), app.debugDescription)
        let start = trackpad.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        let end = trackpad.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        start.press(forDuration: 1.2, thenDragTo: end)

        XCTAssertEqual(app.state, .runningForeground, "app stopped responding after long press")
        XCTAssertTrue(app.buttons["Session menu"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testWindowDragModeKeyToggles() throws {
        let app = launchProbeApp()

        let captureButton = app.buttons["Physical input captured. Tap to release."]
        if captureButton.waitForExistence(timeout: 5) {
            captureButton.tap()
        }

        let dragKey = app.buttons["Window drag mode"]
        XCTAssertTrue(dragKey.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(dragKey.value as? String, "off")
        dragKey.tap()
        XCTAssertEqual(dragKey.value as? String, "on", app.debugDescription)
    }
}
