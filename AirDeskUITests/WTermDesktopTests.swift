import XCTest

final class WTermDesktopTests: XCTestCase {
    private func element(_ app: XCUIApplication, label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label))
            .firstMatch
    }

    private func launchDesktop(
        extraArguments: [String] = [],
        openPreviewDirectly: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AirDeskAutoDemo",
            "-AirDeskUITestProbe"
        ] + extraArguments
        if openPreviewDirectly {
            app.launchArguments.append("-AirDeskUITestOpenPreview")
        }
        app.launch()

        if !openPreviewDirectly {
            var sessionMenu = element(app, label: "Session menu")
            if !sessionMenu.waitForExistence(timeout: 90) {
                app.terminate()
                app.launch()
                sessionMenu = element(app, label: "Session menu")
            }
            XCTAssertTrue(sessionMenu.waitForExistence(timeout: 60), app.debugDescription)
            sessionMenu.tap()

            let previewDesktop = element(app, label: "Preview Desktop")
            XCTAssertTrue(previewDesktop.waitForExistence(timeout: 15), app.debugDescription)
            previewDesktop.tap()
        }

        XCTAssertTrue(app.staticTexts["Desktop Preview"].waitForExistence(timeout: 30), app.debugDescription)
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

    private func lastResizeSize(_ app: XCUIApplication) -> (cols: Int, rows: Int)? {
        let pattern = try! NSRegularExpression(pattern: #"wterm\.resize (\d+)x(\d+)"#)
        let label = probeLabel(app)
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        guard let match = pattern.matches(in: label, range: range).last else { return nil }
        guard
            let colsRange = Range(match.range(at: 1), in: label),
            let rowsRange = Range(match.range(at: 2), in: label),
            let cols = Int(label[colsRange]),
            let rows = Int(label[rowsRange])
        else { return nil }
        return (cols, rows)
    }

    private func waitForWindowSizeChange(
        _ app: XCUIApplication,
        from oldSize: (cols: Int, rows: Int)?,
        timeout: TimeInterval
    ) -> (cols: Int, rows: Int)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let size = lastResizeSize(app),
               size.cols != oldSize?.cols || size.rows != oldSize?.rows {
                return size
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return lastResizeSize(app)
    }

    private func focusTerminal(_ app: XCUIApplication) -> XCUIElement {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)
        let terminal = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialog")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        let terminalText = terminal.textViews.firstMatch
        if terminalText.exists {
            terminalText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        let keyboard = app.buttons["Show keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), app.debugDescription)
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(2)
        return terminal
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
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialog")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let keyboard = app.buttons["Show keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), app.debugDescription)
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

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
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialog")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let keyboard = app.buttons["Show keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), app.debugDescription)
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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

    func testLocalWindowSizeReachesShell() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launchDesktop(openPreviewDirectly: true)
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        XCTAssertTrue(
            waitForProbe(app, containing: "wterm.connected", timeout: 60),
            "probe=\(probeLabel(app))"
        )

        guard let initial = waitForWindowSizeChange(app, from: nil, timeout: 15) else {
            return XCTFail("The terminal never reported a window size. probe=\(probeLabel(app))")
        }
        XCTAssertTrue(
            waitForProbe(app, containing: "kernel.resize.ok=true", timeout: 20),
            "expected the initial size to reach the shell bridge; probe=\(probeLabel(app))"
        )

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25), app.debugDescription)
        let terminal = webView.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialog")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        for title in ["AirDesk, web dialog", "Finder, web dialog"] {
            let window = webView.otherElements.matching(
                NSPredicate(format: "label BEGINSWITH %@", title)
            ).firstMatch
            if window.exists {
                let close = window.buttons["Close"]
                if close.exists {
                    close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    sleep(1)
                }
            }
        }
        let maximize = terminal.buttons["Maximize"]
        XCTAssertTrue(maximize.waitForExistence(timeout: 10), terminal.debugDescription)
        maximize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        guard let resized = waitForWindowSizeChange(app, from: initial, timeout: 25) else {
            return XCTFail("The terminal never reported a resized window. probe=\(probeLabel(app))")
        }
        XCTAssertNotEqual(resized.cols, initial.cols, "expected a different terminal width; probe=\(probeLabel(app))")
        XCTAssertTrue(
            waitForProbe(app, containing: "kernel.resize.ok=true", timeout: 20),
            "expected the resized terminal to reach the shell bridge; probe=\(probeLabel(app))"
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
            NSPredicate(format: "label BEGINSWITH %@", "Terminal, web dialog")
        ).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20), webView.debugDescription)
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let keyboard = app.buttons["Show keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), app.debugDescription)
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
