import XCTest
@testable import AirDesk

final class RuntimeRegistryTests: XCTestCase {
    func testSelectsWanixForWasip1AndNativeForWasiCLI() throws {
        let registry = try makeRegistry()
        let wanixApp = makeApplication(
            id: "app.wanix",
            targets: [WorkspaceRuntimeTarget(provider: "wanix", world: "wasip1", architectures: ["wasm32"])]
        )
        let nativeApp = makeApplication(
            id: "app.native",
            targets: [WorkspaceRuntimeTarget(provider: "native", world: "wasi-cli@0.2", architectures: ["arm64"])]
        )

        let wanix = try registry.select(application: wanixApp)
        XCTAssertEqual(wanix.providerId, "wanix")
        XCTAssertEqual(wanix.world, .wasip1)
        XCTAssertTrue(wanix.rationale.contains("provider=wanix"))

        let native = try registry.select(application: nativeApp)
        XCTAssertEqual(native.providerId, "native")
        XCTAssertEqual(native.world, .wasiCLI02)
    }

    func testUnsupportedWorldAndCapabilityFailClosed() throws {
        let registry = try makeRegistry()
        let wrongWorld = makeApplication(
            id: "app.wrong-world",
            targets: [WorkspaceRuntimeTarget(provider: "wanix", world: "wasi-cli@0.2", architectures: ["wasm32"])]
        )
        XCTAssertThrowsError(try registry.select(application: wrongWorld))

        let unsupportedCapability = makeApplication(
            id: "app.camera",
            targets: [WorkspaceRuntimeTarget(provider: "wanix", world: "wasip1", architectures: ["wasm32"])],
            capabilities: ["camera"]
        )
        XCTAssertThrowsError(try registry.select(application: unsupportedCapability)) { error in
            XCTAssertEqual(error as? RuntimeProviderError, .capabilityUnsupported("camera"))
        }
    }

    func testQuotaAndThreadingRequirementsAreEnforced() throws {
        let registry = RuntimeRegistry()
        let limited = ManagedRuntimeProvider(descriptor: RuntimeProviderDescriptor(
            id: "limited",
            displayName: "Limited",
            location: .phone,
            version: "1",
            supportedWorlds: [.wasip1],
            architectures: ["wasm32"],
            capabilities: .wanixDesktop,
            threadingProfiles: [.singleThreaded],
            enforcedQuotas: [.memory]
        ))
        try registry.register(limited)

        let app = makeApplication(
            id: "app.quota",
            targets: [WorkspaceRuntimeTarget(provider: "limited", world: "wasip1", architectures: ["wasm32"])],
            quotas: WorkspaceQuotas(workers: 2)
        )
        XCTAssertThrowsError(try registry.select(application: app)) { error in
            XCTAssertEqual(
                error as? RuntimeProviderError,
                .quotaUnenforceable(providerId: "limited", quota: .workers)
            )
        }
        XCTAssertThrowsError(try registry.select(application: makeApplication(
            id: "app.sync",
            targets: [WorkspaceRuntimeTarget(provider: "limited", world: "wasip1", architectures: ["wasm32"])]
        ), threading: .sharedMemory)) { error in
            XCTAssertEqual(
                error as? RuntimeProviderError,
                .synchronizationUnavailable(providerId: "limited")
            )
        }
    }

    func testPreferredProviderFallbackAndLocalOnly() throws {
        let registry = RuntimeRegistry()
        let local = WanixRuntimeProvider()
        let remote = ManagedRuntimeProvider(descriptor: RuntimeProviderDescriptor(
            id: "remote",
            displayName: "Remote",
            location: .remote,
            version: "1",
            supportedWorlds: [.wasip1],
            architectures: ["wasm32"],
            capabilities: .wanixDesktop
        ))
        try registry.register(local)
        try registry.register(remote)

        let app = makeApplication(
            id: "app.multi",
            targets: [
                WorkspaceRuntimeTarget(provider: "wanix", world: "wasip1", architectures: ["wasm32"]),
                WorkspaceRuntimeTarget(provider: "remote", world: "wasip1", architectures: ["wasm32"])
            ]
        )
        let binding = WorkspaceExecutionBinding(
            instanceId: "i",
            preferredProviderId: "wanix",
            fallbackPolicy: .localOnly
        )
        XCTAssertEqual(try registry.select(application: app, binding: binding).providerId, "wanix")

        let denyBinding = WorkspaceExecutionBinding(
            instanceId: "i",
            preferredProviderId: "native",
            fallbackPolicy: .deny
        )
        XCTAssertThrowsError(try registry.select(application: app, binding: denyBinding))
    }

    func testUnavailablePreferredProviderReportsTypedError() throws {
        let registry = RuntimeRegistry()
        try registry.register(NativeRuntimeProvider(availability: .unavailable))
        let app = makeApplication(
            id: "app.native",
            targets: [WorkspaceRuntimeTarget(provider: "native", world: "wasi-cli@0.2", architectures: ["arm64"])]
        )
        let binding = WorkspaceExecutionBinding(
            instanceId: "i",
            preferredProviderId: "native",
            fallbackPolicy: .deny
        )
        XCTAssertThrowsError(try registry.select(application: app, binding: binding)) { error in
            XCTAssertEqual(error as? RuntimeProviderError, .providerUnavailable("native"))
        }
    }

    func testCircuitBreakerStateMachine() {
        var breaker = RuntimeCircuitBreaker(failureThreshold: 2, cooldown: 30)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        breaker.recordFailure(now: start)
        XCTAssertEqual(breaker.health, .degraded)
        breaker.recordFailure(now: start)
        XCTAssertEqual(breaker.health, .open)
        XCTAssertFalse(breaker.probeAllowed(now: start.addingTimeInterval(29)))
        XCTAssertTrue(breaker.probeAllowed(now: start.addingTimeInterval(31)))
        XCTAssertEqual(breaker.health, .halfOpen)
        XCTAssertFalse(breaker.probeAllowed(now: start.addingTimeInterval(32)))
        breaker.recordSuccess()
        XCTAssertEqual(breaker.health, .healthy)
    }

    private func makeRegistry() throws -> RuntimeRegistry {
        let registry = RuntimeRegistry()
        try registry.register(WanixRuntimeProvider())
        try registry.register(NativeRuntimeProvider())
        return registry
    }

    private func makeApplication(
        id: String,
        targets: [WorkspaceRuntimeTarget],
        capabilities: [String] = [],
        quotas: WorkspaceQuotas? = nil
    ) -> WorkspaceApplication {
        WorkspaceApplication(
            id: id,
            version: "1.0.0",
            name: id,
            entrypoint: "main",
            runtimeTargets: targets,
            requiredCapabilities: capabilities,
            presentation: .foreground,
            permissions: [],
            quotas: quotas
        )
    }
}
