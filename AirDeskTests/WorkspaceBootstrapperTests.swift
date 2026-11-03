import XCTest
@testable import AirDesk

final class WorkspaceBootstrapperTests: XCTestCase {
    func testFirstBootCreatesWorkspaceAndReportsCreated() throws {
        let (bootstrapper, _) = try makeBootstrapper()

        let report = try bootstrapper.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Wanix"
        )

        XCTAssertEqual(report.outcome, .created)
        XCTAssertEqual(report.workspaceName, "Wanix")
        XCTAssertNil(report.recoveryWarning)
        XCTAssertTrue(report.instances.isEmpty)
        XCTAssertFalse(report.needsAttention)
        XCTAssertEqual(try bootstrapper.store.load()?.id, report.workspaceId)
    }

    func testSecondBootRestoresSameWorkspaceWithoutNewRevision() throws {
        let (bootstrapper, directory) = try makeBootstrapper()
        let first = try bootstrapper.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Wanix"
        )

        let relaunched = try WorkspaceBootstrapper(
            store: NativeWorkspaceStore(directory: directory),
            deviceId: "device.test"
        )
        let second = try relaunched.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Ignored"
        )

        XCTAssertEqual(second.outcome, .restored)
        XCTAssertEqual(second.workspaceId, first.workspaceId)
        XCTAssertEqual(second.workspaceName, "Wanix")
        XCTAssertEqual(try relaunched.store.load()?.revision, 1)
    }

    func testBootRecoversCorruptManifestAndReportsRecovered() throws {
        let (bootstrapper, directory) = try makeBootstrapper()
        let created = try bootstrapper.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Wanix"
        )
        let manifestURL = directory.appendingPathComponent(NativeWorkspaceStore.manifestFileName)
        try Data("{not json".utf8).write(to: manifestURL)

        let relaunched = try WorkspaceBootstrapper(
            store: NativeWorkspaceStore(directory: directory),
            deviceId: "device.test"
        )
        let report = try relaunched.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Ignored"
        )

        XCTAssertEqual(report.outcome, .recovered)
        XCTAssertEqual(report.recoveryWarning, .corruptManifest)
        XCTAssertEqual(report.workspaceId, created.workspaceId)
        XCTAssertTrue(report.needsAttention)
    }

    func testBootReportsDesiredRunningInstanceAsRestarted() throws {
        let (bootstrapper, _) = try makeBootstrapper()
        _ = try bootstrapper.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Wanix"
        )
        try installInstances([makeInstance()], in: bootstrapper.host)

        let report = try bootstrapper.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Ignored"
        )

        XCTAssertEqual(report.instances, [.restarted(instanceId: "instance.one")])
    }

    func testReportMapsObservedRuntimeStates() throws {
        let (bootstrapper, _) = try makeBootstrapper()
        _ = try bootstrapper.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Wanix"
        )
        try installInstances([
            makeInstance(id: "instance.running"),
            makeInstance(id: "instance.starting"),
            makeInstance(id: "instance.failed"),
            makeInstance(id: "instance.unavailable")
        ], in: bootstrapper.host)
        let manifest = try XCTUnwrap(try bootstrapper.host.load())

        let report = bootstrapper.makeReport(
            manifest,
            outcome: .restored,
            warning: nil,
            observed: [
                ApplicationInstanceStatus(instanceId: "instance.running", observedState: .running),
                ApplicationInstanceStatus(instanceId: "instance.starting", observedState: .starting),
                ApplicationInstanceStatus(
                    instanceId: "instance.failed",
                    observedState: .failed,
                    lastError: "startup failed"
                ),
                ApplicationInstanceStatus(
                    instanceId: "instance.unavailable",
                    observedState: .unavailable,
                    lastError: "offline"
                )
            ]
        )

        XCTAssertEqual(report.instances, [
            .reconnected(instanceId: "instance.running"),
            .restarted(instanceId: "instance.starting"),
            .lost(instanceId: "instance.failed", reason: "startup failed"),
            .lost(instanceId: "instance.unavailable", reason: "offline")
        ])
        XCTAssertTrue(report.needsAttention)
    }

    func testReportMapsStoppedDesiredStateToRestored() throws {
        let (bootstrapper, _) = try makeBootstrapper()
        _ = try bootstrapper.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Wanix"
        )
        try installInstances([
            makeInstance(id: "instance.stopped", desiredState: .stopped),
            makeInstance(id: "instance.suspended", desiredState: .suspended)
        ], in: bootstrapper.host)
        let manifest = try XCTUnwrap(try bootstrapper.host.load())

        let report = bootstrapper.makeReport(manifest, outcome: .restored, warning: nil, observed: [])

        XCTAssertEqual(report.instances, [
            .restored(instanceId: "instance.stopped"),
            .restored(instanceId: "instance.suspended")
        ])
    }

    func testFutureSchemaPreventsBoot() throws {
        let (bootstrapper, directory) = try makeBootstrapper()
        _ = try bootstrapper.restore(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Wanix"
        )
        let manifestURL = directory.appendingPathComponent(NativeWorkspaceStore.manifestFileName)
        let data = try Data(contentsOf: manifestURL)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: manifestURL)

        XCTAssertThrowsError(try WorkspaceBootstrapper(
            store: NativeWorkspaceStore(directory: directory),
            deviceId: "device.test"
        )) { error in
            XCTAssertEqual(error as? WorkspaceStoreError, .unsupportedSchemaVersion(2))
        }
    }

    private func makeBootstrapper() throws -> (WorkspaceBootstrapper, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirDeskWorkspaceBootTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try NativeWorkspaceStore(directory: directory)
        let bootstrapper = try WorkspaceBootstrapper(store: store, deviceId: "device.test")
        return (bootstrapper, directory)
    }

    private func installInstances(
        _ instances: [WorkspaceApplicationInstance],
        in host: WorkspaceHost
    ) throws {
        guard let current = try host.load() else {
            throw WorkspaceHostError.workspaceMissing
        }
        _ = try host.mutate(expectedWorkspaceSeq: current.workspaceSeq) { manifest in
            manifest.applications = [makeApplication()]
            manifest.instances = instances
        }
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
            requiredCapabilities: [],
            presentation: .foreground,
            permissions: [],
            quotas: nil
        )
    }

    private func makeInstance(
        id: String = "instance.one",
        desiredState: WorkspaceDesiredState = .running
    ) -> WorkspaceApplicationInstance {
        WorkspaceApplicationInstance(
            id: id,
            applicationId: "app.terminal",
            desiredState: desiredState,
            placement: nil,
            configuration: [:]
        )
    }
}
