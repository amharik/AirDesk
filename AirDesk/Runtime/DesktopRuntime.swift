import Foundation

typealias RuntimeInputEvent = InputEvent

@MainActor
protocol DesktopRuntime: AnyObject {
    var identifier: String { get }
    var state: RuntimeState { get }
    var capabilities: RuntimeCapabilities { get }
    var onStateChange: ((RuntimeState) -> Void)? { get set }

    func prepare(in host: RuntimeHost) async throws
    func loadWorkspace(_ workspace: Workspace) async throws
    func dispatch(_ event: RuntimeInputEvent)
    func suspend() async
    func resume() async throws
    func shutdown() async
}

@MainActor
protocol RuntimeHost: AnyObject {
    var surface: DesktopSurface { get }
    var workspace: Workspace { get set }
    var sessionId: String { get set }
    var generation: Int { get set }
}

@MainActor
final class SurfaceRuntimeHost: RuntimeHost {
    let surface: DesktopSurface
    var workspace: Workspace
    var sessionId: String
    var generation: Int

    init(surface: DesktopSurface, workspace: Workspace = .default, sessionId: String = "", generation: Int = 0) {
        self.surface = surface
        self.workspace = workspace
        self.sessionId = sessionId
        self.generation = generation
    }
}
