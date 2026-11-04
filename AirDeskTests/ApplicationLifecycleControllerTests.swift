import XCTest
@testable import AirDesk

final class ApplicationLifecycleControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testInstallStartPinsProviderAndWorldThenSuspendsCheckpointsAndStops() async throws {
        let (lifecycle, registry, host) = try makeLifecycle()
        let application = makeApplication()
        let instance = makeInstance(desiredState: .stopped)
        try install(application, instance, in: host)
        _ = registry

        let started = try await lifecycle.start(instanceId: instance.id)
        XCTAssertEqual(started.observedState, .running)
        var manifest = try XCTUnwrap(try host.load())
        XCTAssertEqual(manifest.instances[0].desiredState, .running)
        XCTAssertEqual(manifest.instances[0].placement?.providerId, "wanix")
        XCTAssertEqual(manifest.executionBindings.first?.pinnedWorld, "wasip1")

        let suspended = try await lifecycle.suspend(instanceId: instance.id)
        XCTAssertEqual(suspended.observedState, .suspended)
        manifest = try XCTUnwrap(try host.load())
        XCTAssertEqual(manifest.instances[0].desiredState, .suspended)

        let resumed = try await lifecycle.resume(instanceId: instance.id)
        XCTAssertEqual(resumed.observedState, .running)

        let checkpointed = try await lifecycle.checkpoint(instanceId: instance.id)
        XCTAssertEqual(checkpointed.observedState, .suspendedCheckpointed)
        manifest = try XCTUnwrap(try host.load())
        XCTAssertEqual(manifest.instances[0].desiredState, .suspended)

        let stopped = try await lifecycle.stop(instanceId: instance.id)
        XCTAssertEqual(stopped.observedState, .stopped)
        manifest = try XCTUnwrap(try host.load())
        XCTAssertEqual(manifest.instances[0].desiredState, .stopped)
    }

    func testQuotaFailureDoesNotChangeDesiredState() async throws {
        let (lifecycle, registry, host) = try makeLifecycle(useWanix: false)
        try registry.register(ManagedRuntimeProvider(descriptor: RuntimeProviderDescriptor(
            id: "limited",
            displayName: "Limited",
            location: .phone,
            version: "1",
            supportedWorlds: [.wasip1],
            architectures: ["wasm32"],
            capabilities: .wanixDesktop,
            enforcedQuotas: []
        )))
        let application = makeApplication(
            provider: "limited",
            quotas: WorkspaceQuotas(workers: 2)
        )
        let instance = makeInstance(desiredState: .stopped)
        try install(application, instance, in: host)

        do {
            _ = try await lifecycle.start(instanceId: instance.id)
            XCTFail("Expected quota failure")
        } catch {
            XCTAssertEqual(error as? ApplicationLifecycleError, .provider(
                .quotaUnenforceable(providerId: "limited", quota: .workers)
            ))
        }
        let manifest = try XCTUnwrap(try host.load())
        XCTAssertEqual(manifest.instances[0].desiredState, .stopped)
        XCTAssertNil(manifest.instances[0].placement)
    }

    func testNativeApplicationStartsWithoutWanix() async throws {
        let (lifecycle, _, host) = try makeLifecycle(useWanix: false)
        let application = makeApplication(
            provider: "native",
            world: "wasi-cli@0.2",
            architectures: ["arm64"]
        )
        let instance = makeInstance(desiredState: .stopped)
        try install(application, instance, in: host)

        let started = try await lifecycle.start(instanceId: instance.id)
        XCTAssertEqual(started.observedState, .running)
        XCTAssertEqual(started.runtimeProviderId, "native")

        let manifest = try XCTUnwrap(try host.load())
        XCTAssertEqual(manifest.instances[0].placement?.providerId, "native")
        XCTAssertEqual(manifest.executionBindings.first?.pinnedWorld, "wasi-cli@0.2")
    }

    func testUnsupportedWorldFailsClosed() async throws {
        let (lifecycle, _, host) = try makeLifecycle()
        let application = makeApplication(world: "wasi-cli@0.2")
        let instance = makeInstance(desiredState: .stopped)
        try install(application, instance, in: host)

        do {
            _ = try await lifecycle.start(instanceId: instance.id)
            XCTFail("Expected unsupported world failure")
        } catch {}
        let manifest = try XCTUnwrap(try host.load())
        XCTAssertEqual(manifest.instances[0].desiredState, .stopped)
    }

    func testReconcileReportsProviderStateWithoutRewritingDesiredState() async throws {
        let (lifecycle, _, host) = try makeLifecycle()
        let application = makeApplication()
        let instance = makeInstance(desiredState: .stopped)
        try install(application, instance, in: host)
        _ = try await lifecycle.start(instanceId: instance.id)

        let report = try lifecycle.reconcile()
        XCTAssertEqual(report.observed.first?.observedState, .running)
        XCTAssertTrue(report.failed.isEmpty)
        let manifest = try XCTUnwrap(try host.load())
        XCTAssertEqual(manifest.instances[0].desiredState, .running)
    }

    func testInstallAndUninstallEnforceReferences() throws {
        let (lifecycle, _, host) = try makeLifecycle()
        let application = makeApplication()
        _ = try lifecycle.install(application)
        XCTAssertThrowsError(try lifecycle.install(application))
        _ = try host.mutate(expectedWorkspaceSeq: try XCTUnwrap(try host.load()).workspaceSeq) {
            $0.instances = [self.makeInstance(desiredState: .stopped)]
        }
        XCTAssertThrowsError(try lifecycle.uninstall(applicationId: application.id)) { error in
            XCTAssertEqual(error as? ApplicationLifecycleError, .applicationInUse(application.id))
        }
    }

    private func makeLifecycle(
        useWanix: Bool = true
    ) throws -> (ApplicationLifecycleController, RuntimeRegistry, WorkspaceHost) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirDeskLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try NativeWorkspaceStore(directory: directory)
        let host = try WorkspaceHost(store: store, deviceId: "device.test", now: { self.now })
        _ = try host.create(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Test",
            id: "workspace.test"
        )
        let registry = RuntimeRegistry()
        if useWanix {
            try registry.register(WanixRuntimeProvider())
        }
        try registry.register(NativeRuntimeProvider())
        return (
            ApplicationLifecycleController(host: host, registry: registry, now: { self.now }),
            registry,
            host
        )
    }

    private func install(
        _ application: WorkspaceApplication,
        _ instance: WorkspaceApplicationInstance,
        in host: WorkspaceHost
    ) throws {
        let current = try XCTUnwrap(try host.load())
        _ = try host.mutate(expectedWorkspaceSeq: current.workspaceSeq) {
            $0.applications = [application]
            $0.instances = [instance]
        }
    }

    private func makeApplication(
        provider: String = "wanix",
        world: String = "wasip1",
        architectures: [String] = ["wasm32"],
        quotas: WorkspaceQuotas? = nil
    ) -> WorkspaceApplication {
        WorkspaceApplication(
            id: "app.terminal",
            version: "1.0.0",
            name: "Terminal",
            entrypoint: "terminal.wasm",
            runtimeTargets: [
                WorkspaceRuntimeTarget(
                    provider: provider,
                    world: world,
                    architectures: architectures
                )
            ],
            requiredCapabilities: [],
            presentation: .foreground,
            permissions: [],
            quotas: quotas
        )
    }

    private func makeInstance(
        desiredState: WorkspaceDesiredState = .running
    ) -> WorkspaceApplicationInstance {
        WorkspaceApplicationInstance(
            id: "instance.terminal",
            applicationId: "app.terminal",
            desiredState: desiredState,
            placement: nil,
            configuration: [:]
        )
    }
}
