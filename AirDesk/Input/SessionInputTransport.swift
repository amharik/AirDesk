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
            return cast?.connectedDevice != nil
        }
    }

    func send(_ event: InputEvent) {
        guard isAvailable else { return }
        switch route {
        case .endpoint:
            endpoint?.send(event)
        case .cast:
            cast?.send(event)
        }
    }
}
