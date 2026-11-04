import XCTest
@testable import AirDesk

@MainActor
final class SessionCoordinatorRuntimeProviderTests: XCTestCase {
    func testSessionStartsRuntimeThroughRegisteredProvider() async throws {
        let provider = RecordingDesktopRuntimeProvider()
        let registry = DesktopRuntimeProviderRegistry()
        try registry.register(provider)

        let settings = AppSettings()
        settings.runtimeChoice = .wanixDesktop
        let coordinator = SessionCoordinator(
            settings: settings,
            diagnostics: PerformanceMetrics(),
            display: DisplayCoordinator(),
            cast: CastSessionCoordinator(adapter: StubProviderCastAdapter()),
            entitlements: EntitlementManager(),
            runtimeProviders: registry
        )

        coordinator.beginConnection(to: .previewDevice)
        try await waitUntilReady(coordinator)

        XCTAssertEqual(coordinator.runtimeName, "Recording")
        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(provider.prepareCount, 1)
        XCTAssertEqual(provider.loadWorkspaceCount, 1)
        XCTAssertEqual(provider.runtime?.loadedWorkspace, .default)

        coordinator.disconnect()
        for _ in 0..<120 where provider.shutdownCount == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(provider.shutdownCount, 1)
    }

    private func waitUntilReady(_ coordinator: SessionCoordinator) async throws {
        for _ in 0..<120 {
            if coordinator.phase == .ready { return }
            if coordinator.phase == .failed {
                XCTFail("Session failed: \(coordinator.lastError ?? "unknown")")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Session did not become ready")
    }
}

@MainActor
private final class RecordingDesktopRuntimeProvider: DesktopRuntimeProvider {
    let descriptor = RuntimeProviderDescriptor(
        id: "recording",
        displayName: "Recording",
        location: .phone,
        version: "1",
        supportedWorlds: [.wasip1],
        architectures: ["wasm32"],
        capabilities: .wanixDesktop
    )
    let choices: Set<RuntimeChoice> = [.wanixDesktop]
    private(set) var runtime: RecordingDesktopRuntime?
    private(set) var prepareCount = 0
    private(set) var loadWorkspaceCount = 0
    private(set) var shutdownCount = 0

    func makeRuntime(choice: RuntimeChoice, appearance: String) throws -> any DesktopRuntime {
        let runtime = RecordingDesktopRuntime()
        self.runtime = runtime
        return runtime
    }

    func prepare(_ runtime: any DesktopRuntime, in host: RuntimeHost) async throws {
        prepareCount += 1
        try await runtime.prepare(in: host)
    }

    func loadWorkspace(_ workspace: Workspace, into runtime: any DesktopRuntime) async throws {
        loadWorkspaceCount += 1
        try await runtime.loadWorkspace(workspace)
    }

    func shutdown(_ runtime: any DesktopRuntime) async {
        shutdownCount += 1
        await runtime.shutdown()
    }
}

@MainActor
private final class RecordingDesktopRuntime: DesktopRuntime {
    let identifier = "Recording"
    private(set) var state: RuntimeState = .idle
    let capabilities: RuntimeCapabilities = .wanixDesktop
    var onStateChange: ((RuntimeState) -> Void)?
    private(set) var loadedWorkspace: Workspace?

    func prepare(in host: RuntimeHost) async throws {
        state = .ready
        onStateChange?(state)
    }

    func loadWorkspace(_ workspace: Workspace) async throws {
        loadedWorkspace = workspace
    }

    func dispatch(_ event: RuntimeInputEvent) {}
    func suspend() async {}
    func resume() async throws {}
    func shutdown() async {}
}

@MainActor
private final class StubProviderCastAdapter: GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = true
    weak var delegate: (any GoogleCastAdapterDelegate)?
    private(set) var discoveredDevices: [CastDevice] = []

    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to device: CastDevice) async throws {}
    func disconnect() {}
    func send(_ event: InputEvent) {}
    func sendControl(_ message: CastControlMessage) {}
}
