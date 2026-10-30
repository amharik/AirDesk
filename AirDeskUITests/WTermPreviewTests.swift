import XCTest

final class WTermPreviewTests: XCTestCase {
    private func launchPreviewApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AirDeskAutoDemo",
            "-AirDeskUITestProbe",
            "-AirDeskWTermPreview"
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

    func testWTermBashSelfTest() throws {
        let app = launchPreviewApp()
        XCTAssertTrue(waitForProbe(app, containing: "wterm ready bash", timeout: 30), "probe=\(probeLabel(app))")

        let webView = visibleWebView(in: app)
        XCTAssertTrue(webView.exists, app.debugDescription)

        XCTAssertTrue(webView.buttons["Run self test"].waitForExistence(timeout: 10), webView.debugDescription)
        XCTAssertTrue(waitForProbe(app, containing: "wterm self-test ok", timeout: 20), "probe=\(probeLabel(app))")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "wterm-preview-self-test"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
