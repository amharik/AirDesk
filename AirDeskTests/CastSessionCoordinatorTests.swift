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
        let message = CastControlMessage.sessionStart(sessionId: "ads-test", workspace: "Wanix")

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
        let message = CastControlMessage(
            type: "appearance",
            sessionId: "ads-test",
            appearance: "dark",
            workspace: "Wanix"
        )

        let json = try XCTUnwrap(message.jsonString())
        let decoded = try JSONDecoder().decode(CastControlMessage.self, from: Data(json.utf8))

        XCTAssertEqual(decoded, message)
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
}
