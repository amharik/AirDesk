import XCTest
@testable import AirDesk

@MainActor
final class CastRuntimeEndpointTests: XCTestCase {
    func testStartSendsSessionStartAndWaitsForReady() async throws {
        let adapter = EndpointCastAdapter()
        let cast = CastSessionCoordinator(adapter: adapter)
        let endpoint = CastRuntimeEndpoint(cast: cast)
        try await cast.connect(to: .demoStudio)

        try await endpoint.start(context: context(generation: 4))

        XCTAssertEqual(endpoint.location, .castReceiver)
        XCTAssertEqual(adapter.sentControls.first?.type, .sessionStart)
        XCTAssertEqual(adapter.sentControls.first?.generation, 4)
        XCTAssertEqual(adapter.sentControls.first?.protocolInfo, CastProtocolVersions())
        XCTAssertEqual(endpoint.state, .ready)
        XCTAssertTrue(endpoint.acceptsInput)
        XCTAssertEqual(endpoint.identifier, "Cast 1")
        XCTAssertTrue(endpoint.capabilities.desktopWindows)
        XCTAssertTrue(endpoint.capabilities.persistentStorage)
    }

    func testReceiverErrorFailsStart() async throws {
        let adapter = EndpointCastAdapter()
        adapter.failOnStart = true
        let cast = CastSessionCoordinator(adapter: adapter)
        let endpoint = CastRuntimeEndpoint(cast: cast)
        try await cast.connect(to: .demoStudio)

        do {
            try await endpoint.start(context: context(generation: 1))
            XCTFail("Expected start to fail")
        } catch {
            XCTAssertEqual(error as? CastProtocolError, .receiverError("unsupportedVersion"))
        }

        XCTAssertEqual(endpoint.state, .failed)
        XCTAssertFalse(endpoint.acceptsInput)
    }

    func testInputWithStaleGenerationIsDropped() async throws {
        let adapter = EndpointCastAdapter()
        let cast = CastSessionCoordinator(adapter: adapter)
        let endpoint = CastRuntimeEndpoint(cast: cast)
        try await cast.connect(to: .demoStudio)
        try await endpoint.start(context: context(generation: 7))

        endpoint.send(InputEvent.make(.keyDown, sessionId: "ads-endpoint", generation: 6, seq: 1, key: "a"))
        endpoint.send(InputEvent.make(.keyDown, sessionId: "ads-endpoint", generation: 7, seq: 2, key: "b"))

        XCTAssertEqual(adapter.sentEvents.map(\.seq), [2])
    }

    func testStopSendsSessionEndOnceAndDisconnects() async throws {
        let adapter = EndpointCastAdapter()
        let cast = CastSessionCoordinator(adapter: adapter)
        let endpoint = CastRuntimeEndpoint(cast: cast)
        try await cast.connect(to: .demoStudio)
        try await endpoint.start(context: context(generation: 2))

        await endpoint.stop()
        await endpoint.stop()

        XCTAssertEqual(adapter.sentControls.filter { $0.type == .sessionEnd }.count, 1)
        XCTAssertNil(cast.connectedDevice)
        XCTAssertEqual(endpoint.state, .stopped)
    }

    func testUnexpectedDisconnectResumesSameSession() async throws {
        let adapter = EndpointCastAdapter()
        let cast = CastSessionCoordinator(adapter: adapter)
        let endpoint = CastRuntimeEndpoint(cast: cast)
        try await cast.connect(to: .demoStudio)
        try await endpoint.start(context: context(generation: 9))

        adapter.emitIdle()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !adapter.sentControls.contains(where: { $0.type == .sessionResume }) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(adapter.connectCount, 2)
        XCTAssertTrue(adapter.sentControls.contains { $0.type == .sessionResume && $0.generation == 9 })
        XCTAssertEqual(endpoint.state, .ready)
        await endpoint.stop()
    }

    private func context(generation: Int) -> RuntimeContext {
        RuntimeContext(
            sessionId: "ads-endpoint",
            generation: generation,
            workspace: .default,
            appearance: "dark"
        )
    }
}

@MainActor
private final class EndpointCastAdapter: GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = true
    weak var delegate: (any GoogleCastAdapterDelegate)?
    private(set) var discoveredDevices: [CastDevice] = []
    private(set) var sentEvents: [InputEvent] = []
    private(set) var sentControls: [CastControlMessage] = []
    private(set) var connectCount = 0
    var failOnStart = false

    func startDiscovery() {}
    func stopDiscovery() {}

    func connect(to device: CastDevice) async throws {
        connectCount += 1
        delegate?.castAdapter(self, didChange: .connected)
    }

    func disconnect() {
        delegate?.castAdapter(self, didChange: .idle)
    }

    func send(_ event: InputEvent) {
        sentEvents.append(event)
    }

    func sendControl(_ message: CastControlMessage) {
        sentControls.append(message)

        switch message.type {
        case .sessionStart where failOnStart:
            emitError(sessionId: message.sessionId, generation: message.generation)
        case .sessionStart, .sessionResume:
            emitReady(sessionId: message.sessionId, generation: message.generation)
        default:
            break
        }
    }

    func emitIdle() {
        delegate?.castAdapter(self, didChange: .idle)
    }

    private func emitReady(sessionId: String, generation: Int) {
        guard let ready = try? CastControlMessage.ready(
            sessionId: sessionId,
            generation: generation,
            width: 1920,
            height: 1080,
            persistence: "opfs",
            lastAcceptedInputSeq: 0
        ).validated() else { return }
        delegate?.castAdapter(self, didReceive: ready)
    }

    private func emitError(sessionId: String, generation: Int) {
        guard let error = try? CastControlMessage.error(
            sessionId: sessionId,
            generation: generation,
            code: "unsupportedVersion",
            message: "Unsupported protocol"
        ).validated() else { return }
        delegate?.castAdapter(self, didReceive: error)
    }
}
