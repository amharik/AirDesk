import XCTest
@testable import AirDesk

@MainActor
final class CastSessionCoordinatorTests: XCTestCase {
    func testDiscoveryPublishesDevices() {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)

        coordinator.startDiscovery()
        adapter.emitDevices([.demoStudio])

        XCTAssertEqual(coordinator.devices, [.demoStudio])
        XCTAssertEqual(coordinator.state, .discovering)
    }

    func testConnectPublishesConnectedDevice() async throws {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)

        try await coordinator.connect(to: .demoStudio)

        XCTAssertEqual(coordinator.state, .connected)
        XCTAssertEqual(coordinator.connectedDevice, .demoStudio)
        XCTAssertNil(coordinator.lastError)
    }

    func testSendIsIgnoredUntilConnected() async throws {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)
        let event = InputEvent.make(.keyDown, sessionId: "ads-test", seq: 1, key: "a")

        coordinator.send(event)
        XCTAssertTrue(adapter.sentEvents.isEmpty)

        try await coordinator.connect(to: .demoStudio)
        coordinator.send(event)

        XCTAssertEqual(adapter.sentEvents, [event])
    }

    func testControlIsIgnoredUntilConnected() async throws {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)
        let message = CastControlMessage.sessionStart(
            sessionId: "ads-test",
            generation: 1,
            workspace: "Wanix",
            appearance: "dark"
        )

        coordinator.sendControl(message)
        XCTAssertTrue(adapter.sentControls.isEmpty)

        try await coordinator.connect(to: .demoStudio)
        coordinator.sendControl(message)

        XCTAssertEqual(adapter.sentControls, [message])
    }

    func testAdapterFailurePublishesError() {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)

        adapter.emitFailure(CastAdapterError.receiverNotConfigured)

        XCTAssertEqual(coordinator.state, .failed)
        XCTAssertEqual(coordinator.lastError, CastAdapterError.receiverNotConfigured.localizedDescription)
    }

    func testConnectFailureThrowsAndPublishesError() async {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)
        adapter.connectError = CastAdapterError.deviceUnavailable

        do {
            try await coordinator.connect(to: .demoStudio)
            XCTFail("Expected connect to throw")
        } catch {
            XCTAssertEqual(error as? CastAdapterError, .deviceUnavailable)
        }

        XCTAssertEqual(coordinator.state, .failed)
        XCTAssertEqual(coordinator.lastError, CastAdapterError.deviceUnavailable.localizedDescription)
    }

    func testDisconnectClearsConnection() async throws {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)

        try await coordinator.connect(to: .demoStudio)
        coordinator.disconnect()

        XCTAssertNil(coordinator.connectedDevice)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testControlMessageRoundTrips() throws {
        let message = CastControlMessage.appearance(
            sessionId: "ads-test",
            generation: 1,
            appearance: "dark"
        )

        let json = try message.jsonString()
        let decoded = try JSONDecoder().decode(CastControlMessage.self, from: Data(json.utf8))

        XCTAssertEqual(decoded, message)
        XCTAssertNoThrow(try decoded.validated())
    }

    func testReadyMessageIsPublishedAndMatchesSession() async throws {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)
        var received: [CastControlMessage] = []
        coordinator.addControlObserver { received.append($0) }

        try await coordinator.connect(to: .demoStudio)
        adapter.emitReady(sessionId: "ads-test", generation: 1)

        let ready = try await coordinator.waitForReady(sessionId: "ads-test", generation: 1, timeout: 1)
        XCTAssertEqual(ready.type, .ready)
        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(received.map(\.type), [.ready])
    }

    func testReadyTimeoutForMismatchedGeneration() async throws {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)
        try await coordinator.connect(to: .demoStudio)
        adapter.emitReady(sessionId: "ads-test", generation: 1)

        do {
            _ = try await coordinator.waitForReady(sessionId: "ads-test", generation: 2, timeout: 0.15)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? CastProtocolError, .readyTimeout)
        }
    }

    func testReceiverAckTracksHighestAcceptedSequence() async throws {
        let adapter = FakeCastAdapter()
        let coordinator = CastSessionCoordinator(adapter: adapter)
        try await coordinator.connect(to: .demoStudio)
        adapter.emitControl(CastControlMessage.ack(sessionId: "ads-test", generation: 1, lastAcceptedInputSeq: 4))
        adapter.emitControl(CastControlMessage.ack(sessionId: "ads-test", generation: 1, lastAcceptedInputSeq: 7))
        adapter.emitControl(CastControlMessage.ack(sessionId: "ads-test", generation: 1, lastAcceptedInputSeq: 6))

        XCTAssertEqual(coordinator.lastAcceptedInputSequence, 7)
    }
}

@MainActor
private final class FakeCastAdapter: GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = true
    weak var delegate: (any GoogleCastAdapterDelegate)?
    private(set) var discoveredDevices: [CastDevice] = []
    private(set) var sentEvents: [InputEvent] = []
    private(set) var sentControls: [CastControlMessage] = []
    var connectError: Error?

    func startDiscovery() {
        delegate?.castAdapter(self, didChange: .discovering)
    }

    func stopDiscovery() {}

    func connect(to device: CastDevice) async throws {
        if let connectError { throw connectError }
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
    }

    func emitDevices(_ devices: [CastDevice]) {
        discoveredDevices = devices
        delegate?.castAdapter(self, didDiscover: devices)
    }

    func emitFailure(_ error: Error) {
        delegate?.castAdapter(self, didFail: error)
    }

    func emitControl(_ message: CastControlMessage) {
        delegate?.castAdapter(self, didReceive: message)
    }

    func emitReady(sessionId: String, generation: Int) {
        emitControl(CastControlMessage.ready(
            sessionId: sessionId,
            generation: generation,
            width: 1920,
            height: 1080,
            persistence: "indexeddb",
            lastAcceptedInputSeq: 0
        ))
    }
}
