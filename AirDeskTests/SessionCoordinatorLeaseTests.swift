import XCTest
@testable import AirDesk

@MainActor
final class SessionCoordinatorLeaseTests: XCTestCase {
    func testConnectionOwnsLeaseAndRejectsStaleEpoch() async throws {
        let coordinator = makeCoordinator()
        coordinator.beginConnection(to: .previewDevice)
        try await waitUntilReady(coordinator)

        XCTAssertEqual(coordinator.leaseEpoch, 1)
        XCTAssertEqual(coordinator.activeInputControllerId, "local")
        XCTAssertEqual(coordinator.negotiatedInputProtocol.version, .legacy)

        let event = InputEvent.make(
            .pointerDown,
            sessionId: coordinator.sessionId,
            generation: coordinator.sessionGeneration,
            seq: 100,
            x: 0.25,
            y: 0.75,
            button: 0
        )
        XCTAssertNoThrow(try coordinator.validateIncomingEdge(
            event,
            controllerId: "local",
            leaseEpoch: coordinator.leaseEpoch
        ))

        let stale = InputEvent.make(
            .pointerUp,
            sessionId: coordinator.sessionId,
            generation: coordinator.sessionGeneration,
            seq: 101,
            x: 0.25,
            y: 0.75,
            button: 0
        )
        XCTAssertThrowsError(try coordinator.validateIncomingEdge(
            stale,
            controllerId: "local",
            leaseEpoch: 0
        )) { error in
            XCTAssertEqual(error as? InputLeaseError, .epochRejected(currentEpoch: 1))
        }

        let movement = PackedMovementFrame(leaseEpochLow: 1, seq: 5, x: 0.4, y: 0.6)
        XCTAssertNotNil(coordinator.acceptIncomingMovement(
            movement,
            controllerId: "local",
            leaseEpoch: 1
        ))
        XCTAssertNil(coordinator.acceptIncomingMovement(
            PackedMovementFrame(leaseEpochLow: 0, seq: 6, x: 0.4, y: 0.6),
            controllerId: "local",
            leaseEpoch: 1
        ))

        coordinator.disconnect()
        XCTAssertEqual(coordinator.leaseEpoch, 0)
        XCTAssertNil(coordinator.activeInputControllerId)
    }

    func testReconnectResetsLeaseEpochWithNewGeneration() async throws {
        let coordinator = makeCoordinator()
        coordinator.beginConnection(to: .previewDevice)
        try await waitUntilReady(coordinator)
        let firstGeneration = coordinator.sessionGeneration
        let firstSessionId = coordinator.sessionId

        coordinator.disconnect()
        coordinator.beginConnection(to: .previewDevice)
        try await waitUntilReady(coordinator)

        XCTAssertGreaterThan(coordinator.sessionGeneration, firstGeneration)
        XCTAssertNotEqual(coordinator.sessionId, firstSessionId)
        XCTAssertEqual(coordinator.leaseEpoch, 1)

        let old = InputEvent.make(
            .pointerDown,
            sessionId: firstSessionId,
            generation: firstGeneration,
            seq: 1,
            x: 0.5,
            y: 0.5,
            button: 0
        )
        XCTAssertThrowsError(try coordinator.validateIncomingEdge(
            old,
            controllerId: "local",
            leaseEpoch: 1
        ))
    }

    private func makeCoordinator() -> SessionCoordinator {
        let settings = AppSettings()
        settings.runtimeChoice = .wanixDesktop
        return SessionCoordinator(
            settings: settings,
            diagnostics: PerformanceMetrics(),
            display: DisplayCoordinator(),
            cast: CastSessionCoordinator(adapter: StubLeaseCastAdapter()),
            entitlements: EntitlementManager(),
            endpointFactory: { _ in StubLeaseEndpoint() }
        )
    }

    private func waitUntilReady(_ coordinator: SessionCoordinator) async throws {
        for _ in 0..<120 {
            if coordinator.phase == .ready { return }
            if coordinator.phase == .failed {
                XCTFail("Session failed: \(coordinator.lastError ?? "unknown")")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Session did not become ready")
    }
}

@MainActor
private final class StubLeaseEndpoint: RuntimeEndpoint {
    let location: RuntimeLocation = .phone
    let identifier = "Stub"
    private(set) var state: RuntimeState = .ready
    let capabilities: RuntimeCapabilities = .wanixDesktop
    var onStateChange: ((RuntimeState) -> Void)?

    func start(context: RuntimeContext) async throws {
        state = .ready
        onStateChange?(state)
    }

    func send(_ event: InputEvent) {}
    func sendControl(_ control: RuntimeControl) {}
    func stop() async {
        state = .stopped
    }
}

@MainActor
private final class StubLeaseCastAdapter: GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = true
    weak var delegate: (any GoogleCastAdapterDelegate)?
    private(set) var discoveredDevices: [CastDevice] = []

    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to device: CastDevice) async throws {}
    func disconnect() {}
    func send(_ event: InputEvent) {}
    func sendControl(_ message: CastControlMessage) {}
}
