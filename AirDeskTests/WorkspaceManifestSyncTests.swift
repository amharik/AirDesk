import XCTest
@testable import AirDesk

final class WorkspaceManifestSyncTests: XCTestCase {
    func testManifestSnapshotRoundTripsAllSynchronizedFields() throws {
        let manifest = makeManifest()
        let snapshot = try manifest.syncSnapshot()
        let restored = try WorkspaceManifest.applying(snapshot, to: manifest)

        XCTAssertEqual(snapshot.workspaceId, manifest.id)
        XCTAssertEqual(snapshot.hostEpoch, manifest.hostEpoch)
        XCTAssertEqual(snapshot.workspaceSeq, manifest.workspaceSeq)
        XCTAssertEqual(snapshot.revision, manifest.revision)
        XCTAssertEqual(snapshot.metadata, manifest.mergeMetadata.fields)
        XCTAssertEqual(restored, manifest)
    }

    func testMergedSnapshotAppliesToBaseWithoutLosingLocalCreatedAt() throws {
        let local = makeManifest()
        let remote = makeManifest()
        var localSnapshot = try local.syncSnapshot()
        var remoteSnapshot = try remote.syncSnapshot()
        localSnapshot.fields["metadata.name"] = WorkspaceSyncLWWValue(
            value: .string("local"),
            revision: 1,
            deviceId: "device-a"
        ).json
        remoteSnapshot.fields["metadata.name"] = WorkspaceSyncLWWValue(
            value: .string("remote"),
            revision: 2,
            deviceId: "device-b"
        ).json
        remoteSnapshot.fields["preferences"] = WorkspaceSyncLWWValue(
            value: .object(["values": .object(["theme": .string("dark")])]),
            revision: 6,
            deviceId: "device-b"
        ).json
        remoteSnapshot.workspaceSeq = 8
        remoteSnapshot.revision = 8

        let merged = WorkspaceSyncMerge.mergeSnapshots(local: localSnapshot, remote: remoteSnapshot)
        XCTAssertEqual(merged.status, .applied)
        let applied = try WorkspaceManifest.applying(merged.snapshot, to: local)
        XCTAssertEqual(applied.metadata.name, "remote")
        XCTAssertEqual(applied.metadata.createdAt, local.metadata.createdAt)
        XCTAssertEqual(applied.preferences.values["theme"], "dark")
        XCTAssertEqual(applied.layout.focusOrder, local.layout.focusOrder)
        XCTAssertEqual(applied.workspaceSeq, 9)
    }

    func testRejectsForeignWorkspaceAndInvalidField() throws {
        let manifest = makeManifest()
        var snapshot = try manifest.syncSnapshot()
        snapshot.workspaceId = "other"
        XCTAssertThrowsError(try WorkspaceManifest.applying(snapshot, to: manifest)) {
            XCTAssertEqual($0 as? WorkspaceManifestSyncError, .workspaceMismatch)
        }

        snapshot = try manifest.syncSnapshot()
        snapshot.fields["metadata.name"] = .number(42)
        XCTAssertThrowsError(try WorkspaceManifest.applying(snapshot, to: manifest)) {
            XCTAssertEqual($0 as? WorkspaceManifestSyncError, .invalidField("metadata.name"))
        }
    }

    func testNullableFieldsRemainNil() throws {
        let manifest = makeManifest()
        let snapshot = try manifest.syncSnapshot()
        let lastActive = try XCTUnwrap(snapshot.fields["metadata.lastActiveDeviceId"])
        let activeWindow = try XCTUnwrap(snapshot.fields["layout.activeWindowId"])
        XCTAssertEqual(WorkspaceSyncLWWValue(json: lastActive)?.value, .null)
        XCTAssertEqual(WorkspaceSyncLWWValue(json: activeWindow)?.value, .null)
        let restored = try WorkspaceManifest.applying(snapshot, to: manifest)
        XCTAssertNil(restored.metadata.lastActiveDeviceId)
        XCTAssertNil(restored.layout.activeWindowId)
    }

    private func makeManifest() -> WorkspaceManifest {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let application = WorkspaceApplication(
            id: "app.terminal",
            version: "1.0.0",
            name: "Terminal",
            entrypoint: "bin/terminal",
            runtimeTargets: [
                WorkspaceRuntimeTarget(provider: "wasi", world: "wasi:cli", architectures: ["wasm32"])
            ],
            requiredCapabilities: ["display"],
            presentation: .foreground,
            permissions: ["display"],
            quotas: WorkspaceQuotas(workers: 2, memoryBytes: 1024, cpuMillis: 100, handles: 8, persistedBytes: 0),
            lifecycle: WorkspaceApplicationLifecycle(cooperativeCheckpoint: true)
        )
        let instance = WorkspaceApplicationInstance(
            id: "instance.terminal",
            applicationId: application.id,
            desiredState: .running,
            placement: WorkspacePlacement(deviceId: "device-a", providerId: "wasi"),
            configuration: ["shell": "zsh"]
        )
        var manifest = WorkspaceManifest(
            id: "ws-1",
            revision: 5,
            workspaceSeq: 3,
            owner: WorkspaceOwner(identityId: "owner", displayName: "Owner"),
            metadata: WorkspaceMetadata(
                name: "Desk",
                createdAt: now,
                updatedAt: now,
                lastActiveDeviceId: nil
            ),
            layout: WorkspaceLayout(
                displays: [
                    WorkspaceDisplay(
                        id: "display.main",
                        name: "Main",
                        bounds: WorkspaceRect(x: 0, y: 0, width: 1440, height: 900),
                        isPrimary: true
                    )
                ],
                windows: [
                    WorkspaceWindow(
                        id: "window.terminal",
                        instanceId: instance.id,
                        displayId: "display.main",
                        bounds: WorkspaceRect(x: 10, y: 20, width: 800, height: 500),
                        isMinimized: false,
                        surface: "terminal"
                    )
                ],
                focusOrder: ["window.terminal"],
                activeWindowId: nil
            ),
            applications: [application],
            instances: [instance],
            executionBindings: [
                WorkspaceExecutionBinding(
                    instanceId: instance.id,
                    preferredProviderId: "wasi",
                    fallbackPolicy: .localOnly,
                    pinnedWorld: "wasi:cli"
                )
            ],
            resources: [
                WorkspaceResourceReference(
                    id: "resource.workspace",
                    kind: .applicationData,
                    providerId: "filesystem",
                    resourceId: "workspace",
                    accessPolicy: .workspace,
                    persistence: .durable
                )
            ],
            preferences: WorkspacePreferences(values: ["theme": "light"])
        )
        manifest.hostEpoch = 2
        return manifest
    }
}
