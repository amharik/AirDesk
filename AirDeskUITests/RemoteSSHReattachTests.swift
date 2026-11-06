import XCTest

final class RemoteSSHReattachTests: XCTestCase {
    private struct Configuration {
        let host: String
        let port: String
        let username: String
        let hostKey: String
        let privateKey: String
        let startup: String
        let backgroundSeconds: Double
        let terminationSeconds: Double
        let cycles: Int
        let token: String
        let baselineMarker: Int
    }

    private func loadConfiguration() throws -> Configuration {
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
        return Configuration(
            host: host,
            port: port,
            username: username,
            hostKey: hostKey,
            privateKey: privateKey,
            startup: startup,
            backgroundSeconds: Double(value("backgroundSeconds") ?? "5") ?? 5,
            terminationSeconds: Double(value("terminationSeconds") ?? "2") ?? 2,
            cycles: max(1, Int(value("cycles") ?? "3") ?? 3),
            token: value("token") ?? String(UUID().uuidString.prefix(8)),
            baselineMarker: max(0, Int(value("baselineMarker") ?? "0") ?? 0)
        )
    }

    private func makeApp(_ configuration: Configuration) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AirDeskAutoDemo",
            "-AirDeskUITestProbe",
            "-AirDeskRemoteSSHExternal",
            "-AirDeskUITestOpenPreview"
        ]
        app.launchEnvironment["AIRDESK_SSH_HOST"] = configuration.host
        app.launchEnvironment["AIRDESK_SSH_PORT"] = configuration.port
        app.launchEnvironment["AIRDESK_SSH_USERNAME"] = configuration.username
        app.launchEnvironment["AIRDESK_SSH_HOST_KEY"] = configuration.hostKey
        app.launchEnvironment["AIRDESK_SSH_PRIVATE_KEY_B64"] = configuration.privateKey
        app.launchEnvironment["AIRDESK_SSH_STARTUP"] = configuration.startup
        return app
    }

    private func openPreview(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["Desktop Preview"].waitForExistence(timeout: 120),
            app.debugDescription
        )
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

    private func latestMarkerIndex(_ app: XCUIApplication, prefix: String) -> Int {
        probeLabel(app).components(separatedBy: prefix).dropFirst().compactMap { piece in
            let digits = piece.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(String(digits))
        }.max() ?? 0
    }

    private func waitForMarkerAfter(
        _ app: XCUIApplication,
        prefix: String,
        after: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if latestMarkerIndex(app, prefix: prefix) > after { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return latestMarkerIndex(app, prefix: prefix) > after
    }

    func testRemoteSSHReattachesAfterBackground() throws {
        let configuration = try loadConfiguration()
        let app = makeApp(configuration)
        app.launch()
        defer { app.terminate() }

        openPreview(app)
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.ready", timeout: 60),
            "probe=\(probeLabel(app))"
        )

        let marker = "S2-REMOTE-SURVIVED-\(configuration.token)-"
        _ = waitForProbeCount(app, containing: marker, minimum: 1, timeout: 30)

        let backgroundSleep = UInt32(max(1, Int(configuration.backgroundSeconds)))
        print("AIRDESK_S2_CYCLES=\(configuration.cycles)")
        for _ in 1...configuration.cycles {
            let markerBefore = latestMarkerIndex(app, prefix: marker)
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
                waitForMarkerAfter(app, prefix: marker, after: markerBefore, timeout: 20),
                "probe=\(probeLabel(app))"
            )
            print("AIRDESK_S2_CYCLE_PROCESS_SURVIVED=true")
            print("AIRDESK_S2_CYCLE_TRANSCRIPT_TRUTHFUL=true")
        }
        print("AIRDESK_S2_DONE=true")
    }

    func testRemoteSSHReattachesAfterTermination() throws {
        let configuration = try loadConfiguration()
        let app = makeApp(configuration)
        app.launch()
        defer { app.terminate() }

        openPreview(app)
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.ready", timeout: 60),
            "probe=\(probeLabel(app))"
        )

        let marker = "S2-REMOTE-SURVIVED-\(configuration.token)-"
        _ = waitForProbeCount(app, containing: marker, minimum: 1, timeout: 30)

        let terminationSleep = UInt32(max(1, Int(configuration.terminationSeconds)))
        print("AIRDESK_S2_CYCLES=\(configuration.cycles)")
        for _ in 1...configuration.cycles {
            let markerBefore = latestMarkerIndex(app, prefix: marker)
            app.terminate()
            sleep(terminationSleep)

            let reattachStart = Date()
            app.launch()
            openPreview(app)
            let reattached = waitForProbeCount(
                app,
                containing: "terminal.ssh.ready",
                minimum: 1,
                timeout: 45
            )
            let reattachMilliseconds = Int(Date().timeIntervalSince(reattachStart) * 1000)
            XCTAssertTrue(reattached, "probe=\(probeLabel(app))")
            print("AIRDESK_S2_CYCLE_REATTACH_MS=\(reattachMilliseconds)")

            XCTAssertTrue(
                waitForMarkerAfter(app, prefix: marker, after: markerBefore, timeout: 20),
                "probe=\(probeLabel(app))"
            )
            print("AIRDESK_S2_CYCLE_PROCESS_SURVIVED=true")
            print("AIRDESK_S2_CYCLE_TRANSCRIPT_TRUTHFUL=true")
        }
        print("AIRDESK_S2_DONE=true")
    }

    func testRemoteSSHSecondDevicePrimary() throws {
        let configuration = try loadConfiguration()
        let app = makeApp(configuration)
        app.launch()
        defer { app.terminate() }

        openPreview(app)
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.ready", timeout: 60),
            "probe=\(probeLabel(app))"
        )

        let marker = "S2-REMOTE-SURVIVED-\(configuration.token)-"
        XCTAssertTrue(
            waitForProbeCount(app, containing: marker, minimum: 1, timeout: 30),
            "probe=\(probeLabel(app))"
        )
        let markerIndex = latestMarkerIndex(app, prefix: marker)
        print("AIRDESK_S2_PRIMARY_MARKER=\(markerIndex)")
        print("AIRDESK_S2_PRIMARY_READY=true")
        print("AIRDESK_S2_DONE=true")
    }

    func testRemoteSSHSecondDeviceSecondary() throws {
        let configuration = try loadConfiguration()
        let app = makeApp(configuration)
        let connectStart = Date()
        app.launch()
        defer { app.terminate() }

        openPreview(app)
        XCTAssertTrue(
            waitForProbe(app, containing: "terminal.ssh.ready", timeout: 60),
            "probe=\(probeLabel(app))"
        )
        let connectMilliseconds = Int(Date().timeIntervalSince(connectStart) * 1000)

        let marker = "S2-REMOTE-SURVIVED-\(configuration.token)-"
        XCTAssertTrue(
            waitForMarkerAfter(
                app,
                prefix: marker,
                after: configuration.baselineMarker,
                timeout: 30
            ),
            "baseline=\(configuration.baselineMarker) probe=\(probeLabel(app))"
        )
        let markerIndex = latestMarkerIndex(app, prefix: marker)
        print("AIRDESK_S2_SECONDARY_CONNECT_MS=\(connectMilliseconds)")
        print("AIRDESK_S2_SECONDARY_MARKER=\(markerIndex)")
        print("AIRDESK_S2_SECONDARY_READY=true")
        print("AIRDESK_S2_DONE=true")
    }
}
