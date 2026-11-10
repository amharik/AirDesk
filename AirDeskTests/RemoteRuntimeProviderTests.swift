import XCTest
@testable import AirDesk

final class RemoteRuntimeProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testMapsLifecycleAndCachesObservedStatus() async throws {
        let transport = MockRemoteRuntimeTransport(now: now)
        let provider = RemoteRuntimeProvider(
            transport: transport,
            descriptor: makeDescriptor(),
            now: { self.now }
        )
        let application = makeApplication()
        let request = RuntimeCreateRequest(
            instanceId: "instance.remote",
            application: application,
            world: .wasip1
        )

        try await provider.create(request)
        XCTAssertEqual(provider.status(instanceId: request.instanceId)?.observedState, .stopped)

        try await provider.start(instanceId: request.instanceId)
        var status = try XCTUnwrap(provider.status(instanceId: request.instanceId))
        XCTAssertEqual(status.observedState, .running)
        XCTAssertEqual(status.runtimeProviderId, "remote")
        XCTAssertEqual(status.deviceId, "device.remote")

        try await provider.suspend(instanceId: request.instanceId)
        XCTAssertEqual(provider.status(instanceId: request.instanceId)?.observedState, .suspended)

        try await provider.checkpoint(instanceId: request.instanceId)
        XCTAssertEqual(
            provider.status(instanceId: request.instanceId)?.observedState,
            .suspendedCheckpointed
        )

        try await provider.resume(instanceId: request.instanceId)
        XCTAssertEqual(provider.status(instanceId: request.instanceId)?.observedState, .running)

        try await provider.stop(instanceId: request.instanceId)
        XCTAssertEqual(provider.status(instanceId: request.instanceId)?.observedState, .stopped)

        try await provider.destroy(instanceId: request.instanceId)
        XCTAssertNil(provider.status(instanceId: request.instanceId))
        XCTAssertEqual(
            transport.calls,
            ["create", "start", "suspend", "checkpoint", "resume", "stop", "destroy"]
        )
    }

    func testDisconnectPreservesObservedStateAndMarksProviderUnavailable() async throws {
        let transport = MockRemoteRuntimeTransport(now: now)
        let provider = RemoteRuntimeProvider(
            transport: transport,
            descriptor: makeDescriptor(),
            now: { self.now }
        )
        let request = RuntimeCreateRequest(
            instanceId: "instance.remote",
            application: makeApplication(),
            world: .wasip1
        )
        try await provider.create(request)
        try await provider.start(instanceId: request.instanceId)

        transport.nextError = .unavailable
        do {
            try await provider.suspend(instanceId: request.instanceId)
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertEqual(
                error as? RuntimeProviderError,
                .transportUnavailable(providerId: "remote")
            )
        }

        let descriptor = provider.descriptor
        XCTAssertEqual(descriptor.availability, .unavailable)
        XCTAssertEqual(descriptor.health, .open)
        let cached = try XCTUnwrap(provider.status(instanceId: request.instanceId))
        XCTAssertEqual(cached.observedState, .running)
        XCTAssertNotNil(cached.lastError)

        provider.reconnect()
        XCTAssertEqual(provider.descriptor.availability, .available)
        XCTAssertEqual(provider.descriptor.health, .healthy)
        XCTAssertEqual(provider.status(instanceId: request.instanceId)?.observedState, .running)
        XCTAssertNil(provider.status(instanceId: request.instanceId)?.lastError)
    }

    func testAuthorizationAndProtocolFailuresAreTyped() async throws {
        let transport = MockRemoteRuntimeTransport(now: now)
        let provider = RemoteRuntimeProvider(
            transport: transport,
            descriptor: makeDescriptor(),
            now: { self.now }
        )
        let request = RuntimeCreateRequest(
            instanceId: "instance.remote",
            application: makeApplication(),
            world: .wasip1
        )
        try await provider.create(request)

        transport.nextError = .unauthorized
        do {
            try await provider.start(instanceId: request.instanceId)
            XCTFail("Expected authorization failure")
        } catch {
            XCTAssertEqual(
                error as? RuntimeProviderError,
                .authorizationDenied(providerId: "remote")
            )
        }
        XCTAssertEqual(provider.descriptor.availability, .restricted)
        XCTAssertEqual(provider.descriptor.health, .degraded)

        transport.nextError = .protocolFailure("bad frame")
        do {
            try await provider.refreshStatus(instanceId: request.instanceId)
            XCTFail("Expected protocol failure")
        } catch {
            XCTAssertEqual(error as? RuntimeProviderError, .providerFailure("bad frame"))
        }
    }

    func testExplicitDeviceSelectionAndPlacementDiagnostics() throws {
        let transport = MockRemoteRuntimeTransport(now: now)
        let remote = RemoteRuntimeProvider(
            transport: transport,
            descriptor: makeDescriptor(),
            now: { self.now }
        )
        let registry = RuntimeRegistry(hostDeviceId: "device.host")
        try registry.register(WanixRuntimeProvider())
        try registry.register(remote)

        let application = makeApplication(targets: [
            WorkspaceRuntimeTarget(
                provider: "wanix",
                world: "wasip1",
                architectures: ["wasm32"]
            ),
            WorkspaceRuntimeTarget(
                provider: "remote",
                world: "wasip1",
                architectures: ["wasm32"]
            )
        ])

        let local = try registry.select(application: application)
        XCTAssertEqual(local.providerId, "wanix")
        XCTAssertEqual(local.deviceId, "device.host")
        XCTAssertEqual(local.diagnostics.first(where: { $0.outcome == .selected })?.providerId, "wanix")

        let remoteSelection = try registry.select(
            application: application,
            placement: WorkspacePlacement(deviceId: "device.remote")
        )
        XCTAssertEqual(remoteSelection.providerId, "remote")
        XCTAssertEqual(remoteSelection.deviceId, "device.remote")
        XCTAssertEqual(
            remoteSelection.diagnostics.first(where: { $0.outcome == .selected })?.reason,
            "selected by preferred, local-first, provider id and world ordering"
        )

        XCTAssertThrowsError(try registry.select(
            application: application,
            placement: WorkspacePlacement(deviceId: "device.missing")
        )) { error in
            XCTAssertEqual(error as? RuntimeProviderError, .deviceMismatch(deviceId: "device.missing"))
        }
    }

    func testRemoteProviderIsNotDefaultEnabled() {
        let registry = RuntimeRegistry.standard(hostDeviceId: "device.host")
        XCTAssertFalse(registry.descriptors.contains { $0.id == "remote" })
    }

    private func makeDescriptor() -> RuntimeProviderDescriptor {
        RuntimeProviderDescriptor(
            id: "remote",
            displayName: "Remote",
            location: .remote,
            deviceId: "device.remote",
            version: "1.0",
            supportedWorlds: [.wasip1],
            architectures: ["wasm32"],
            capabilities: .wanixDesktop
        )
    }

    private func makeApplication(
        targets: [WorkspaceRuntimeTarget] = [
            WorkspaceRuntimeTarget(
                provider: "remote",
                world: "wasip1",
                architectures: ["wasm32"]
            )
        ]
    ) -> WorkspaceApplication {
        WorkspaceApplication(
            id: "app.remote",
            version: "1.0.0",
            name: "Remote Terminal",
            entrypoint: "terminal.wasm",
            runtimeTargets: targets,
            requiredCapabilities: [],
            presentation: .foreground,
            permissions: [],
            quotas: nil,
            lifecycle: WorkspaceApplicationLifecycle(cooperativeCheckpoint: true)
        )
    }
}

private final class MockRemoteRuntimeTransport: RemoteRuntimeTransport {
    private let now: Date
    var calls: [String] = []
    var nextError: RemoteRuntimeTransportError?
    private var statuses: [String: ApplicationInstanceStatus] = [:]

    init(now: Date) {
        self.now = now
    }

    func create(_ request: RuntimeCreateRequest) async throws -> ApplicationInstanceStatus? {
        try record("create")
        let status = ApplicationInstanceStatus(
            instanceId: request.instanceId,
            observedState: .stopped,
            lastHeartbeat: now
        )
        statuses[request.instanceId] = status
        return status
    }

    func start(instanceId: String) async throws -> ApplicationInstanceStatus? {
        try record("start")
        return update(instanceId, state: .running)
    }

    func suspend(instanceId: String) async throws -> ApplicationInstanceStatus? {
        try record("suspend")
        return update(instanceId, state: .suspended)
    }

    func checkpoint(instanceId: String) async throws -> ApplicationInstanceStatus? {
        try record("checkpoint")
        return update(instanceId, state: .suspendedCheckpointed)
    }

    func resume(instanceId: String) async throws -> ApplicationInstanceStatus? {
        try record("resume")
        return update(instanceId, state: .running)
    }

    func stop(instanceId: String) async throws -> ApplicationInstanceStatus? {
        try record("stop")
        return update(instanceId, state: .stopped)
    }

    func destroy(instanceId: String) async throws {
        try record("destroy")
        statuses.removeValue(forKey: instanceId)
    }

    func status(instanceId: String) async throws -> ApplicationInstanceStatus? {
        try record("status")
        return statuses[instanceId]
    }

    private func record(_ call: String) throws {
        calls.append(call)
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    private func update(
        _ instanceId: String,
        state: WorkspaceObservedState
    ) -> ApplicationInstanceStatus? {
        var status = statuses[instanceId] ?? ApplicationInstanceStatus(
            instanceId: instanceId,
            observedState: state
        )
        status.observedState = state
        status.lastHeartbeat = now
        statuses[instanceId] = status
        return status
    }
}
