import Foundation

@MainActor
protocol IrohFabricInputRouting: AnyObject {
    var isConnected: Bool { get }
    func sendInput(_ event: InputEvent) -> Bool
}

extension IrohFabricPeer: IrohFabricInputRouting {}

@MainActor
final class SessionInputTransport: InputTransport {
    enum Route: Equatable {
        case endpoint
        case cast
    }

    var route: Route = .endpoint
    var forwardsToFabric = false
    weak var endpoint: (any RuntimeEndpoint)?
    weak var cast: CastSessionCoordinator?
    weak var fabric: (any IrohFabricInputRouting)?

    var isAvailable: Bool {
        if forwardsToFabric, fabric?.isConnected == true {
            return true
        }
        switch route {
        case .endpoint:
            return endpoint?.acceptsInput == true
        case .cast:
            if let endpoint {
                return endpoint.acceptsInput
            }
            return cast?.isReady == true
        }
    }

    func send(_ event: InputEvent, on channel: InputTransportChannel) {
        print("[AirDeskDebug] transport send \(event.type) channel=\(channel.rawValue) route=\(route) fabric=\(forwardsToFabric) available=\(isAvailable) endpoint=\(endpoint != nil)")
        guard isAvailable else { return }
        guard (try? InputChannelRouter.validate(event, on: channel)) != nil else {
            print("[AirDeskDebug] transport drop \(event.type) wrong channel \(channel.rawValue)")
            return
        }
        if forwardsToFabric, let fabric, fabric.isConnected, fabric.sendInput(event) {
            return
        }
        switch route {
        case .endpoint:
            endpoint?.send(event)
        case .cast:
            if let endpoint {
                endpoint.send(event)
            } else {
                cast?.send(event)
            }
        }
    }
}
