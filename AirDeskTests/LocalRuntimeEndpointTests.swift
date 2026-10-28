import XCTest
@testable import AirDesk

@MainActor
final class LocalRuntimeEndpointTests: XCTestCase {
    func testStartPreparesAndLoadsRuntime() async throws {
        let surface = DesktopSurface()
        let host = SurfaceRuntimeHost(surface: surface)
        let runtime = FakeDesktopRuntime()
        let endpoint = LocalRuntimeEndpoint(host: host) { runtime }
        let workspace = Workspace.default

        try await endpoint.start(context: RuntimeContext(
            sessionId: "ads-test",
            workspace: workspace,
            appearance: "dark"
        ))

        XCTAssertEqual(host.sessionId, "ads-test")
        XCTAssertEqual(host.workspace, workspace)
        XCTAssertEqual(runtime.preparedHost?.sessionId, "ads-test")
        XCTAssertEqual(runtime.preparedHost?.workspace, workspace)
        XCTAssertEqual(endpoint.identifier, "Fake Wanix")
        XCTAssertEqual(endpoint.state, .ready)
        XCTAssertTrue(endpoint.acceptsInput)
    }

    func testSendDispatchesInput() async throws {
        let runtime = FakeDesktopRuntime()
        let endpoint = LocalRuntimeEndpoint(host: SurfaceRuntimeHost(surface: DesktopSurface())) {
            runtime
        }
        try await endpoint.start(context: context)
        let event = InputEvent.make(.keyDown, sessionId: "ads-test", seq: 1, key: "a")

        endpoint.send(event)

        XCTAssertEqual(runtime.dispatchedEvents, [event])
    }

    func testStopIsIdempotent() async throws {
        let runtime = FakeDesktopRuntime()
        let endpoint = LocalRuntimeEndpoint(host: SurfaceRuntimeHost(surface: DesktopSurface())) {
            runtime
        }
        try await endpoint.start(context: context)

        await endpoint.stop()
        await endpoint.stop()

        XCTAssertEqual(runtime.shutdownCount, 1)
        XCTAssertEqual(endpoint.state, .stopped)
        XCTAssertFalse(endpoint.acceptsInput)
    }

    func testLateRuntimeStateIsIgnoredAfterStop() async throws {
        let runtime = FakeDesktopRuntime()
        let endpoint = LocalRuntimeEndpoint(host: SurfaceRuntimeHost(surface: DesktopSurface())) {
            runtime
        }
        try await endpoint.start(context: context)
        await endpoint.stop()

        runtime.emitState(.ready)

        XCTAssertEqual(endpoint.state, .stopped)
    }

    private var context: RuntimeContext {
        RuntimeContext(sessionId: "ads-test", workspace: .default, appearance: "dark")
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
