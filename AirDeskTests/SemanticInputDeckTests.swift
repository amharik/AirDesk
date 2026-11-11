import XCTest
@testable import AirDesk

final class SemanticInputDeckTests: XCTestCase {
    func testContextModeMapsDisplayModesAndDisconnectedState() {
        XCTAssertEqual(SemanticContextMode.resolve(sessionMode: .extended, isSessionReady: true), .a)
        XCTAssertEqual(SemanticContextMode.resolve(sessionMode: .mirrored, isSessionReady: true), .b)
        XCTAssertEqual(SemanticContextMode.resolve(sessionMode: .cast, isSessionReady: true), .c)
        XCTAssertEqual(SemanticContextMode.resolve(sessionMode: .preview, isSessionReady: true), .d)
        XCTAssertEqual(SemanticContextMode.resolve(sessionMode: .extended, isSessionReady: false), .d)
    }

    func testOSC133ParserTracksPromptRunningAndExitAcrossChunks() {
        var parser = OSC133Parser()

        XCTAssertEqual(parser.consume(Data("\u{1B}]133;A\u{07}".utf8)), [.prompt])
        XCTAssertEqual(parser.phase, .prompt)

        let start = Array("\u{1B}]133;C\u{1B}\\".utf8)
        XCTAssertTrue(parser.consume(Data(start.prefix(4))).isEmpty)
        XCTAssertEqual(parser.consume(Data(start.dropFirst(4))), [.running])
        XCTAssertEqual(parser.phase, .running)

        XCTAssertEqual(parser.consume(Data("\u{1B}]133;D;7\u{07}".utf8)), [.finished(exitCode: 7)])
        XCTAssertEqual(parser.phase, .finished)
    }

    func testOSC133ParserIgnoresOtherAndMalformedSequences() {
        var parser = OSC133Parser()

        XCTAssertTrue(parser.consume(Data("plain output".utf8)).isEmpty)
        XCTAssertTrue(parser.consume(Data("\u{1B}]8;;https://example.com\u{07}".utf8)).isEmpty)
        XCTAssertTrue(parser.consume(Data("\u{1B}]133;Z\u{07}".utf8)).isEmpty)
        XCTAssertEqual(parser.phase, .unknown)

        XCTAssertEqual(parser.consume(Data("\u{1B}]133;B\u{07}".utf8)), [.input])
        XCTAssertEqual(parser.phase, .input)
    }

    func testAuthorizationRequiresCapabilityModeAndLocalLease() {
        var context = makeContext()
        XCTAssertNil(context.denial(for: .escape))
        XCTAssertNil(context.denial(for: .dock))

        context.activeControllerId = nil
        XCTAssertEqual(context.denial(for: .escape), .inputLeaseMissing)
        XCTAssertNil(context.denial(for: .diagnostics))

        context = makeContext(mode: .b)
        XCTAssertEqual(context.denial(for: .dock), .modeNotSupported(.b))

        context = makeContext(capabilities: [.sessionRecovery])
        XCTAssertEqual(context.denial(for: .returnKey), .capabilityMissing(.desktopControl))

        context = makeContext(isSessionReady: false)
        XCTAssertEqual(context.denial(for: .escape), .sessionNotReady)
        XCTAssertNil(context.denial(for: .reconnect))
    }

    func testLayoutUsesModeAndTerminalPhase() {
        let running = SemanticInputDeckLayout.resolve(context: makeContext(phase: .running))
        XCTAssertEqual(running.mode, .a)
        XCTAssertTrue(running.actions.contains(.interrupt))
        XCTAssertTrue(running.actions.contains(.dock))
        XCTAssertTrue(running.showsKeyboard)
        XCTAssertTrue(running.gestureHint.contains("MOVE WINDOWS"))

        let mirrored = SemanticInputDeckLayout.resolve(context: makeContext(mode: .b, phase: .prompt))
        XCTAssertFalse(mirrored.actions.contains(.dock))
        XCTAssertTrue(mirrored.actions.contains(.clearScreen))
        XCTAssertFalse(mirrored.gestureHint.contains("MOVE WINDOWS"))

        let disconnected = SemanticInputDeckLayout.resolve(context: makeContext(isSessionReady: false))
        XCTAssertEqual(disconnected.mode, .d)
        XCTAssertEqual(disconnected.actions, [.reconnect, .diagnostics, .endSession])
        XCTAssertFalse(disconnected.showsKeyboard)
        XCTAssertFalse(disconnected.showsTrackpad)
    }

    private func makeContext(
        mode: SemanticContextMode? = nil,
        phase: TerminalCommandPhase = .prompt,
        capabilities: Set<SemanticInputCapability> = [
            .sessionRecovery, .desktopControl, .keyboard, .pointer, .windowManagement
        ],
        isSessionReady: Bool = true
    ) -> SemanticInputAuthorizationContext {
        SemanticInputAuthorizationContext(
            mode: mode ?? (isSessionReady ? .a : .d),
            terminalPhase: phase,
            availableCapabilities: capabilities,
            activeControllerId: isSessionReady ? "local" : nil,
            localControllerId: "local",
            leaseEpoch: isSessionReady ? 1 : 0,
            isSessionReady: isSessionReady
        )
    }
}
