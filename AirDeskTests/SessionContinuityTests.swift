import XCTest
@testable import AirDesk

final class SessionContinuityTests: XCTestCase {
    func testIdleIsHidden() {
        var model = SessionContinuityModel()
        let presentation = update(&model, phase: .idle, stage: .idle, runtime: .idle)

        XCTAssertFalse(presentation.isVisible)
        XCTAssertEqual(presentation.haptic, .none)
    }

    func testIdlePathChangeDoesNotHaptic() {
        var model = SessionContinuityModel()
        _ = update(
            &model,
            phase: .idle,
            stage: .idle,
            runtime: .idle,
            paths: [path(id: "direct-a", direct: true, relay: false, rtt: 12)]
        )
        let presentation = update(
            &model,
            phase: .idle,
            stage: .idle,
            runtime: .idle,
            paths: [path(id: "direct-b", direct: true, relay: false, rtt: 14)]
        )

        XCTAssertFalse(presentation.isVisible)
        XCTAssertEqual(presentation.haptic, .none)
    }

    func testConnectingShowsStageAndProgress() {
        var model = SessionContinuityModel()
        let presentation = update(
            &model,
            phase: .connecting,
            stage: .launching,
            runtime: .preparing
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.title, ConnectionStage.launching.title)
        XCTAssertEqual(presentation.detail, ConnectionStage.launching.detail)
        XCTAssertEqual(presentation.tone, .neutral)
        XCTAssertEqual(presentation.haptic, .none)
    }

    func testReadyDirectShowsLatencyAndCapabilities() {
        var model = SessionContinuityModel()
        let presentation = update(
            &model,
            paths: [path(id: "direct", direct: true, relay: false, rtt: 18)]
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.title, "Direct path")
        XCTAssertEqual(presentation.tone, .positive)
        XCTAssertEqual(presentation.latencyMilliseconds, 18)
        XCTAssertEqual(presentation.pathLabel, "Direct path")
        XCTAssertEqual(presentation.haptic, .sessionReady)
        XCTAssertTrue(presentation.detail.contains("Windows · Terminal · Files +3"))
    }

    func testReadyWithoutFabricPathUsesMeasuredLatency() {
        var model = SessionContinuityModel()
        let presentation = update(&model, latency: 27.4)

        XCTAssertEqual(presentation.title, "Session live")
        XCTAssertEqual(presentation.latencyMilliseconds, 27)
        XCTAssertEqual(presentation.haptic, .sessionReady)
    }

    func testRelayPathIsWarning() {
        var model = SessionContinuityModel()
        let presentation = update(
            &model,
            paths: [path(id: "relay", direct: false, relay: true, rtt: 42)]
        )

        XCTAssertEqual(presentation.title, "Relay path")
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertEqual(presentation.pathLabel, "Relay path")
        XCTAssertEqual(presentation.latencyMilliseconds, 42)
    }

    func testRelayToDirectMigrationIsPathUpgrade() {
        var model = SessionContinuityModel()
        _ = update(
            &model,
            paths: [path(id: "relay", direct: false, relay: true, rtt: 70)]
        )
        let presentation = update(
            &model,
            paths: [path(id: "direct", direct: true, relay: false, rtt: 12)]
        )

        XCTAssertEqual(presentation.haptic, .pathUpgraded)
        XCTAssertTrue(presentation.detail.contains("Upgraded from relay to direct"))
        XCTAssertEqual(presentation.latencyMilliseconds, 12)
    }

    func testDirectToRelayMigrationIsPathDegrade() {
        var model = SessionContinuityModel()
        _ = update(
            &model,
            paths: [path(id: "direct", direct: true, relay: false, rtt: 12)]
        )
        let presentation = update(
            &model,
            paths: [path(id: "relay", direct: false, relay: true, rtt: 95)]
        )

        XCTAssertEqual(presentation.haptic, .pathDegraded)
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertTrue(presentation.detail.contains("Failover to relay"))
    }

    func testSameTransportPathIDChangeReportsMigration() {
        var model = SessionContinuityModel()
        _ = update(
            &model,
            paths: [path(id: "direct-a", direct: true, relay: false, rtt: 12)]
        )
        let presentation = update(
            &model,
            paths: [path(id: "direct-b", direct: true, relay: false, rtt: 14)]
        )

        XCTAssertEqual(presentation.haptic, .pathChanged)
        XCTAssertEqual(presentation.title, "Direct path")
        XCTAssertTrue(presentation.detail.contains("Path changed to direct path"))
    }

    func testStablePathDoesNotRepeatSemanticHaptic() {
        var model = SessionContinuityModel()
        let directPath = path(id: "direct", direct: true, relay: false, rtt: 12)
        let first = update(&model, paths: [directPath])
        let second = update(&model, paths: [directPath])

        XCTAssertEqual(first.haptic, .sessionReady)
        XCTAssertEqual(second.haptic, .none)
        XCTAssertEqual(second.title, "Direct path")
    }

    func testRecoveryPresentationUsesAttempts() {
        var model = SessionContinuityModel()
        _ = update(
            &model,
            paths: [path(id: "direct", direct: true, relay: false, rtt: 12)]
        )
        let presentation = update(
            &model,
            runtime: .recovering,
            attempts: 1,
            paths: [path(id: "direct", direct: true, relay: false, rtt: 12)]
        )

        XCTAssertEqual(presentation.title, "Restoring workspace")
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertEqual(presentation.haptic, .recovery)
        XCTAssertTrue(presentation.detail.contains("Attempt 1 of 3"))
        XCTAssertTrue(presentation.detail.contains("direct path"))
    }

    func testFailurePresentationUsesErrorAndHaptic() {
        var model = SessionContinuityModel()
        _ = update(&model, phase: .connecting, stage: .pairing, runtime: .preparing)
        let presentation = update(
            &model,
            phase: .failed,
            stage: .idle,
            runtime: .failed,
            error: "The display stopped responding."
        )

        XCTAssertEqual(presentation.title, "Connection interrupted")
        XCTAssertEqual(presentation.tone, .critical)
        XCTAssertEqual(presentation.haptic, .failure)
        XCTAssertTrue(presentation.detail.contains("The display stopped responding."))
    }

    private func update(
        _ model: inout SessionContinuityModel,
        phase: SessionPhase = .ready,
        stage: ConnectionStage = .ready,
        runtime: RuntimeState = .ready,
        capabilities: RuntimeCapabilities = .wanixDesktop,
        attempts: Int = 0,
        maximumAttempts: Int = 3,
        error: String? = nil,
        device: String? = "Studio",
        paths: [IrohFabricPath] = [],
        latency: Double = 0
    ) -> SessionContinuityPresentation {
        model.update(
            phase: phase,
            stage: stage,
            runtimeState: runtime,
            capabilities: capabilities,
            recoveryAttempts: attempts,
            recoveryMaximumAttempts: maximumAttempts,
            lastError: error,
            selectedDeviceName: device,
            paths: paths,
            measuredLatencyMilliseconds: latency
        )
    }

    private func path(
        id: String,
        direct: Bool,
        relay: Bool,
        rtt: UInt64
    ) -> IrohFabricPath {
        IrohFabricPath(
            id: id,
            remoteAddress: "127.0.0.1:4433",
            isSelected: true,
            isDirectIP: direct,
            isRelay: relay,
            rttMs: rtt
        )
    }
}
