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
}

#if canImport(GoogleCast)
import GoogleCast

@MainActor
final class SDKGoogleCastAdapter: NSObject, GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = false
    weak var delegate: (any GoogleCastAdapterDelegate)?
    private(set) var discoveredDevices: [CastDevice] = []
    private var channel: GCKGenericChannel?
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "Cast")

    func startDiscovery() {
        let discovery = GCKCastContext.sharedInstance().discoveryManager
        discovery.add(self)
        discovery.startDiscovery()
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
        GCKCastContext.sharedInstance().sessionManager.startSession(with: gckDevice)
    }

    func disconnect() {
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
        channel = nil
        delegate?.castAdapter(self, didChange: .idle)
    }

    func send(_ event: InputEvent) {
        guard let channel, let object = try? event.jsonObject(),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return }
        channel.sendTextMessage(json)
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
    func didUpdateDeviceList() {
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
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        guard let castSession = session as? GCKCastSession else { return }
        let channel = castSession.addChannel(withNamespace: CastNamespace.input) as? GCKGenericChannel
        channel?.delegate = self
        self.channel = channel
        delegate?.castAdapter(self, didChange: .connected)
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        channel = nil
        if let error {
            delegate?.castAdapter(self, didFail: error)
        } else {
            delegate?.castAdapter(self, didChange: .idle)
        }
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        delegate?.castAdapter(self, didFail: error)
    }
}

extension SDKGoogleCastAdapter: GCKGenericChannelDelegate {
    func castChannel(_ channel: GCKGenericChannel, didReceiveTextMessage message: String, withNamespace protocolNamespace: String) {
        guard protocolNamespace == CastNamespace.input,
              let data = message.data(using: .utf8),
              let event = try? JSONDecoder().decode(InputEvent.self, from: data),
              let validated = try? event.validated() else { return }
        delegate?.castAdapter(self, didReceive: validated)
    }
}

#endif
