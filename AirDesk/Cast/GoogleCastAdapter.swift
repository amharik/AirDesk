import Foundation
import OSLog

@MainActor
protocol GoogleCastAdapterDelegate: AnyObject {
    func castAdapter(_ adapter: any GoogleCastAdapter, didDiscover devices: [CastDevice])
    func castAdapter(_ adapter: any GoogleCastAdapter, didChange state: CastConnectionState)
    func castAdapter(_ adapter: any GoogleCastAdapter, didFail error: Error)
    func castAdapter(_ adapter: any GoogleCastAdapter, didReceive event: InputEvent)
}

@MainActor
protocol GoogleCastAdapter: AnyObject {
    var isAvailable: Bool { get }
    var isSimulated: Bool { get }
    var delegate: (any GoogleCastAdapterDelegate)? { get set }
    var discoveredDevices: [CastDevice] { get }

    func startDiscovery()
    func stopDiscovery()
    func connect(to device: CastDevice) async throws
    func disconnect()
    func send(_ event: InputEvent)
    func sendControl(_ message: CastControlMessage)
}

@MainActor
final class SimulatedGoogleCastAdapter: GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = true
    weak var delegate: (any GoogleCastAdapterDelegate)?
    private(set) var discoveredDevices: [CastDevice] = []
    private var discoveryTask: Task<Void, Never>?
    private(set) var connectedDevice: CastDevice?

    func startDiscovery() {
        discoveryTask?.cancel()
        delegate?.castAdapter(self, didChange: .discovering)
        discoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled, let self else { return }
            self.discoveredDevices = [.demoStudio, .demoLivingRoom]
            self.delegate?.castAdapter(self, didDiscover: self.discoveredDevices)
            self.delegate?.castAdapter(self, didChange: .idle)
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    func connect(to device: CastDevice) async throws {
        delegate?.castAdapter(self, didChange: .connecting)
        try await Task.sleep(nanoseconds: 650_000_000)
        try Task.checkCancellation()
        connectedDevice = device
        delegate?.castAdapter(self, didChange: .connected)
    }

    func disconnect() {
        connectedDevice = nil
        delegate?.castAdapter(self, didChange: .idle)
    }

    func send(_ event: InputEvent) {
        delegate?.castAdapter(self, didReceive: event)
    }

    func sendControl(_ message: CastControlMessage) {
        _ = message
    }
}

#if canImport(GoogleCast)
import GoogleCast

@MainActor
final class SDKGoogleCastAdapter: NSObject, GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = false
    weak var delegate: (any GoogleCastAdapterDelegate)?
    private(set) var discoveredDevices: [CastDevice] = []
    private var inputChannel: GCKGenericChannel?
    private var controlChannel: GCKGenericChannel?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var isListening = false
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "Cast")

    func startDiscovery() {
        let context = GCKCastContext.sharedInstance()
        if !isListening {
            context.discoveryManager.add(self)
            context.sessionManager.add(self)
            isListening = true
        }
        context.discoveryManager.startDiscovery()
        delegate?.castAdapter(self, didChange: .discovering)
    }

    func stopDiscovery() {
        GCKCastContext.sharedInstance().discoveryManager.stopDiscovery()
    }

    func connect(to device: CastDevice) async throws {
        guard let gckDevice = currentGCKDevice(matching: device) else {
            throw CastAdapterError.deviceUnavailable
        }
        delegate?.castAdapter(self, didChange: .connecting)
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            GCKCastContext.sharedInstance().sessionManager.startSession(with: gckDevice)
            connectTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishConnect(.failure(CastAdapterError.connectionTimedOut))
            }
        }
    }

    func disconnect() {
        finishConnect(.failure(CancellationError()))
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
        inputChannel = nil
        controlChannel = nil
        delegate?.castAdapter(self, didChange: .idle)
    }

    func send(_ event: InputEvent) {
        guard let inputChannel, let object = try? event.jsonObject(),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return }
        inputChannel.sendTextMessage(json)
    }

    func sendControl(_ message: CastControlMessage) {
        guard let controlChannel, let json = message.jsonString() else { return }
        controlChannel.sendTextMessage(json)
    }

    private func finishConnect(_ result: Result<Void, Error>) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        guard let continuation = connectContinuation else { return }
        connectContinuation = nil
        continuation.resume(with: result)
    }

    private func currentGCKDevice(matching device: CastDevice) -> GCKDevice? {
        let discovery = GCKCastContext.sharedInstance().discoveryManager
        for index in 0..<discovery.deviceCount {
            let candidate = discovery.device(at: index)
            if candidate.deviceID == device.id {
                return candidate
            }
        }
        return nil
    }
}

extension SDKGoogleCastAdapter: GCKDiscoveryManagerListener {
    @objc func didUpdateDeviceList() {
        let discovery = GCKCastContext.sharedInstance().discoveryManager
        var result: [CastDevice] = []
        for index in 0..<discovery.deviceCount {
            let device = discovery.device(at: index)
            result.append(CastDevice(
                id: device.deviceID,
                name: device.friendlyName,
                model: "Cast device",
                isDemo: false
            ))
        }
        discoveredDevices = result
        delegate?.castAdapter(self, didDiscover: result)
    }
}

extension SDKGoogleCastAdapter: GCKSessionManagerListener {
    @objc func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        guard let castSession = session as? GCKCastSession else { return }
        let input = castSession.addChannel(withNamespace: CastNamespace.input) as? GCKGenericChannel
        input?.delegate = self
        let control = castSession.addChannel(withNamespace: CastNamespace.control) as? GCKGenericChannel
        control?.delegate = self
        inputChannel = input
        controlChannel = control
        delegate?.castAdapter(self, didChange: .connected)
        finishConnect(.success(()))
    }

    @objc func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        inputChannel = nil
        controlChannel = nil
        if let error {
            delegate?.castAdapter(self, didFail: error)
            finishConnect(.failure(error))
        } else {
            delegate?.castAdapter(self, didChange: .idle)
            finishConnect(.failure(CastAdapterError.notConnected))
        }
    }

    @objc func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        delegate?.castAdapter(self, didFail: error)
        finishConnect(.failure(error))
    }
}

extension SDKGoogleCastAdapter: GCKGenericChannelDelegate {
    @objc func castChannel(_ channel: GCKGenericChannel, didReceiveTextMessage message: String, withNamespace protocolNamespace: String) {
        guard protocolNamespace == CastNamespace.input,
              let data = message.data(using: .utf8),
              let event = try? JSONDecoder().decode(InputEvent.self, from: data),
              let validated = try? event.validated() else { return }
        delegate?.castAdapter(self, didReceive: validated)
    }
}

#endif
