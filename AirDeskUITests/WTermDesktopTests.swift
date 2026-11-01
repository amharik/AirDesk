import XCTest

final class WTermDesktopTests: XCTestCase {
    private func launchDesktop(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AirDeskAutoDemo",
            "-AirDeskUITestProbe"
        ] + extraArguments
        app.launch()

        var sessionMenu = app.buttons["Session menu"]
        if !sessionMenu.waitForExistence(timeout: 90) {
            app.terminate()
            app.launch()
            sessionMenu = app.buttons["Session menu"]
        }
        XCTAssertTrue(sessionMenu.waitForExistence(timeout: 60), app.debugDescription)
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

    private func waitForProbe(_ app: XCUIApplication, containing text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if probeLabel(app).contains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    func testProductionTerminalUsesWTerm() throws {
        let app = launchDesktop()

        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.engine=wterm", timeout: 45),
            "probe=\(probeLabel(app))"
        )
        XCTAssertTrue(
            waitForProbe(app, containing: "wterm.core=ghostty", timeout: 45),
            "probe=\(probeLabel(app))"
        )
        XCTAssertTrue(
            waitForProbe(app, containing: "wterm.connected", timeout: 60),
            "probe=\(probeLabel(app))"
        )

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)
        let terminal = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialogue")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        terminal.tap()

        let keyboard = app.buttons["Show keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), app.debugDescription)
        keyboard.tap()

        sleep(2)
        app.typeText("a")

        XCTAssertTrue(
            waitForProbe(app, containing: "sendTerminalData ok", timeout: 20),
            "probe=\(probeLabel(app))"
        )
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "wterm-production-terminal"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReloadReplaysTerminalTranscript() throws {
        let app = launchDesktop()

        XCTAssertTrue(
            waitForProbe(app, containing: "wterm.connected", timeout: 60),
            "probe=\(probeLabel(app))"
        )
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)
        let terminal = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialogue")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        terminal.tap()

        let keyboard = app.buttons["Show keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), app.debugDescription)
        keyboard.tap()
        sleep(2)
        app.typeText("echo replay-marker\n")

        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.transcript.saved=", timeout: 90),
            "probe=\(probeLabel(app))"
        )

        let appleMenu = webView.buttons["Apple menu"]
        XCTAssertTrue(appleMenu.waitForExistence(timeout: 15), webView.debugDescription)
        appleMenu.tap()

        let restart = webView.buttons["Restart Desktop"]
        XCTAssertTrue(restart.waitForExistence(timeout: 15), webView.debugDescription)
        restart.tap()

        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.transcript.replayed=", timeout: 90),
            "probe=\(probeLabel(app))"
        )
    }

    func testLegacyTerminalRollbackAcceptsTyping() throws {
        let app = launchDesktop(extraArguments: ["-AirDeskLegacyTerminal"])

        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.engine=wanix-term", timeout: 60),
            "probe=\(probeLabel(app))"
        )
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)
        let terminal = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialogue")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        terminal.tap()

        let keyboard = app.buttons["Show keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), app.debugDescription)
        keyboard.tap()
        sleep(2)
        app.typeText("a")

        XCTAssertTrue(
            waitForProbe(app, containing: "sendTerminalData ok", timeout: 20),
            "probe=\(probeLabel(app))"
        )
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "legacy-terminal-rollback"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
