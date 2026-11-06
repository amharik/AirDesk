import Foundation
import IrohLib

struct IrohFabricPath: Sendable, Equatable {
    let id: String
    let remoteAddress: String
    let isSelected: Bool
    let isDirectIP: Bool
    let isRelay: Bool
    let rttMs: UInt64
}

struct IrohFabricConnectionDiagnostics: Sendable, Equatable {
    let remoteEndpointID: String
    let paths: [IrohFabricPath]

    var selectedPath: IrohFabricPath? {
        paths.first { $0.isSelected }
    }

    var isUsingRelay: Bool {
        selectedPath?.isRelay == true
    }
}

final class IrohFabricConnection: @unchecked Sendable {
    let messages: AsyncStream<IrohFabricMessage>
    let remoteEndpointID: String

    private let connection: Connection
    private let continuation: AsyncStream<IrohFabricMessage>.Continuation
    private var receiveTasks: [Task<Void, Never>] = []
    private let lock = NSLock()
    private var started = false

    init(connection: Connection) {
        self.connection = connection
        self.remoteEndpointID = connection.remoteId().description

        let (stream, continuation) = AsyncStream<IrohFabricMessage>.makeStream()
        self.messages = stream
        self.continuation = continuation
    }

    func start() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        receiveTasks.append(Task { [weak self] in
            await self?.receiveReliableFrames()
        })
        receiveTasks.append(Task { [weak self] in
            await self?.receiveMovementDatagrams()
        })
        receiveTasks.append(Task { [weak self] in
            guard let self else { return }
            _ = await self.connection.closed()
            self.continuation.finish()
            self.cancelReceiveTasks()
        })
    }

    func send(_ payload: Data, channel: IrohFabricChannel) async throws {
        if channel == .movement {
            let frame = try IrohFabricFrame(movement: payload)
            guard connection.maxDatagramSize().map({ UInt64(frame.payload.count) <= $0 }) ?? true else {
                throw IrohFabricError.frameTooLarge
            }
            try await connection.sendDatagramWait(data: frame.payload)
            return
        }

        let frame = try IrohFabricFrame(channel: channel, payload: payload)
        let stream = try await connection.openBi()
        let sendStream = stream.send()
        try await sendStream.writeAll(buf: frame.encoded)
        try await sendStream.finish()
    }

    func diagnostics() -> IrohFabricConnectionDiagnostics {
        IrohFabricConnectionDiagnostics(
            remoteEndpointID: remoteEndpointID,
            paths: connection.paths().map {
                IrohFabricPath(
                    id: $0.id,
                    remoteAddress: $0.remoteAddr,
                    isSelected: $0.isSelected,
                    isDirectIP: $0.isIp,
                    isRelay: $0.isRelay,
                    rttMs: $0.rttMs
                )
            }
        )
    }

    func close() {
        cancelReceiveTasks()
        continuation.finish()
        try? connection.close(errorCode: 0, reason: Data("airdesk-closed".utf8))
    }

    private func cancelReceiveTasks() {
        lock.lock()
        let tasks = receiveTasks
        receiveTasks.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    private func receiveReliableFrames() async {
        while !Task.isCancelled {
            do {
                let stream = try await connection.acceptBi()
                let receiveStream = stream.recv()
                let channelData = try await receiveStream.readExact(size: 1)
                guard let channel = IrohFabricChannel.reliable(rawValue: channelData[0]) else {
                    continuation.yield(.invalid("Unknown reliable channel \(channelData[0])."))
                    continue
                }
                let lengthData = try await receiveStream.readExact(size: 4)
                let length = lengthData.uint32BigEndian()
                guard length <= UInt32(IrohFabricFrame.maximumReliablePayload) else {
                    continuation.yield(.invalid("Reliable frame exceeds the 1 MiB limit."))
                    continue
                }
                let payload = try await receiveStream.readExact(size: length)
                guard payload.count == Int(length) else {
                    continuation.yield(.invalid("Reliable frame ended early."))
                    continue
                }
                continuation.yield(.reliable(channel: channel, payload: payload))
            } catch {
                break
            }
        }
    }

    private func receiveMovementDatagrams() async {
        while !Task.isCancelled {
            do {
                let payload = try await connection.readDatagram()
                guard payload.count == IrohFabricFrame.movementPayloadSize else {
                    continuation.yield(.invalid("Movement datagram must be exactly 16 bytes."))
                    continue
                }
                continuation.yield(.movement(payload))
            } catch {
                break
            }
        }
    }
}

struct IrohFabricEndpointInfo: Sendable, Equatable {
    let endpointID: String
    let ticket: String
    let directAddresses: [String]
    let relayURL: String?
    let relayPolicy: String
}

actor IrohFabricTransport {
    private let configuration: IrohFabricConfiguration
    private let incomingStream: AsyncStream<IrohFabricConnection>
    private let incomingContinuation: AsyncStream<IrohFabricConnection>.Continuation
    private var endpoint: Endpoint?
    private var acceptTask: Task<Void, Never>?

    init(configuration: IrohFabricConfiguration) {
        self.configuration = configuration
        let (stream, continuation) = AsyncStream<IrohFabricConnection>.makeStream()
        self.incomingStream = stream
        self.incomingContinuation = continuation
    }

    var incoming: AsyncStream<IrohFabricConnection> { incomingStream }

    func start() async throws -> IrohFabricEndpointInfo {
        guard endpoint == nil else {
            return try endpointInfo()
        }

        let options = EndpointOptions(
            preset: presetMinimal(),
            bindAddr: configuration.bindAddress,
            secretKey: configuration.identitySeed,
            alpns: [configuration.alpn],
            relayMode: try configuration.relayPolicy.relayMode()
        )
        let endpoint = try await Endpoint.bind(options: options)
        self.endpoint = endpoint

        if case .selfHosted = configuration.relayPolicy {
            try await waitForHomeRelay(endpoint)
        }

        acceptTask = Task { [weak self] in
            await self?.acceptLoop(endpoint)
        }
        return try endpointInfo()
    }

    func endpointInfo() throws -> IrohFabricEndpointInfo {
        guard let endpoint else { throw IrohFabricError.notStarted }
        let address = endpoint.addr()
        return IrohFabricEndpointInfo(
            endpointID: address.id().description,
            ticket: try EndpointTicket.fromAddr(addr: address).description,
            directAddresses: address.directAddresses(),
            relayURL: address.relayUrl(),
            relayPolicy: configuration.relayPolicy.diagnosticsLabel
        )
    }

    func connect(ticket: String) async throws -> IrohFabricConnection {
        guard let endpoint else { throw IrohFabricError.notStarted }
        guard !endpoint.isClosed() else { throw IrohFabricError.endpointClosed }

        let parsed: EndpointTicket
        do {
            parsed = try EndpointTicket.fromString(str: ticket)
        } catch {
            throw IrohFabricError.invalidTicket
        }
        let connection = try await endpoint.connect(addr: parsed.endpointAddr(), alpn: configuration.alpn)
        return makeConnection(connection)
    }

    func close() async {
        acceptTask?.cancel()
        acceptTask = nil
        incomingContinuation.finish()
        guard let endpoint else { return }
        self.endpoint = nil
        try? await endpoint.close()
    }

    private func makeConnection(_ connection: Connection) -> IrohFabricConnection {
        let fabricConnection = IrohFabricConnection(connection: connection)
        fabricConnection.start()
        return fabricConnection
    }

    private func waitForHomeRelay(_ endpoint: Endpoint) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await endpoint.online()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                throw IrohFabricError.relayRequired
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func acceptLoop(_ endpoint: Endpoint) async {
        while !Task.isCancelled {
            guard let incoming = await endpoint.acceptNext() else { break }
            do {
                let accepting = try await incoming.accept()
                let alpn = try await accepting.alpn()
                guard alpn == configuration.alpn else {
                    continue
                }
                let connection = try await accepting.connect()
                incomingContinuation.yield(makeConnection(connection))
            } catch {
                continue
            }
        }
        incomingContinuation.finish()
    }
}
