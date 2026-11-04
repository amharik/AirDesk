import XCTest
@testable import AirDesk

@MainActor
final class LocalRuntimeEndpointTests: XCTestCase {
    func testStartPreparesAndLoadsRuntime() async throws {
        let surface = DesktopSurface()
        let host = SurfaceRuntimeHost(surface: surface)
        let runtime = FakeDesktopRuntime()
        let provider = TestDesktopRuntimeProvider(runtime: runtime)
        let endpoint = LocalRuntimeEndpoint(
            host: host,
            provider: provider,
            choice: .wanixDesktop,
            appearance: "dark"
        )
        let workspace = Workspace.default

        try await endpoint.start(context: RuntimeContext(
            sessionId: "ads-test",
            generation: 7,
            workspace: workspace,
            appearance: "dark"
        ))

        XCTAssertEqual(host.sessionId, "ads-test")
        XCTAssertEqual(host.generation, 7)
        XCTAssertEqual(host.workspace, workspace)
        XCTAssertEqual(runtime.preparedHost?.sessionId, "ads-test")
        XCTAssertEqual(runtime.preparedHost?.generation, 7)
        XCTAssertEqual(runtime.preparedHost?.workspace, workspace)
        XCTAssertEqual(endpoint.identifier, "Fake Wanix")
        XCTAssertEqual(endpoint.state, .ready)
        XCTAssertTrue(endpoint.acceptsInput)
        XCTAssertEqual(provider.prepareCount, 1)
        XCTAssertEqual(provider.loadWorkspaceCount, 1)
    }

    func testSendDispatchesInput() async throws {
        let runtime = FakeDesktopRuntime()
        let endpoint = makeEndpoint(runtime: runtime)
        try await endpoint.start(context: context)
        let event = InputEvent.make(.keyDown, sessionId: "ads-test", seq: 1, key: "a")

        endpoint.send(event)

        XCTAssertEqual(runtime.dispatchedEvents, [event])
    }

    func testStopIsIdempotent() async throws {
        let runtime = FakeDesktopRuntime()
        let endpoint = makeEndpoint(runtime: runtime)
        try await endpoint.start(context: context)

        await endpoint.stop()
        await endpoint.stop()

        XCTAssertEqual(runtime.shutdownCount, 1)
        XCTAssertEqual(endpoint.state, .stopped)
        XCTAssertFalse(endpoint.acceptsInput)
    }

    func testLateRuntimeStateIsIgnoredAfterStop() async throws {
        let runtime = FakeDesktopRuntime()
        let endpoint = makeEndpoint(runtime: runtime)
        try await endpoint.start(context: context)
        await endpoint.stop()

        runtime.emitState(.ready)

        XCTAssertEqual(endpoint.state, .stopped)
    }

    private var context: RuntimeContext {
        RuntimeContext(sessionId: "ads-test", workspace: .default, appearance: "dark")
    }

    private func makeEndpoint(runtime: FakeDesktopRuntime) -> LocalRuntimeEndpoint {
        LocalRuntimeEndpoint(
            host: SurfaceRuntimeHost(surface: DesktopSurface()),
            provider: TestDesktopRuntimeProvider(runtime: runtime),
            choice: .wanixDesktop,
            appearance: "dark"
        )
    }
}

@MainActor
private final class TestDesktopRuntimeProvider: DesktopRuntimeProvider {
    let descriptor = RuntimeProviderDescriptor(
        id: "test",
        displayName: "Test",
        location: .phone,
        version: "1",
        supportedWorlds: [.wasip1],
        architectures: ["wasm32"],
        capabilities: .wanixDesktop
    )
    let choices: Set<RuntimeChoice> = [.wanixDesktop]
    private let runtime: any DesktopRuntime
    private(set) var prepareCount = 0
    private(set) var loadWorkspaceCount = 0

    init(runtime: any DesktopRuntime) {
        self.runtime = runtime
    }

    func makeRuntime(choice: RuntimeChoice, appearance: String) throws -> any DesktopRuntime {
        runtime
    }

    func prepare(_ runtime: any DesktopRuntime, in host: RuntimeHost) async throws {
        prepareCount += 1
        try await runtime.prepare(in: host)
    }

    func loadWorkspace(_ workspace: Workspace, into runtime: any DesktopRuntime) async throws {
        loadWorkspaceCount += 1
        try await runtime.loadWorkspace(workspace)
    }
}

@MainActor
private final class FakeDesktopRuntime: DesktopRuntime {
    let identifier = "Fake Wanix"
    let capabilities: RuntimeCapabilities = .wanixDesktop
    private(set) var state: RuntimeState = .idle
    var onStateChange: ((RuntimeState) -> Void)?
    private(set) var preparedHost: RuntimeHost?
    private(set) var dispatchedEvents: [InputEvent] = []
    private(set) var shutdownCount = 0
    var prepareError: Error?

    func prepare(in host: RuntimeHost) async throws {
        preparedHost = host
        if let prepareError {
            state = .failed
            onStateChange?(state)
            throw prepareError
        }
        state = .ready
        onStateChange?(state)
    }

    func loadWorkspace(_ workspace: Workspace) async throws {}

    func dispatch(_ event: InputEvent) {
        dispatchedEvents.append(event)
    }

    func suspend() async {
        state = .suspended
        onStateChange?(state)
    }

    func resume() async throws {
        state = .ready
        onStateChange?(state)
    }

    func shutdown() async {
        shutdownCount += 1
        state = .stopped
    }

    func emitState(_ state: RuntimeState) {
        self.state = state
        onStateChange?(state)
    }
}
