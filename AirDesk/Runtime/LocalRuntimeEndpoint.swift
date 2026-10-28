import Foundation

@MainActor
final class LocalRuntimeEndpoint: RuntimeEndpoint {
    let location: RuntimeLocation
    private let host: RuntimeHost
    private let runtimeFactory: () -> any DesktopRuntime
    private var runtime: (any DesktopRuntime)?

    private(set) var identifier = "Wanix"
    private(set) var state: RuntimeState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    private(set) var capabilities: RuntimeCapabilities = .wanixDesktop
    var onStateChange: ((RuntimeState) -> Void)?

    init(
        location: RuntimeLocation = .phone,
        host: RuntimeHost,
        runtimeFactory: @escaping () -> any DesktopRuntime
    ) {
        self.location = location
        self.host = host
        self.runtimeFactory = runtimeFactory
    }

    func start(context: RuntimeContext) async throws {
        if runtime != nil {
            await stop()
        }

        host.workspace = context.workspace
        host.sessionId = context.sessionId

        let runtime = runtimeFactory()
        self.runtime = runtime
        identifier = runtime.identifier
        capabilities = runtime.capabilities
        state = .preparing
        runtime.onStateChange = { [weak self] state in
            self?.state = state
        }

        do {
            try await runtime.prepare(in: host)
            try await runtime.loadWorkspace(context.workspace)
            state = runtime.state
        } catch {
            state = .failed
            throw error
        }
    }

    func send(_ event: InputEvent) {
        guard acceptsInput else { return }
        runtime?.dispatch(event)
    }

    func sendControl(_ control: RuntimeControl) {
        switch control {
        case .workspace(let workspace):
            host.surface.sendControl(
                type: "workspace",
                payload: ["name": workspace.name, "runtime": workspace.runtime]
            )
        case .appearance(let appearance):
            host.surface.sendControl(
                type: "appearance",
                payload: ["appearance": appearance]
            )
        case .suspend:
            Task { [weak self] in
                await self?.runtime?.suspend()
            }
        case .resume:
            Task { [weak self] in
                try? await self?.runtime?.resume()
            }
        case .shutdown:
            Task { [weak self] in
                await self?.stop()
            }
        }
    }

    func stop() async {
        guard let runtime else {
            state = .stopped
            return
        }
        runtime.onStateChange = nil
        self.runtime = nil
        await runtime.shutdown()
        state = .stopped
    }
}
