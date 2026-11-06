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

    func testFabricPeerRequiresLeaseAndForwardsValidatedInput() async throws {
        let endpoint = StubLeaseEndpoint()
        let fabric = StubLeaseFabric(isConnected: true)
        let coordinator = makeCoordinator(fabric: fabric, endpoint: endpoint)
        coordinator.beginConnection(to: DisplayDevice(
            id: "test.wired",
            name: "Test display",
            detail: "Test",
            kind: .wired,
            mode: .extended
        ))
        try await waitUntilReady(coordinator)
        let baseline = endpoint.sentEvents.count

        coordinator.fabricPeerDidConnect("peer-1")
        XCTAssertEqual(coordinator.fabricControllerID, "iroh:peer-1")
        XCTAssertFalse(coordinator.fabricControllerHasLease)

        coordinator.fabricDidReceive(InputEvent.make(
            .keyDown,
            sessionId: "remote-session",
            generation: 1,
            seq: 1,
            key: "a"
        ))
        XCTAssertEqual(endpoint.sentEvents.count, baseline)

        coordinator.grantFabricControl()
        XCTAssertTrue(coordinator.fabricControllerHasLease)

        coordinator.fabricDidReceive(InputEvent.make(
            .keyDown,
            sessionId: "remote-session",
            generation: 1,
            seq: 2,
            key: "a"
        ))
        XCTAssertEqual(endpoint.sentEvents.count, baseline + 1)
        XCTAssertEqual(endpoint.sentEvents.last?.sessionId, coordinator.sessionId)
        XCTAssertEqual(endpoint.sentEvents.last?.generation, coordinator.sessionGeneration)
        XCTAssertEqual(endpoint.sentEvents.last?.key, "a")

        coordinator.fabricDidReceive(PackedMovementFrame(
            leaseEpochLow: 0,
            seq: 3,
            x: 0.3,
            y: 0.4
        ))
        XCTAssertEqual(endpoint.sentEvents.count, baseline + 2)
        XCTAssertEqual(endpoint.sentEvents.last?.type, .pointerMove)
        XCTAssertEqual(endpoint.sentEvents.last?.x ?? -1, 0.3, accuracy: 0.001)
        XCTAssertEqual(endpoint.sentEvents.last?.y ?? -1, 0.4, accuracy: 0.001)

        coordinator.fabricPeerDidDisconnect("peer-1")
        XCTAssertNil(coordinator.fabricControllerID)
        XCTAssertFalse(coordinator.fabricControllerHasLease)
        XCTAssertEqual(coordinator.activeInputControllerId, "local")
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

    private func makeCoordinator(
        fabric: (any IrohFabricInputRouting)? = nil,
        endpoint: StubLeaseEndpoint? = nil
    ) -> SessionCoordinator {
        let settings = AppSettings()
        settings.runtimeChoice = .wanixDesktop
        return SessionCoordinator(
            settings: settings,
            diagnostics: PerformanceMetrics(),
            display: DisplayCoordinator(),
            cast: CastSessionCoordinator(adapter: StubLeaseCastAdapter()),
            entitlements: EntitlementManager(),
            fabric: fabric,
            endpointFactory: { _ in endpoint ?? StubLeaseEndpoint() }
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
    private(set) var sentEvents: [InputEvent] = []

    func start(context: RuntimeContext) async throws {
        state = .ready
        onStateChange?(state)
    }

    func send(_ event: InputEvent) { sentEvents.append(event) }
    func sendControl(_ control: RuntimeControl) {}
    func stop() async {
        state = .stopped
    }
}

@MainActor
private final class StubLeaseFabric: IrohFabricInputRouting {
    let isConnected: Bool

    init(isConnected: Bool) {
        self.isConnected = isConnected
    }

    func sendInput(_ event: InputEvent) -> Bool { true }
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
