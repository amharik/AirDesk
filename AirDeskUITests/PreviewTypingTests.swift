import XCTest

final class PreviewTypingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AirDeskAutoDemo", "-AirDeskUITestProbe"]
    }

    func testTerminalAcceptsTypingInPreview() throws {
        app.launch()

        let sessionMenu = app.buttons["Session menu"]
        XCTAssertTrue(sessionMenu.waitForExistence(timeout: 150), app.debugDescription)
        sessionMenu.tap()

        let previewDesktop = app.buttons["Preview Desktop"]
        XCTAssertTrue(previewDesktop.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(previewDesktop.isEnabled, "Preview Desktop button is disabled")
        previewDesktop.tap()

        XCTAssertTrue(app.staticTexts["Desktop Preview"].waitForExistence(timeout: 15), app.debugDescription)

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)

        let terminal = webView.otherElements["Terminal"]
        if terminal.waitForExistence(timeout: 20) {
            terminal.tap()
        } else {
            webView.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.74)).tap()
        }

        let keyboard = app.buttons["Show keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), app.debugDescription)
        keyboard.tap()

        sleep(2)
        app.typeText("a")

        let probe = app.staticTexts["JSLogProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 8), app.debugDescription)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !probe.label.contains("sendTerminalData ok") {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(probe.label.contains("sendTerminalData ok"), "probe=\(probe.label)")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "preview-terminal-after-typing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
