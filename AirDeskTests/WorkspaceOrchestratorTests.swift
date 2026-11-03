import XCTest
@testable import AirDesk

final class WorkspaceOrchestratorTests: XCTestCase {
    func testOpenCreatesWorkspaceAndReturnsSnapshot() throws {
        let (orchestrator, _, _, _) = try makeOrchestrator()

        let snapshot = try orchestrator.open(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Test Workspace",
            id: "workspace.test"
        )

        XCTAssertEqual(snapshot.manifest.id, "workspace.test")
        XCTAssertEqual(snapshot.manifest.workspaceSeq, 0)
        XCTAssertEqual(snapshot.manifest.recovery.hostEpoch, 1)
        XCTAssertTrue(snapshot.observed.isEmpty)
    }

    func testOpenLoadsExistingWorkspaceWithoutNewRevision() throws {
        let (orchestrator, _, store, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)

        let reopened = try orchestrator.open(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Ignored",
            id: "ignored"
        )

        XCTAssertEqual(reopened.manifest.id, "workspace.test")
        XCTAssertEqual(try store.load()?.revision, 1)
    }

    func testAttachAddsDesiredInstanceAndBinding() throws {
        let (orchestrator, host, store, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)

        let manifest = try orchestrator.attach(makeInstance(), preferredProviderId: "wanix")

        XCTAssertEqual(manifest.instances.map(\.id), ["instance.terminal"])
        XCTAssertEqual(manifest.executionBindings.map(\.instanceId), ["instance.terminal"])
        XCTAssertEqual(manifest.executionBindings.first?.preferredProviderId, "wanix")
        XCTAssertEqual(manifest.workspaceSeq, 2)
        XCTAssertEqual(host.workspaceSeq, 2)
        XCTAssertEqual(try store.load(), manifest)
    }

    func testAttachRejectsMissingApplication() throws {
        let (orchestrator, _, store, _) = try makeOrchestrator()
        let initial = try openWorkspace(orchestrator)

        XCTAssertThrowsError(try orchestrator.attach(makeInstance())) { error in
            XCTAssertEqual(
                error as? WorkspaceOrchestratorError,
                .applicationMissing(instanceId: "instance.terminal", applicationId: "app.terminal")
            )
        }

        XCTAssertEqual(try store.load(), initial)
    }

    func testAttachRejectsDuplicateInstance() throws {
        let (orchestrator, host, store, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)
        let attached = try orchestrator.attach(makeInstance())

        XCTAssertThrowsError(try orchestrator.attach(makeInstance())) { error in
            XCTAssertEqual(
                error as? WorkspaceOrchestratorError,
                .instanceAlreadyExists("instance.terminal")
            )
        }

        XCTAssertEqual(try store.load(), attached)
    }

    func testPlaceSetsDesiredPlacement() throws {
        let (orchestrator, host, _, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)
        _ = try orchestrator.attach(makeInstance())

        let manifest = try orchestrator.place(
            instanceId: "instance.terminal",
            deviceId: "device.test",
            providerId: "wanix"
        )

        XCTAssertEqual(
            manifest.instances.first?.placement,
            WorkspacePlacement(deviceId: "device.test", providerId: "wanix")
        )
        XCTAssertEqual(manifest.workspaceSeq, 3)
    }

    func testPlaceRejectsMissingInstance() throws {
        let (orchestrator, _, store, _) = try makeOrchestrator()
        let initial = try openWorkspace(orchestrator)

        XCTAssertThrowsError(try orchestrator.place(
            instanceId: "instance.unknown",
            deviceId: nil,
            providerId: nil
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceOrchestratorError,
                .instanceMissing("instance.unknown")
            )
        }

        XCTAssertEqual(try store.load(), initial)
    }

    func testReconcileStoresObservedStateWithoutMutatingWorkspace() throws {
        let (orchestrator, host, store, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)
        let attached = try orchestrator.attach(makeInstance())
        let revisionBefore = try store.load()?.revision
        let sequenceBefore = host.workspaceSeq

        let report = try orchestrator.reconcile([
            ApplicationInstanceStatus(
                instanceId: "instance.terminal",
                observedState: .running,
                runtimeProviderId: "wanix",
                runtimeInstanceId: "runtime.1",
                deviceId: "device.test"
            )
        ])

        XCTAssertEqual(report.observed.map(\.instanceId), ["instance.terminal"])
        XCTAssertEqual(report.observed.first?.observedState, .running)
        XCTAssertTrue(report.desiredRunningWithoutObservation.isEmpty)
        XCTAssertEqual(try store.load(), attached)
        XCTAssertEqual(try store.load()?.revision, revisionBefore)
        XCTAssertEqual(host.workspaceSeq, sequenceBefore)
        XCTAssertEqual(orchestrator.status(for: "instance.terminal")?.observedState, .running)
    }

    func testObservedFailureDoesNotRewriteDesiredState() throws {
        let (orchestrator, host, store, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)
        let attached = try orchestrator.attach(makeInstance())

        let status = try orchestrator.markUnavailable(
            instanceId: "instance.terminal",
            reason: "provider disconnected"
        )

        XCTAssertEqual(status.observedState, .unavailable)
        XCTAssertEqual(status.lastError, "provider disconnected")
        XCTAssertEqual(try store.load(), attached)
        XCTAssertEqual(try store.load()?.instances.first?.desiredState, .running)
        XCTAssertEqual(try orchestrator.snapshot().observed.first?.observedState, .unavailable)
    }

    func testReconcileReportsDesiredRunningWithoutObservation() throws {
        let (orchestrator, host, _, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)
        _ = try orchestrator.attach(makeInstance())

        let report = try orchestrator.reconcile([])

        XCTAssertEqual(report.desiredRunningWithoutObservation, ["instance.terminal"])
        XCTAssertTrue(report.observed.isEmpty)
    }

    func testReconcileReportsUnavailableAndFailedFromLatestObservedState() throws {
        let (orchestrator, host, _, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)
        _ = try orchestrator.attach(makeInstance())

        var report = try orchestrator.reconcile([
            ApplicationInstanceStatus(
                instanceId: "instance.terminal",
                observedState: .unavailable,
                lastError: "offline"
            )
        ])
        XCTAssertEqual(report.unavailable, ["instance.terminal"])
        XCTAssertTrue(report.failed.isEmpty)

        report = try orchestrator.reconcile([
            ApplicationInstanceStatus(
                instanceId: "instance.terminal",
                observedState: .failed,
                lastError: "startup failed"
            )
        ])
        XCTAssertTrue(report.unavailable.isEmpty)
        XCTAssertEqual(report.failed, ["instance.terminal"])
    }

    func testReconcileIgnoresUnknownInstanceStatus() throws {
        let (orchestrator, host, _, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)
        _ = try orchestrator.attach(makeInstance())

        let report = try orchestrator.reconcile([
            ApplicationInstanceStatus(
                instanceId: "instance.unknown",
                observedState: .running
            )
        ])

        XCTAssertEqual(report.ignored, ["instance.unknown"])
        XCTAssertTrue(report.observed.isEmpty)
        XCTAssertNil(orchestrator.status(for: "instance.unknown"))
    }

    func testSnapshotIncludesDesiredAndObservedState() throws {
        let (orchestrator, host, _, _) = try makeOrchestrator()
        _ = try openWorkspace(orchestrator)
        _ = try installApplication(host)
        _ = try orchestrator.attach(makeInstance())
        _ = try orchestrator.reconcile([
            ApplicationInstanceStatus(
                instanceId: "instance.terminal",
                observedState: .running
            )
        ])

        let snapshot = try orchestrator.snapshot()

        XCTAssertEqual(snapshot.manifest.instances.first?.id, "instance.terminal")
        XCTAssertEqual(snapshot.observed.first?.observedState, .running)
    }

    private func openWorkspace(_ orchestrator: WorkspaceOrchestrator) throws -> WorkspaceManifest {
        try orchestrator.open(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Test Workspace",
            id: "workspace.test"
        ).manifest
    }

    private func installApplication(_ host: WorkspaceHost) throws -> WorkspaceManifest {
        guard let current = try host.load() else {
            throw WorkspaceOrchestratorError.workspaceMissing
        }
        return try host.mutate(expectedWorkspaceSeq: current.workspaceSeq) {
            $0.applications.append(makeApplication())
        }
    }

    private func makeOrchestrator(
        now: @escaping () -> Date = Date.init
    ) throws -> (WorkspaceOrchestrator, WorkspaceHost, NativeWorkspaceStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirDeskWorkspaceOrchestratorTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try NativeWorkspaceStore(directory: directory)
        let host = try WorkspaceHost(store: store, deviceId: "device.test", now: now)
        let orchestrator = WorkspaceOrchestrator(host: host, now: now)
        return (orchestrator, host, store, directory)
    }

    private func makeApplication() -> WorkspaceApplication {
        WorkspaceApplication(
            id: "app.terminal",
            version: "1.0.0",
            name: "Terminal",
            entrypoint: "terminal.wasm",
            runtimeTargets: [
                WorkspaceRuntimeTarget(provider: "wanix", world: "wasip1", architectures: ["wasm32"])
            ],
            requiredCapabilities: ["airdesk://pty/default"],
            presentation: .foreground,
            permissions: [],
            quotas: nil
        )
    }

    private func makeInstance() -> WorkspaceApplicationInstance {
        WorkspaceApplicationInstance(
            id: "instance.terminal",
            applicationId: "app.terminal",
            desiredState: .running,
            placement: nil,
            configuration: [:]
        )
    }
}
