import XCTest
@testable import AirDesk

final class IrohFabricTransportTests: XCTestCase {
    private enum TestError: Error {
        case timeout
        case streamClosed
        case unexpectedMessage
    }

    func testFrameEncodingAndValidation() throws {
        let frame = try IrohFabricFrame(channel: .control, payload: Data([1, 2, 3]))
        XCTAssertEqual(frame.encoded, Data([0, 0, 0, 0, 3, 1, 2, 3]))

        let movement = Data(repeating: 0x7f, count: 16)
        XCTAssertEqual(try IrohFabricFrame(movement: movement).payload, movement)
        XCTAssertThrowsError(try IrohFabricFrame(movement: Data(repeating: 0, count: 15)))
        XCTAssertThrowsError(try IrohFabricFrame(channel: .movement, payload: movement))
        XCTAssertNil(IrohFabricChannel.reliable(rawValue: IrohFabricChannel.movement.rawValue))
        XCTAssertThrowsError(try IrohFabricFrame(channel: .runtime, payload: Data(count: 1_048_577)))
    }

    func testRelayPolicyFailsClosed() throws {
        XCTAssertThrowsError(try IrohRelayPolicy.selfHosted(urls: []).relayMode())
        XCTAssertThrowsError(try IrohRelayPolicy.selfHosted(urls: [""]).relayMode())
        XCTAssertThrowsError(try IrohRelayPolicy.selfHosted(urls: ["http://relay.example"]).relayMode())
        _ = try IrohRelayPolicy.selfHosted(urls: ["https://relay.example"]).relayMode()
        XCTAssertThrowsError(try IrohFabricConfiguration(identitySeed: Data(repeating: 0, count: 31)))
        XCTAssertThrowsError(try IrohFabricConfiguration(alpn: Data()))
    }

    func testDirectLoopbackReliableAndMovement() async throws {
        let host = try makeTransport(seed: 0x11)
        let controller = try makeTransport(seed: 0x22)

        let hostInfo = try await host.start()
        let controllerInfo = try await controller.start()
        defer {
            Task {
                await host.close()
                await controller.close()
            }
        }

        XCTAssertFalse(hostInfo.endpointID.isEmpty)
        XCTAssertFalse(controllerInfo.endpointID.isEmpty)
        XCTAssertEqual(hostInfo.relayPolicy, "direct-only")
        XCTAssertEqual(controllerInfo.relayPolicy, "direct-only")

        let incoming = await host.incoming
        let acceptTask = Task {
            try await withTimeout(seconds: 10) {
                var iterator = incoming.makeAsyncIterator()
                guard let connection = await iterator.next() else {
                    throw TestError.streamClosed
                }
                return connection
            }
        }

        let controllerConnection = try await controller.connect(ticket: hostInfo.ticket)
        let accepted = try await acceptTask.value
        XCTAssertEqual(controllerConnection.remoteEndpointID, hostInfo.endpointID)

        let control = Data("hello-airdesk".utf8)
        try await controllerConnection.send(control, channel: .control)
        let controlMessage = try await nextMessage(from: accepted)
        guard case .reliable(channel: .control, let receivedControl) = controlMessage else {
            return XCTFail("Expected reliable control message")
        }
        XCTAssertEqual(receivedControl, control)

        let movement = Data((0..<16).map { UInt8($0) })
        try await controllerConnection.send(movement, channel: .movement)
        let movementMessage = try await nextMessage(from: accepted)
        guard case .movement(let receivedMovement) = movementMessage else {
            return XCTFail("Expected movement datagram")
        }
        XCTAssertEqual(receivedMovement, movement)

        let runtime = Data("runtime".utf8)
        try await accepted.send(runtime, channel: .runtime)
        let runtimeMessage = try await nextMessage(from: controllerConnection)
        guard case .reliable(channel: .runtime, let receivedRuntime) = runtimeMessage else {
            return XCTFail("Expected reliable runtime message")
        }
        XCTAssertEqual(receivedRuntime, runtime)

        let diagnostics = accepted.diagnostics()
        XCTAssertEqual(diagnostics.remoteEndpointID, controllerInfo.endpointID)
        XCTAssertTrue(diagnostics.paths.contains { $0.isSelected })
    }

    private func makeTransport(seed: UInt8) throws -> IrohFabricTransport {
        IrohFabricTransport(
            configuration: try IrohFabricConfiguration(
                relayPolicy: .directOnly,
                bindAddress: "127.0.0.1:0",
                identitySeed: Data(repeating: seed, count: 32)
            )
        )
    }

    private func nextMessage(from connection: IrohFabricConnection) async throws -> IrohFabricMessage {
        try await withTimeout(seconds: 5) {
            var iterator = connection.messages.makeAsyncIterator()
            guard let message = await iterator.next() else {
                throw TestError.streamClosed
            }
            return message
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw TestError.timeout
            }
            guard let result = try await group.next() else {
                throw TestError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
