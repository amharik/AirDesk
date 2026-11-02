import XCTest

final class RealSSHTerminalTests: XCTestCase {
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

    private func focusTerminal(_ app: XCUIApplication) {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)
        let terminal = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialog")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        terminal.tap()
        let keyboard = app.buttons["Show keyboard"]
        if keyboard.waitForExistence(timeout: 5) {
            keyboard.tap()
        }
        sleep(2)
    }

    func testRealOpenSSHTerminalAcceptsTyping() throws {
        let defaults = UserDefaults(suiteName: "com.airdesk.realsshsmoke")
        let environment = ProcessInfo.processInfo.environment
        func value(_ key: String) -> String? {
            defaults?.string(forKey: key) ?? environment[key]
        }
        guard let host = value("host"), !host.isEmpty,
              let port = value("port"), !port.isEmpty,
              let username = value("username"), !username.isEmpty,
              let hostKey = value("hostKey"), !hostKey.isEmpty,
              let privateKey = value("privateKey"), !privateKey.isEmpty else {
            throw XCTSkip("Set the com.airdesk.realsshsmoke defaults to run the real OpenSSH smoke test.")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-AirDeskAutoDemo",
            "-AirDeskUITestProbe",
            "-AirDeskRemoteSSHExternal"
        ]
        app.launchEnvironment["AIRDESK_SSH_HOST"] = host
        app.launchEnvironment["AIRDESK_SSH_PORT"] = port
        app.launchEnvironment["AIRDESK_SSH_USERNAME"] = username
        app.launchEnvironment["AIRDESK_SSH_HOST_KEY"] = hostKey
        app.launchEnvironment["AIRDESK_SSH_PRIVATE_KEY_B64"] = privateKey
        app.launchEnvironment["AIRDESK_SSH_STARTUP"] = value("startup") ?? ""
        app.launch()
        defer { app.terminate() }

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

        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.engine=ssh", timeout: 45),
            "probe=\(probeLabel(app))"
        )
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.ready", timeout: 60),
            "probe=\(probeLabel(app))"
        )

        focusTerminal(app)
        app.typeText("real-openssh\n")
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.input real-openssh", timeout: 25),
            "probe=\(probeLabel(app))"
        )
    }
}
