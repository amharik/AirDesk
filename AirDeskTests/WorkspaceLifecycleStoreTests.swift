import XCTest
@testable import AirDesk

@MainActor
final class WorkspaceLifecycleStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testLifecycleActionsPublishObservedAndDesiredState() async throws {
        let (store, host) = try makeStore()
        try install(
            application: makeApplication(cooperativeCheckpoint: true),
            instance: makeInstance(),
            in: host
        )
        store.refresh()

        XCTAssertEqual(store.instances.count, 1)
        XCTAssertEqual(store.instances[0].observedState, .unavailable)
        XCTAssertEqual(store.instances[0].desiredState, .stopped)

        await store.start("instance.terminal")
        XCTAssertEqual(store.instances[0].observedState, .running)
        XCTAssertEqual(store.instances[0].desiredState, .running)
        XCTAssertEqual(store.instances[0].runtimeProviderId, "wanix")

        await store.suspend("instance.terminal")
        XCTAssertEqual(store.instances[0].observedState, .suspended)
        XCTAssertEqual(store.instances[0].desiredState, .suspended)

        await store.resume("instance.terminal")
        XCTAssertEqual(store.instances[0].observedState, .running)

        await store.checkpoint("instance.terminal")
        XCTAssertEqual(store.instances[0].observedState, .suspendedCheckpointed)
        XCTAssertEqual(store.instances[0].desiredState, .suspended)

        await store.resume("instance.terminal")
        XCTAssertEqual(store.instances[0].observedState, .running)

        await store.stop("instance.terminal")
        XCTAssertEqual(store.instances[0].observedState, .stopped)
        XCTAssertEqual(store.instances[0].desiredState, .stopped)
        XCTAssertNil(store.errorMessage)
    }

    func testUnsupportedCheckpointReportsErrorWithoutChangingState() async throws {
        let (store, host) = try makeStore()
        try install(
            application: makeApplication(cooperativeCheckpoint: false),
            instance: makeInstance(),
            in: host
        )
        await store.start("instance.terminal")

        await store.checkpoint("instance.terminal")

        XCTAssertEqual(
            store.errorMessage,
            "Application app.terminal does not support app-cooperative checkpoints."
        )
        XCTAssertEqual(store.instances[0].observedState, .running)
        XCTAssertEqual(store.instances[0].desiredState, .running)
        XCTAssertFalse(store.instances[0].canCheckpoint)
    }

    private func makeStore() throws -> (WorkspaceLifecycleStore, WorkspaceHost) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirDeskLifecycleStoreTests-\(UUID().uuidString)", isDirectory: true)
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
        return (
            WorkspaceLifecycleStore(host: host, now: { self.now }),
            host
        )
    }

    private func install(
        application: WorkspaceApplication,
        instance: WorkspaceApplicationInstance,
        in host: WorkspaceHost
    ) throws {
        let current = try XCTUnwrap(try host.load())
        _ = try host.mutate(expectedWorkspaceSeq: current.workspaceSeq) {
            $0.applications = [application]
            $0.instances = [instance]
        }
    }

    private func makeApplication(cooperativeCheckpoint: Bool) -> WorkspaceApplication {
        WorkspaceApplication(
            id: "app.terminal",
            version: "1.0.0",
            name: "Terminal",
            entrypoint: "terminal.wasm",
            runtimeTargets: [
                WorkspaceRuntimeTarget(
                    provider: "wanix",
                    world: "wasip1",
                    architectures: ["wasm32"]
                )
            ],
            requiredCapabilities: [],
            presentation: .foreground,
            permissions: [],
            quotas: nil,
            lifecycle: WorkspaceApplicationLifecycle(
                cooperativeCheckpoint: cooperativeCheckpoint
            )
        )
    }

    private func makeInstance() -> WorkspaceApplicationInstance {
        WorkspaceApplicationInstance(
            id: "instance.terminal",
            applicationId: "app.terminal",
            desiredState: .stopped,
            placement: nil,
            configuration: [:]
        )
    }
}
