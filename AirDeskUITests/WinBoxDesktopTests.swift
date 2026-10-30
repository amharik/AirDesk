import XCTest

final class WinBoxDesktopTests: XCTestCase {
    private func launchDesktop() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AirDeskAutoDemo",
            "-AirDeskUITestProbe"
        ]
        app.launch()

        let sessionMenu = app.buttons["Session menu"]
        XCTAssertTrue(sessionMenu.waitForExistence(timeout: 150), app.debugDescription)
        sessionMenu.tap()

        let previewDesktop = app.buttons["Preview Desktop"]
        XCTAssertTrue(previewDesktop.waitForExistence(timeout: 15), app.debugDescription)
        previewDesktop.tap()
        XCTAssertTrue(app.staticTexts["Desktop Preview"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func probeLabel(_ app: XCUIApplication) -> String {
        app.staticTexts["JSLogProbe"].label
    }

    @discardableResult
    private func waitForProbe(_ app: XCUIApplication, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if probeLabel(app).contains(text) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return probeLabel(app).contains(text)
    }

    private func visibleWebView(in app: XCUIApplication) -> XCUIElement {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let webView = app.webViews.allElementsBoundByIndex.first(where: {
                $0.frame.width > 100 && $0.frame.height > 100
            }) {
                return webView
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return app.webViews.firstMatch
    }

    func testProductionDesktopDefaultsToWinBox() throws {
        let app = launchDesktop()
        XCTAssertTrue(waitForProbe(app, containing: "desktop.windowManager=winbox", timeout: 30), "probe=\(probeLabel(app))")

        let webView = visibleWebView(in: app)
        XCTAssertTrue(webView.exists, app.debugDescription)

        let terminal = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialogue")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)

        let welcome = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "AirDesk, web dialogue")
        ).firstMatch
        XCTAssertTrue(welcome.exists, webView.debugDescription)
        welcome.buttons["Close"].tap()
        XCTAssertTrue(welcome.waitForNonExistence(timeout: 10), "AirDesk was not closed")

        let originBeforeDrag = terminal.frame.origin
        let dragStart = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
        dragStart.press(forDuration: 0.3, thenDragTo: dragStart.withOffset(CGVector(dx: 60, dy: 40)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertNotEqual(terminal.frame.origin, originBeforeDrag, "terminal did not move")

        terminal.buttons["Maximize"].tap()
        let expanded = terminal.frame.width
        XCTAssertGreaterThan(expanded, webView.frame.width * 0.8, "terminal did not maximize")

        terminal.buttons["Maximize"].tap()
        let restored = terminal.frame.width
        XCTAssertLessThan(restored, expanded, "terminal did not restore")

        terminal.buttons["Close"].tap()
        XCTAssertTrue(terminal.waitForNonExistence(timeout: 10), "terminal was not closed")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "winbox-desktop"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
