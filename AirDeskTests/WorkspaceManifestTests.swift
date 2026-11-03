import XCTest
@testable import AirDesk

final class WorkspaceManifestTests: XCTestCase {
    func testCreateProducesCurrentSchemaAndDefaults() {
        let manifest = WorkspaceManifest.create(
            id: "workspace.test",
            name: "Test Workspace",
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(manifest.schemaVersion, WorkspaceManifest.currentSchemaVersion)
        XCTAssertEqual(manifest.revision, 1)
        XCTAssertEqual(manifest.workspaceSeq, 0)
        XCTAssertEqual(manifest.hostEpoch, 1)
        XCTAssertEqual(manifest.mergeMetadata.mergeClass(for: "metadata.name"), .lww)
        XCTAssertEqual(manifest.mergeMetadata.mergeClass(for: "applications.app.test"), .manual)
        XCTAssertNoThrow(try manifest.validate())
    }

    func testJSONRoundTripPreservesManifest() throws {
        let manifest = try makeValidManifest()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WorkspaceManifest.self, from: encoder.encode(manifest))

        XCTAssertEqual(decoded, manifest)
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        var manifest = try makeValidManifest()
        manifest.schemaVersion = 99

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(error as? WorkspaceManifestError, .unsupportedSchemaVersion(99))
        }
    }

    func testDuplicateApplicationIdentifiersAreRejected() throws {
        var manifest = try makeValidManifest()
        manifest.applications.append(manifest.applications[0])

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? WorkspaceManifestError,
                .duplicateIdentifier(kind: "application", id: "app.terminal")
            )
        }
    }

    func testMissingApplicationReferenceIsRejected() throws {
        var manifest = try makeValidManifest()
        manifest.instances[0].applicationId = "app.missing"

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? WorkspaceManifestError,
                .missingApplication(instanceId: "instance.terminal", applicationId: "app.missing")
            )
        }
    }

    func testMissingWindowInstanceIsRejected() throws {
        var manifest = try makeValidManifest()
        manifest.layout.windows[0].instanceId = "instance.missing"

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? WorkspaceManifestError,
                .missingInstanceForWindow(windowId: "window.terminal", instanceId: "instance.missing")
            )
        }
    }

    func testMergeClassUsesMostSpecificPathAndDefaultsToManual() throws {
        var manifest = try makeValidManifest()
        manifest.mergeMetadata = WorkspaceMergeMetadata(fields: [
            WorkspaceFieldMetadata(path: "layout", merge: .manual, sinceSchemaVersion: 1),
            WorkspaceFieldMetadata(path: "layout.windows", merge: .lww, sinceSchemaVersion: 1)
        ])

        XCTAssertEqual(manifest.mergeMetadata.mergeClass(for: "layout.windows.window.test"), .lww)
        XCTAssertEqual(manifest.mergeMetadata.mergeClass(for: "layout.displays"), .manual)
        XCTAssertEqual(manifest.mergeMetadata.mergeClass(for: "unknown.field"), .manual)
    }

    func testDefaultMergeMetadataCoversEverySyncableField() {
        let expected: [String: WorkspaceMergeClass] = [
            "metadata.name": .lww,
            "metadata.updatedAt": .lww,
            "metadata.lastActiveDeviceId": .lww,
            "layout.displays": .lww,
            "layout.windows": .lww,
            "layout.focusOrder": .lww,
            "layout.activeWindowId": .lww,
            "preferences": .lww,
            "applications": .manual,
            "instances": .manual,
            "executionBindings": .manual,
            "resources": .manual,
            "owner": .manual,
            "recovery": .manual
        ]

        let metadata = WorkspaceMergeMetadata.default
        XCTAssertEqual(metadata.fields.count, expected.count)
        XCTAssertEqual(Set(metadata.fields.map(\.path)).count, expected.count)
        for (path, mergeClass) in expected {
            XCTAssertEqual(metadata.mergeClass(for: path), mergeClass, path)
        }
    }

    func testMergeClassMatchesOnlyWholePathSegments() {
        let metadata = WorkspaceMergeMetadata(fields: [
            WorkspaceFieldMetadata(path: "layout.displays", merge: .lww, sinceSchemaVersion: 1),
            WorkspaceFieldMetadata(path: "instances", merge: .manual, sinceSchemaVersion: 1),
            WorkspaceFieldMetadata(path: "resources", merge: .appendLog, sinceSchemaVersion: 1)
        ])

        XCTAssertEqual(metadata.mergeClass(for: "layout.displays.display.main.bounds"), .lww)
        XCTAssertEqual(metadata.mergeClass(for: "layout.displaysX"), .manual)
        XCTAssertEqual(metadata.mergeClass(for: "instances.instance.terminal"), .manual)
        XCTAssertEqual(metadata.mergeClass(for: "resources.resource.home"), .appendLog)
        XCTAssertEqual(metadata.mergeClass(for: "unknown.field"), .manual)
    }

    func testDuplicateMergePathIsRejected() throws {
        var manifest = try makeValidManifest()
        manifest.mergeMetadata.fields.append(manifest.mergeMetadata.fields[0])

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? WorkspaceManifestError,
                .duplicateMergePath("metadata.name")
            )
        }
    }

    func testInvalidWindowBoundsAreRejected() throws {
        var manifest = try makeValidManifest()
        manifest.layout.windows[0].bounds.width = -1

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? WorkspaceManifestError,
                .invalidLayout("layout.windows.window.terminal.bounds")
            )
        }
    }

    private func makeValidManifest() throws -> WorkspaceManifest {
        let manifest = WorkspaceManifest(
            id: "workspace.test",
            revision: 7,
            workspaceSeq: 12,
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            metadata: WorkspaceMetadata(
                name: "Test Workspace",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
                lastActiveDeviceId: "device.test"
            ),
            layout: WorkspaceLayout(
                displays: [
                    WorkspaceDisplay(
                        id: "display.main",
                        name: "Main",
                        bounds: WorkspaceRect(x: 0, y: 0, width: 1920, height: 1080),
                        isPrimary: true
                    )
                ],
                windows: [
                    WorkspaceWindow(
                        id: "window.terminal",
                        instanceId: "instance.terminal",
                        displayId: "display.main",
                        bounds: WorkspaceRect(x: 80, y: 80, width: 800, height: 500),
                        isMinimized: false,
                        surface: "desktop"
                    )
                ],
                focusOrder: ["window.terminal"],
                activeWindowId: "window.terminal"
            ),
            applications: [
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
                    requiredCapabilities: ["airdesk://pty/default"],
                    presentation: .foreground,
                    permissions: [],
                    quotas: nil
                )
            ],
            instances: [
                WorkspaceApplicationInstance(
                    id: "instance.terminal",
                    applicationId: "app.terminal",
                    desiredState: .running,
                    placement: nil,
                    configuration: [:]
                )
            ],
            executionBindings: [
                WorkspaceExecutionBinding(
                    instanceId: "instance.terminal",
                    preferredProviderId: "wanix",
                    fallbackPolicy: .deny
                )
            ],
            resources: [
                WorkspaceResourceReference(
                    id: "resource.home",
                    kind: .runtimeVolume,
                    providerId: "device.test",
                    resourceId: "volume.home",
                    accessPolicy: .workspace,
                    persistence: .durable
                )
            ],
            preferences: WorkspacePreferences(values: ["appearance": "dark"]),
            recovery: WorkspaceRecovery(
                journalSequence: 4,
                checkpointSeq: 3,
                hostEpoch: 2,
                lastCheckpointId: "checkpoint.3",
                integrityHash: "sha256:test"
            )
        )
        try manifest.validate()
        return manifest
    }
}
