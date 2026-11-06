import Combine
import Foundation

@MainActor
final class IrohFabricPeer: ObservableObject {
    enum State: String, Sendable {
        case stopped
        case starting
        case ready
        case connecting
        case connected
        case failed

        var title: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting"
            case .ready: return "Ready"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            case .failed: return "Failed"
            }
        }
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var endpointID: String = ""
    @Published private(set) var ticket: String = ""
    @Published private(set) var directAddresses: [String] = []
    @Published private(set) var relayURL: String?
    @Published private(set) var relayPolicyLabel: String = IrohRelayPolicy.directOnly.diagnosticsLabel
    @Published private(set) var remoteEndpointID: String?
    @Published private(set) var paths: [IrohFabricPath] = []
    @Published private(set) var lastError: String?
    @Published private(set) var connectionCount: Int = 0

    var onInputEvent: ((InputEvent) -> Void)?
    var onMovementFrame: ((PackedMovementFrame) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?

    var isConnected: Bool { activeConnection != nil }
    var selectedPath: IrohFabricPath? { paths.first { $0.isSelected } }

    private let identitySeed: Data?
    private var transport: IrohFabricTransport?
    private var acceptTask: Task<Void, Never>?
    private var connections: [String: IrohFabricConnection] = [:]
    private var receiveTasks: [String: Task<Void, Never>] = [:]
    private var activeRemoteID: String?
    private var sendChain: Task<Void, Never>?
    private var diagnosticsTimer: Timer?

    init(identitySeed: Data? = nil) {
        self.identitySeed = identitySeed
    }

    deinit {
        diagnosticsTimer?.invalidate()
    }

    func start(relayPolicy: IrohRelayPolicy) async {
        switch state {
        case .starting, .ready, .connected, .connecting:
            return
        case .stopped, .failed:
            break
        }

        state = .starting
        lastError = nil
        relayPolicyLabel = relayPolicy.diagnosticsLabel

        do {
            let seed = try identitySeed ?? IrohIdentityStore.loadOrCreate()
            let configuration = try IrohFabricConfiguration(
                relayPolicy: relayPolicy,
                identitySeed: seed
            )
            let transport = IrohFabricTransport(configuration: configuration)
            let info: IrohFabricEndpointInfo
            do {
                info = try await transport.start()
            } catch {
                await transport.close()
                throw error
            }
            self.transport = transport
            endpointID = info.endpointID
            ticket = info.ticket
            directAddresses = info.directAddresses
            relayURL = info.relayURL
            relayPolicyLabel = info.relayPolicy
            state = .ready
            startAcceptLoop(transport)
        } catch {
            state = .failed
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        acceptTask?.cancel()
        acceptTask = nil
        sendChain?.cancel()
        sendChain = nil
        stopDiagnosticsTimer()

        let connectedIDs = Array(connections.keys)
        for connection in connections.values {
            connection.close()
        }
        connections.removeAll()
        receiveTasks.values.forEach { $0.cancel() }
        receiveTasks.removeAll()
        activeRemoteID = nil
        connectionCount = 0
        paths = []
        remoteEndpointID = nil
        connectedIDs.forEach { onPeerDisconnected?($0) }

        if let transport {
            await transport.close()
        }
        transport = nil
        endpointID = ""
        ticket = ""
        directAddresses = []
        relayURL = nil
        state = .stopped
    }

    func connect(to ticket: String) async throws {
        guard let transport else { throw IrohFabricError.notStarted }
        let trimmed = ticket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw IrohFabricError.invalidTicket }

        state = .connecting
        lastError = nil
        do {
            let connection = try await transport.connect(ticket: trimmed)
            adopt(connection, isOutgoing: true)
        } catch {
            state = transportStateAfterFailure()
            lastError = error.localizedDescription
            throw error
        }
    }

    func disconnect() {
        let connectedIDs = Array(connections.keys)
        for connection in connections.values {
            connection.close()
        }
        connections.removeAll()
        receiveTasks.values.forEach { $0.cancel() }
        receiveTasks.removeAll()
        activeRemoteID = nil
        connectionCount = 0
        paths = []
        remoteEndpointID = nil
        connectedIDs.forEach { onPeerDisconnected?($0) }
        stopDiagnosticsTimer()
        state = transport == nil ? .stopped : .ready
    }

    @discardableResult
    func sendInput(_ event: InputEvent) -> Bool {
        guard let connection = activeConnection else { return false }

        let packet: IrohFabricInputPacket
        do {
            packet = try IrohFabricInputCodec.encode(event)
        } catch {
            lastError = error.localizedDescription
            return false
        }

        let previous = sendChain
        sendChain = Task { @MainActor [weak self, weak connection] in
            _ = await previous?.value
            guard let connection else { return }
            do {
                try await connection.send(packet.payload, channel: packet.channel)
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
        return true
    }

    private var activeConnection: IrohFabricConnection? {
        guard let activeRemoteID else { return nil }
        return connections[activeRemoteID]
    }

    private func startAcceptLoop(_ transport: IrohFabricTransport) {
        acceptTask = Task { @MainActor [weak self] in
            let incoming = await transport.incoming
            for await connection in incoming {
                guard let self else { return }
                self.adopt(connection, isOutgoing: false)
            }
        }
    }

    private func adopt(_ connection: IrohFabricConnection, isOutgoing: Bool) {
        let id = connection.remoteEndpointID
        connections[id] = connection
        if activeRemoteID == nil || isOutgoing {
            activeRemoteID = id
        }
        connectionCount = connections.count
        state = .connected
        refreshDiagnostics()
        startDiagnosticsTimer()
        onPeerConnected?(id)

        receiveTasks[id]?.cancel()
        receiveTasks[id] = Task { @MainActor [weak self, weak connection] in
            guard let connection else { return }
            for await message in connection.messages {
                guard let self else { return }
                self.handle(message)
            }
            self?.removeConnection(id)
        }
    }

    private func handle(_ message: IrohFabricMessage) {
        switch message {
        case .invalid(let reason):
            lastError = reason
        case .reliable:
            do {
                guard let event = try IrohFabricInputCodec.decodeReliable(message) else { return }
                onInputEvent?(event)
            } catch {
                lastError = error.localizedDescription
            }
        case .movement(let payload):
            do {
                onMovementFrame?(try PackedMovementFrame.decode(payload))
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func removeConnection(_ id: String) {
        guard connections.removeValue(forKey: id) != nil else { return }
        receiveTasks.removeValue(forKey: id)?.cancel()
        connectionCount = connections.count
        if activeRemoteID == id {
            activeRemoteID = connections.keys.sorted().first
        }
        refreshDiagnostics()
        onPeerDisconnected?(id)
        if connections.isEmpty {
            stopDiagnosticsTimer()
            state = transport == nil ? .stopped : .ready
        }
    }

    private func refreshDiagnostics() {
        guard let connection = activeConnection else {
            paths = []
            remoteEndpointID = nil
            return
        }
        let diagnostics = connection.diagnostics()
        paths = diagnostics.paths
        remoteEndpointID = diagnostics.remoteEndpointID
    }

    private func startDiagnosticsTimer() {
        guard diagnosticsTimer == nil else { return }
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDiagnostics()
            }
        }
    }

    private func stopDiagnosticsTimer() {
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil
    }

    private func transportStateAfterFailure() -> State {
        transport == nil ? .failed : .ready
    }
}
