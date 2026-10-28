import Foundation

struct RuntimeContext: Equatable, Sendable {
    var sessionId: String
    var workspace: Workspace
    var appearance: String
}

enum RuntimeControl: Equatable, Sendable {
    case workspace(Workspace)
    case appearance(String)
    case suspend
    case resume
    case shutdown
}

@MainActor
protocol RuntimeEndpoint: AnyObject {
    var location: RuntimeLocation { get }
    var identifier: String { get }
    var state: RuntimeState { get }
    var capabilities: RuntimeCapabilities { get }
    var onStateChange: ((RuntimeState) -> Void)? { get set }
    var acceptsInput: Bool { get }

    func start(context: RuntimeContext) async throws
    func send(_ event: InputEvent)
    func sendControl(_ control: RuntimeControl)
    func stop() async
}

extension RuntimeEndpoint {
    var acceptsInput: Bool {
        state == .ready || state == .recovering
    }
}
