import Foundation
import OSLog

#if canImport(GoogleCast)
import GoogleCast
#endif

@MainActor
final class CastSessionCoordinator: ObservableObject {
    @Published private(set) var devices: [CastDevice] = []
    @Published private(set) var state: CastConnectionState = .idle
    @Published private(set) var connectedDevice: CastDevice?
    @Published private(set) var lastError: String?
    @Published private(set) var isDemo = true
    @Published private(set) var isReady = false
    private(set) var lastAcceptedInputSequence = 0

    var onInput: ((InputEvent) -> Void)?
    var onConnectionStateChange: ((CastConnectionState) -> Void)?
    let adapter: any GoogleCastAdapter
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "Cast")
    private var controlObservers: [UUID: (CastControlMessage) -> Void] = [:]
    private var readyMessages: [String: CastControlMessage] = [:]
    private var controlErrors: [String: CastProtocolError] = [:]

    init(adapter: (any GoogleCastAdapter)? = nil) {
        if let adapter {
            self.adapter = adapter
        } else {
            self.adapter = CastSessionCoordinator.makeDefaultAdapter()
        }
        self.isDemo = self.adapter.isSimulated
        self.adapter.delegate = self
    }

    static func makeDefaultAdapter() -> any GoogleCastAdapter {
        #if canImport(GoogleCast)
        if CastConfiguration.hasRegisteredReceiver {
            return SDKGoogleCastAdapter()
        }
        #endif
        return SimulatedGoogleCastAdapter()
    }

    static func configureSDKIfNeeded() {
        #if canImport(GoogleCast)
        guard CastConfiguration.hasRegisteredReceiver else { return }
        let options = GCKCastOptions(receiverApplicationID: CastConfiguration.receiverApplicationID)
        options.suspendSessionsWhenBackgrounded = false
        GCKCastContext.setSharedInstanceWith(options)
        #endif
    }

    func startDiscovery() {
        lastError = nil
        adapter.startDiscovery()
    }

    func stopDiscovery() {
        adapter.stopDiscovery()
        if state == .discovering { state = .idle }
    }

    func connect(to device: CastDevice) async throws {
        lastError = nil
        readyMessages.removeAll()
        controlErrors.removeAll()
        isReady = false
        lastAcceptedInputSequence = 0
        do {
            try await adapter.connect(to: device)
            connectedDevice = device
        } catch {
            lastError = error.localizedDescription
            state = .failed
            throw error
        }
    }

    func disconnect() {
        adapter.disconnect()
        connectedDevice = nil
        state = .idle
        isReady = false
        readyMessages.removeAll()
        controlErrors.removeAll()
    }

    func send(_ event: InputEvent) {
        guard connectedDevice != nil else { return }
        adapter.send(event)
    }

    func sendControl(_ message: CastControlMessage) {
        guard connectedDevice != nil else { return }
        adapter.sendControl(message)
    }

    @discardableResult
    func addControlObserver(_ observer: @escaping (CastControlMessage) -> Void) -> UUID {
        let token = UUID()
        controlObservers[token] = observer
        return token
    }

    func removeControlObserver(_ token: UUID) {
        controlObservers.removeValue(forKey: token)
    }

    func waitForReady(
        sessionId: String,
        generation: Int,
        timeout: TimeInterval = CastProtocol.readyTimeout
    ) async throws -> CastControlMessage {
        let key = readinessKey(sessionId: sessionId, generation: generation)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let ready = readyMessages[key] {
                return ready
            }
            if let error = controlErrors[key] {
                throw error
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CastProtocolError.readyTimeout
    }

    func clearError() {
        lastError = nil
    }

    private func readinessKey(sessionId: String, generation: Int) -> String {
        "\(sessionId):\(generation)"
    }
}

extension CastSessionCoordinator: GoogleCastAdapterDelegate {
    func castAdapter(_ adapter: any GoogleCastAdapter, didDiscover devices: [CastDevice]) {
        self.devices = devices
        if state == .discovering { state = devices.isEmpty ? .idle : .discovering }
    }

    func castAdapter(_ adapter: any GoogleCastAdapter, didChange state: CastConnectionState) {
        self.state = state
        if state == .connected, let device = connectedDevice {
            logger.info("Cast connected to \(device.name, privacy: .public)")
        }
        if state != .connected {
            isReady = false
        }
        if state == .idle {
            connectedDevice = nil
        }
        onConnectionStateChange?(state)
    }

    func castAdapter(_ adapter: any GoogleCastAdapter, didFail error: Error) {
        lastError = error.localizedDescription
        state = .failed
        isReady = false
        logger.error("Cast failure: \(error.localizedDescription, privacy: .public)")
        onConnectionStateChange?(.failed)
    }

    func castAdapter(_ adapter: any GoogleCastAdapter, didReceive event: InputEvent) {
        onInput?(event)
    }

    func castAdapter(_ adapter: any GoogleCastAdapter, didReceive message: CastControlMessage) {
        guard CastControlMessage.Kind.receiverTypes.contains(message.type) else { return }
        let key = readinessKey(sessionId: message.sessionId, generation: message.generation)

        switch message.type {
        case .ready:
            readyMessages[key] = message
            controlErrors.removeValue(forKey: key)
            isReady = true
        case .ack:
            if let seq = message.lastAcceptedInputSeq {
                lastAcceptedInputSequence = max(lastAcceptedInputSequence, seq)
            }
        case .state:
            isReady = message.state == RuntimeState.ready.rawValue
        case .error:
            let error = CastProtocolError.receiverError(message.code ?? "unknown")
            controlErrors[key] = error
            isReady = false
            lastError = error.localizedDescription
        default:
            break
        }

        for observer in controlObservers.values {
            observer(message)
        }
    }
}
