import XCTest
@testable import AirDesk

@MainActor
final class SessionRuntimeRoutingTests: XCTestCase {
    func testEndpointRouteForwardsInputWhenReady() {
        let endpoint = StubRuntimeEndpoint(state: .ready)
        let transport = SessionInputTransport()
        transport.route = .endpoint
        transport.endpoint = endpoint
        let event = InputEvent.make(.keyDown, sessionId: "ads-test", seq: 1, key: "a")

        XCTAssertTrue(transport.isAvailable)
        transport.send(event, on: .reliableEdges)

        XCTAssertEqual(endpoint.sentEvents, [event])
    }

    func testEndpointRouteIgnoresInputBeforeReady() {
        let endpoint = StubRuntimeEndpoint(state: .loading)
        let transport = SessionInputTransport()
        transport.route = .endpoint
        transport.endpoint = endpoint
        let event = InputEvent.make(.keyDown, sessionId: "ads-test", seq: 1, key: "a")

        XCTAssertFalse(transport.isAvailable)
        transport.send(event, on: .reliableEdges)

        XCTAssertTrue(endpoint.sentEvents.isEmpty)
    }

    func testCastRouteForwardsInputAfterConnection() async throws {
        let adapter = StubCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)
        let transport = SessionInputTransport()
        transport.route = .cast
        transport.cast = coordinator
        let event = InputEvent.make(.pointerMove, sessionId: "ads-test", seq: 2, x: 0.5, y: 0.5)

        XCTAssertFalse(transport.isAvailable)
        try await coordinator.connect(to: .demoStudio)
        adapter.emitReady(sessionId: "ads-test", generation: 0)

        XCTAssertTrue(transport.isAvailable)
        transport.send(event, on: .movement)

        XCTAssertEqual(adapter.sentEvents, [event])
    }

    func testFabricRouteForwardsInputWhenConnected() {
        let endpoint = StubRuntimeEndpoint(state: .ready)
        let fabric = StubFabricRouting(isConnected: true)
        let transport = SessionInputTransport()
        transport.route = .endpoint
        transport.endpoint = endpoint
        transport.fabric = fabric
        transport.forwardsToFabric = true
        let event = InputEvent.make(.keyDown, sessionId: "ads-test", seq: 1, key: "a")

        transport.send(event, on: .reliableEdges)

        XCTAssertEqual(fabric.sentEvents, [event])
        XCTAssertTrue(endpoint.sentEvents.isEmpty)
    }

    func testFabricRouteFallsBackWhenDisconnected() {
        let endpoint = StubRuntimeEndpoint(state: .ready)
        let fabric = StubFabricRouting(isConnected: false)
        let transport = SessionInputTransport()
        transport.route = .endpoint
        transport.endpoint = endpoint
        transport.fabric = fabric
        transport.forwardsToFabric = true
        let event = InputEvent.make(.keyDown, sessionId: "ads-test", seq: 1, key: "a")

        transport.send(event, on: .reliableEdges)

        XCTAssertTrue(fabric.sentEvents.isEmpty)
        XCTAssertEqual(endpoint.sentEvents, [event])
    }

    func testTransportRejectsInputOnTheWrongChannel() {
        let endpoint = StubRuntimeEndpoint(state: .ready)
        let transport = SessionInputTransport()
        transport.route = .endpoint
        transport.endpoint = endpoint

        transport.send(
            InputEvent.make(.pointerMove, sessionId: "ads-test", seq: 1, x: 0.5, y: 0.5),
            on: .reliableEdges
        )
        transport.send(
            InputEvent.make(.keyDown, sessionId: "ads-test", seq: 2, key: "a"),
            on: .movement
        )

        XCTAssertTrue(endpoint.sentEvents.isEmpty)
    }
}

@MainActor
private final class StubRuntimeEndpoint: RuntimeEndpoint {
    let location: RuntimeLocation = .phone
    let identifier = "Stub runtime"
    var state: RuntimeState
    let capabilities: RuntimeCapabilities = .wanixDesktop
    var onStateChange: ((RuntimeState) -> Void)?
    private(set) var sentEvents: [InputEvent] = []

    init(state: RuntimeState) {
        self.state = state
    }

    var acceptsInput: Bool {
        state == .ready
    }

    func start(context: RuntimeContext) async throws {}
    func send(_ event: InputEvent) { sentEvents.append(event) }
    func sendControl(_ control: RuntimeControl) {}
    func stop() async {}
}

@MainActor
private final class StubFabricRouting: IrohFabricInputRouting {
    let isConnected: Bool
    private(set) var sentEvents: [InputEvent] = []

    init(isConnected: Bool) {
        self.isConnected = isConnected
    }

    func sendInput(_ event: InputEvent) -> Bool {
        sentEvents.append(event)
        return true
    }
}

@MainActor
private final class StubCastAdapter: GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = true
    weak var delegate: (any GoogleCastAdapterDelegate)?
    private(set) var discoveredDevices: [CastDevice] = []
    private(set) var sentEvents: [InputEvent] = []

    func startDiscovery() {}
    func stopDiscovery() {}

    func connect(to device: CastDevice) async throws {
        delegate?.castAdapter(self, didChange: .connected)
    }

    func disconnect() {
        delegate?.castAdapter(self, didChange: .idle)
    }

    func send(_ event: InputEvent) {
        sentEvents.append(event)
    }

    func sendControl(_ message: CastControlMessage) {}

    func emitReady(sessionId: String, generation: Int) {
        guard let ready = try? CastControlMessage.ready(
            sessionId: sessionId,
            generation: generation,
            width: 1920,
            height: 1080,
            persistence: "indexeddb",
            lastAcceptedInputSeq: 0
        ).validated() else { return }
        delegate?.castAdapter(self, didReceive: ready)
    }
}
