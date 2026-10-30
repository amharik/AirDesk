import XCTest

final class WinBoxPreviewTests: XCTestCase {
    private func launchPreviewApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AirDeskAutoDemo",
            "-AirDeskUITestProbe",
            "-AirDeskWinBoxPreview"
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

    private func window(_ title: String, in webView: XCUIElement) -> XCUIElement {
        webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "\(title), web dialogue")
        ).firstMatch
    }

    func testWinBoxPreviewChromeAndLifecycle() throws {
        let app = launchPreviewApp()
        XCTAssertTrue(waitForProbe(app, containing: "wm ready", timeout: 20), "probe=\(probeLabel(app))")

        let webView = visibleWebView(in: app)
        XCTAssertTrue(webView.exists, app.debugDescription)

        let terminal = window("Terminal", in: webView)
        let notes = window("Notes", in: webView)
        let welcome = window("Welcome", in: webView)
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        XCTAssertTrue(notes.exists, webView.debugDescription)
        XCTAssertTrue(welcome.exists, webView.debugDescription)

        welcome.buttons["Minimize"].tap()
        XCTAssertTrue(waitForProbe(app, containing: "wm minimize welcome"), "probe=\(probeLabel(app))")

        notes.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.045)).tap()
        XCTAssertTrue(waitForProbe(app, containing: "wm focus notes"), "probe=\(probeLabel(app))")

        notes.buttons["Maximize"].tap()
        XCTAssertTrue(waitForProbe(app, containing: "wm maximize notes"), "probe=\(probeLabel(app))")
        notes.buttons["Maximize"].tap()
        XCTAssertTrue(waitForProbe(app, containing: "wm restore notes"), "probe=\(probeLabel(app))")

        let start = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.045))
        let end = start.withOffset(CGVector(dx: 90, dy: 45))
        start.press(forDuration: 0.4, thenDragTo: end)
        XCTAssertTrue(waitForProbe(app, containing: "wm move terminal"), "probe=\(probeLabel(app))")

        terminal.buttons["Close"].tap()
        XCTAssertTrue(waitForProbe(app, containing: "wm closed terminal"), "probe=\(probeLabel(app))")
        XCTAssertFalse(terminal.exists, terminal.debugDescription)
    }
}
