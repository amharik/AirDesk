import XCTest

final class RemoteSSHReattachTests: XCTestCase {
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

    func testRemoteSSHReattachesAfterBackground() throws {
        let defaults = UserDefaults(suiteName: "com.airdesk.realsshsmoke")
        let environment = ProcessInfo.processInfo.environment
        func value(_ key: String) -> String? {
            defaults?.string(forKey: key) ?? environment[key]
        }
        guard let host = value("host"), !host.isEmpty,
              let port = value("port"), !port.isEmpty,
              let username = value("username"), !username.isEmpty,
              let hostKey = value("hostKey"), !hostKey.isEmpty,
              let privateKey = value("privateKey"), !privateKey.isEmpty,
              let startup = value("startup"), !startup.isEmpty else {
            throw XCTSkip("Set the com.airdesk.realsshsmoke defaults to run the reattach test.")
        }

        let backgroundSeconds = Double(value("backgroundSeconds") ?? "5") ?? 5
        let backgroundSleep = UInt32(max(1, Int(backgroundSeconds)))
        let cycles = max(1, Int(value("cycles") ?? "3") ?? 3)
        let token = value("token") ?? String(UUID().uuidString.prefix(8))

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
        app.launchEnvironment["AIRDESK_SSH_STARTUP"] = startup
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
            waitForProbe(app, containing: "terminal.ssh.ready", timeout: 60),
            "probe=\(probeLabel(app))"
        )

        print("AIRDESK_S2_CYCLES=\(cycles)")
        for cycle in 1...cycles {
            focusTerminal(app)
            let marker = "S2-REMOTE-SURVIVED-\(token)-\(cycle)"
            let armed = "S2-ARMED-\(token)-\(cycle)"
            let remoteDelay = max(2, Int(backgroundSeconds) - 1)
            app.typeText("(sleep \(remoteDelay); echo \(marker)) & echo \(armed)\n")
            XCTAssertTrue(
                waitForProbe(app, containing: armed, timeout: 20),
                "probe=\(probeLabel(app))"
            )

            let readyBefore = probeCount(app, containing: "terminal.ssh.ready")
            XCUIDevice.shared.press(.home)
            sleep(backgroundSleep)

            let reattachStart = Date()
            app.activate()
            let reattached = waitForProbeCount(
                app,
                containing: "terminal.ssh.ready",
                minimum: readyBefore + 1,
                timeout: 45
            )
            let reattachMilliseconds = Int(Date().timeIntervalSince(reattachStart) * 1000)
            XCTAssertTrue(reattached, "probe=\(probeLabel(app))")
            print("AIRDESK_S2_CYCLE_REATTACH_MS=\(reattachMilliseconds)")

            XCTAssertTrue(
                waitForProbe(app, containing: marker, timeout: 15),
                "probe=\(probeLabel(app))"
            )
            print("AIRDESK_S2_CYCLE_PROCESS_SURVIVED=true")
            print("AIRDESK_S2_CYCLE_TRANSCRIPT_TRUTHFUL=true")
        }
        print("AIRDESK_S2_DONE=true")
    }
}
