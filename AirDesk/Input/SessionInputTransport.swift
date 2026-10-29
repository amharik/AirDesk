import Foundation

@MainActor
final class SessionInputTransport: InputTransport {
    enum Route: Equatable {
        case endpoint
        case cast
    }

    var route: Route = .endpoint
    weak var endpoint: (any RuntimeEndpoint)?
    weak var cast: CastSessionCoordinator?

    var isAvailable: Bool {
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

    func send(_ event: InputEvent) {
        print("[AirDeskDebug] transport send \(event.type) route=\(route) available=\(isAvailable) endpoint=\(endpoint != nil)")
        guard isAvailable else { return }
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
