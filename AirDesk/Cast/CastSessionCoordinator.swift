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

    var onInput: ((InputEvent) -> Void)?
    let adapter: any GoogleCastAdapter
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "Cast")

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
    }

    func send(_ event: InputEvent) {
        guard connectedDevice != nil else { return }
        adapter.send(event)
    }

    func clearError() {
        lastError = nil
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
        if state == .idle {
            connectedDevice = nil
        }
    }

    func castAdapter(_ adapter: any GoogleCastAdapter, didFail error: Error) {
        lastError = error.localizedDescription
        state = .failed
        logger.error("Cast failure: \(error.localizedDescription, privacy: .public)")
    }

    func castAdapter(_ adapter: any GoogleCastAdapter, didReceive event: InputEvent) {
        onInput?(event)
    }
}
