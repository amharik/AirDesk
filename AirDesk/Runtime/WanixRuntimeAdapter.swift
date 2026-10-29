import Foundation
import OSLog

@MainActor
final class WanixRuntimeAdapter: DesktopRuntime {
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "WanixRuntime")
    let identifier: String
    let capabilities: RuntimeCapabilities
    private(set) var state: RuntimeState = .idle {
        didSet { onStateChange?(state) }
    }

    var onStateChange: ((RuntimeState) -> Void)?

    private let choice: RuntimeChoice
    private let appearance: String
    private weak var surface: DesktopSurface?
    private var workspace: Workspace = .default

    init(choice: RuntimeChoice, appearance: String, capabilities: RuntimeCapabilities) {
        self.choice = choice
        self.appearance = appearance
        self.capabilities = capabilities
        self.identifier = choice == .wanixKernel ? "Wanix Kernel" : "Wanix Desktop"
    }

    func prepare(in host: RuntimeHost) async throws {
        state = .preparing
        let surface = host.surface
        self.surface = surface
        self.workspace = host.workspace

        surface.onStateChange = { [weak self] stateName in
            guard let self else { return }
            if stateName == "recovering", self.state == .ready {
                self.state = .recovering
            }
        }

        do {
            state = .loading
            try surface.load(choice: choice, sessionId: host.sessionId, generation: host.generation, appearance: appearance)
            #if targetEnvironment(simulator)
            let readyTimeout: TimeInterval = 90
            #else
            let readyTimeout: TimeInterval = 35
            #endif
            try await PuterRuntimeAdapter.waitForReady(on: surface, timeout: readyTimeout)
            state = .ready
            logger.info("Wanix runtime ready: \(self.identifier, privacy: .public)")
        } catch {
            state = .failed
            logger.error("Wanix runtime failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func loadWorkspace(_ workspace: Workspace) async throws {
        self.workspace = workspace
        surface?.sendControl(type: "workspace", payload: ["name": workspace.name, "runtime": workspace.runtime])
    }

    func dispatch(_ event: RuntimeInputEvent) {
        print("[AirDeskDebug] adapter dispatch \(event.type) state=\(state) surface=\(surface != nil)")
        guard state.allowsInput || state == .recovering else { return }
        surface?.send(event)
    }

    func suspend() async {
        surface?.sendControl(type: "suspend")
        state = .suspended
    }

    func resume() async throws {
        surface?.sendControl(type: "resume")
        state = .ready
    }

    func shutdown() async {
        surface?.sendControl(type: "shutdown")
        state = .stopped
    }
}
