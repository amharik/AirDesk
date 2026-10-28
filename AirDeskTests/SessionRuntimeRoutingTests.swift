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
        transport.send(event)

        XCTAssertEqual(endpoint.sentEvents, [event])
    }

    func testEndpointRouteIgnoresInputBeforeReady() {
        let endpoint = StubRuntimeEndpoint(state: .loading)
        let transport = SessionInputTransport()
        transport.route = .endpoint
        transport.endpoint = endpoint
        let event = InputEvent.make(.keyDown, sessionId: "ads-test", seq: 1, key: "a")

        XCTAssertFalse(transport.isAvailable)
        transport.send(event)

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

        XCTAssertTrue(transport.isAvailable)
        transport.send(event)

        XCTAssertEqual(adapter.sentEvents, [event])
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
}
