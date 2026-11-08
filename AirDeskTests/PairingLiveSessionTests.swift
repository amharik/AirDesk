import XCTest
@testable import AirDesk

@MainActor
final class PairingLiveSessionTests: XCTestCase {
    func testPinPairingRunsOverIrohAndGatesActivationOnSAS() async throws {
        let hostIdentity = try DeviceIdentity()
        let controllerIdentity = try DeviceIdentity()
        let hostRegistry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let controllerRegistry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let hostPeer = IrohFabricPeer(identitySeed: Data(repeating: 0x51, count: 32))
        let controllerPeer = IrohFabricPeer(identitySeed: Data(repeating: 0x52, count: 32))
        let host = AdPairLiveSession(
            role: .host,
            identity: hostIdentity,
            peer: hostPeer,
            registry: hostRegistry,
            peerDisplayLabel: "Controller"
        )
        let controller = AdPairLiveSession(
            role: .controller,
            identity: controllerIdentity,
            peer: controllerPeer,
            registry: controllerRegistry,
            peerDisplayLabel: "Host"
        )
        defer {
            host.cancel()
            controller.cancel()
        }

        try await host.startHost(mode: .pin)
        let code = try XCTUnwrap(host.code)
        let pin = try XCTUnwrap(host.pin)
        try await controller.join(code: code, pin: pin)

        try await waitFor(host, state: .awaitingUserVerification)
        try await waitFor(controller, state: .awaitingUserVerification)

        let hostSAS = try XCTUnwrap(host.shortAuthenticationString)
        let controllerSAS = try XCTUnwrap(controller.shortAuthenticationString)
        XCTAssertEqual(hostSAS, controllerSAS)
        XCTAssertEqual(host.peerDeviceId, controllerIdentity.deviceId)
        XCTAssertEqual(controller.peerDeviceId, hostIdentity.deviceId)
        XCTAssertEqual(host.state, .awaitingUserVerification)
        XCTAssertEqual(hostRegistry.peer(deviceId: controllerIdentity.deviceId)?.trustState, .pending)
        XCTAssertEqual(controllerRegistry.peer(deviceId: hostIdentity.deviceId)?.trustState, .pending)
        XCTAssertFalse(hostRegistry.isTrusted(deviceId: controllerIdentity.deviceId))
        XCTAssertFalse(controllerRegistry.isTrusted(deviceId: hostIdentity.deviceId))

        XCTAssertThrowsError(try host.confirmShortAuthenticationString("000000" == hostSAS ? "999999" : "000000")) {
            XCTAssertEqual($0 as? AdPairLiveError, .shortAuthenticationStringMismatch)
        }
        XCTAssertEqual(host.state, .awaitingUserVerification)

        let hostKeys = try host.confirmShortAuthenticationString(hostSAS)
        let controllerKeys = try controller.confirmShortAuthenticationString(controllerSAS)
        XCTAssertEqual(hostKeys, controllerKeys)
        XCTAssertEqual(host.state, .completed)
        XCTAssertEqual(controller.state, .completed)
        XCTAssertEqual(hostRegistry.peer(deviceId: controllerIdentity.deviceId)?.displayLabel, "Controller")
        XCTAssertEqual(controllerRegistry.peer(deviceId: hostIdentity.deviceId)?.displayLabel, "Host")
        XCTAssertTrue(hostRegistry.isTrusted(deviceId: controllerIdentity.deviceId))
        XCTAssertTrue(controllerRegistry.isTrusted(deviceId: hostIdentity.deviceId))

        await hostPeer.stop()
        await controllerPeer.stop()
    }

    private func waitFor(
        _ session: AdPairLiveSession,
        state: AdPairLiveSession.State,
        timeout: TimeInterval = 20
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if session.state == state { return }
            if case .failed(let message) = session.state {
                throw TestFailure.failed(message)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw TestFailure.timeout("\(session.state) \(session.lastError ?? "")")
    }

    private enum TestFailure: Error, CustomStringConvertible {
        case timeout(String)
        case failed(String)

        var description: String {
            switch self {
            case .timeout(let detail): return "Timed out waiting for state: \(detail)"
            case .failed(let detail): return "Pairing failed: \(detail)"
            }
        }
    }
}
