import XCTest

final class RemoteTerminalTests: XCTestCase {
    private func launchRemoteDesktop(reconnect: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AirDeskAutoDemo",
            "-AirDeskUITestProbe",
            reconnect ? "-AirDeskRemoteSSHReconnectTest" : "-AirDeskRemoteSSHTest"
        ]
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
            if probeLabel(app).contains(text) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return probeLabel(app).contains(text)
    }

    private func probeCount(_ app: XCUIApplication, containing text: String) -> Int {
        probeLabel(app).components(separatedBy: text).count - 1
    }

    private func waitForProbeCount(
        _ app: XCUIApplication,
        containing text: String,
        minimum: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if probeCount(app, containing: text) >= minimum { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return probeCount(app, containing: text) >= minimum
    }

    private func terminalElement(_ app: XCUIApplication) -> XCUIElement {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)
        let terminal = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialogue")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        return terminal
    }

    private func focusTerminal(_ app: XCUIApplication) {
        let terminal = terminalElement(app)
        terminal.tap()
        let keyboard = app.buttons["Show keyboard"]
        if keyboard.waitForExistence(timeout: 5) {
            keyboard.tap()
        }
        sleep(2)
    }

    func testRemoteSSHTerminalAcceptsTypingAndResize() throws {
        let app = launchRemoteDesktop(reconnect: false)
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.engine=ssh", timeout: 45),
            "probe=\(probeLabel(app))"
        )
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.ready", timeout: 45),
            "probe=\(probeLabel(app))"
        )

        focusTerminal(app)
        app.typeText("remote-one\n")
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.input remote-one", timeout: 25),
            "probe=\(probeLabel(app))"
        )

        let resizesBeforeRotation = probeCount(app, containing: "terminal.ssh.resize")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(
            waitForProbeCount(
                app,
                containing: "terminal.ssh.resize",
                minimum: resizesBeforeRotation + 1,
                timeout: 20
            ),
            "probe=\(probeLabel(app))"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "remote-ssh-terminal"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRemoteSSHTerminalReconnectsAfterDrop() throws {
        let app = launchRemoteDesktop(reconnect: true)
        defer { app.terminate() }

        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.ready", timeout: 45),
            "probe=\(probeLabel(app))"
        )

        focusTerminal(app)
        app.typeText("remote-drop\n")
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.status Reconnecting to tester@127.0.0.1", timeout: 25),
            "probe=\(probeLabel(app))"
        )
        XCTAssertTrue(
            waitForProbeCount(app, containing: "terminal.ssh.ready", minimum: 2, timeout: 45),
            "probe=\(probeLabel(app))"
        )

        focusTerminal(app)
        app.typeText("remote-back\n")
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.input remote-back", timeout: 25),
            "probe=\(probeLabel(app))"
        )
    }
}
