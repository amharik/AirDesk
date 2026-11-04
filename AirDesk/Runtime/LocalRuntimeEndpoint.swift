import Foundation

@MainActor
final class LocalRuntimeEndpoint: RuntimeEndpoint {
    let location: RuntimeLocation
    private let host: RuntimeHost
    private let provider: any DesktopRuntimeProvider
    private let choice: RuntimeChoice
    private let appearance: String
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
        provider: any DesktopRuntimeProvider,
        choice: RuntimeChoice,
        appearance: String
    ) {
        self.location = location
        self.host = host
        self.provider = provider
        self.choice = choice
        self.appearance = appearance
    }

    func start(context: RuntimeContext) async throws {
        if runtime != nil {
            await stop()
        }

        host.workspace = context.workspace
        host.sessionId = context.sessionId
        host.generation = context.generation

        let runtime = try provider.makeRuntime(choice: choice, appearance: appearance)
        self.runtime = runtime
        identifier = runtime.identifier
        capabilities = runtime.capabilities
        state = .preparing
        runtime.onStateChange = { [weak self] state in
            self?.state = state
        }

        do {
            try await provider.prepare(runtime, in: host)
            try await provider.loadWorkspace(context.workspace, into: runtime)
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
                guard let self, let runtime = self.runtime else { return }
                await self.provider.suspend(runtime)
            }
        case .resume:
            Task { [weak self] in
                guard let self, let runtime = self.runtime else { return }
                try? await self.provider.resume(runtime)
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
        await provider.shutdown(runtime)
        state = .stopped
    }
}
