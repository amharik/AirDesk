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

enum RuntimeFactory {
    @MainActor
    static func make(choice: RuntimeChoice, appearance: String) -> any DesktopRuntime {
        switch choice {
        case .wanixDesktop:
            return WanixRuntimeAdapter(choice: .wanixDesktop, appearance: appearance, capabilities: .wanixDesktop)
        case .wanixKernel:
            return WanixRuntimeAdapter(choice: .wanixKernel, appearance: appearance, capabilities: .wanixKernel)
        case .puter:
            return PuterRuntimeAdapter(appearance: appearance)
        }
    }
}

@MainActor
final class PuterRuntimeAdapter: DesktopRuntime {
    let identifier = "Puter"
    private(set) var state: RuntimeState = .idle {
        didSet { onStateChange?(state) }
    }
    let capabilities: RuntimeCapabilities = .puter
    var onStateChange: ((RuntimeState) -> Void)?
    private let appearance: String
    private weak var surface: DesktopSurface?

    init(appearance: String) {
        self.appearance = appearance
    }

    func prepare(in host: RuntimeHost) async throws {
        state = .preparing
        surface = host.surface
        do {
            try host.surface.load(choice: .puter, sessionId: host.sessionId, generation: host.generation, appearance: appearance)
            try await Self.waitForReady(on: host.surface, timeout: 18)
            state = .ready
        } catch {
            state = .failed
            throw error
        }
    }

    func loadWorkspace(_ workspace: Workspace) async throws {}

    func dispatch(_ event: RuntimeInputEvent) {
        surface?.send(event)
    }

    func suspend() async {
        state = .suspended
    }

    func resume() async throws {
        state = .ready
    }

    func shutdown() async {
        state = .stopped
    }

    static func waitForReady(on surface: DesktopSurface, timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await surface.waitUntilReady() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw DesktopSurfaceError.readyTimeout
            }
            try await group.next()
            group.cancelAll()
        }
    }
}
