import XCTest
@testable import AirDesk

final class NativeWorkspaceStoreTests: XCTestCase {
    func testMissingStoreReturnsNil() throws {
        let (store, _) = try makeStore()

        XCTAssertNil(try store.load())
        XCTAssertTrue(try store.loadJournal().isEmpty)
    }

    func testFirstCommitAssignsRevisionCheckpointAndHash() throws {
        let (store, _) = try makeStore()

        let committed = try store.commit(makeManifest(), expectedRevision: nil)

        XCTAssertEqual(committed.revision, 1)
        XCTAssertEqual(committed.recovery.checkpointSeq, 1)
        XCTAssertEqual(committed.recovery.journalSequence, 1)
        XCTAssertEqual(committed.recovery.lastCheckpointId, "checkpoint.1")
        XCTAssertEqual(committed.recovery.integrityHash, try committed.computedIntegrityHash())
        XCTAssertEqual(try store.load(), committed)
    }

    func testCommitWithExpectedRevisionIncrementsRevisionAndCheckpoint() throws {
        let (store, _) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)

        var second = first
        second.metadata.name = "Second"
        let committed = try store.commit(second, expectedRevision: 1)

        XCTAssertEqual(committed.revision, 2)
        XCTAssertEqual(committed.recovery.checkpointSeq, 2)
        XCTAssertEqual(committed.recovery.journalSequence, 2)
        XCTAssertEqual(committed.metadata.name, "Second")
        XCTAssertEqual(try store.load(), committed)
    }

    func testFirstCommitRejectsAnExistingWorkspace() throws {
        let (store, _) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)

        XCTAssertThrowsError(try store.commit(first, expectedRevision: nil)) { error in
            XCTAssertEqual(
                error as? WorkspaceStoreError,
                .revisionConflict(expected: nil, current: 1)
            )
        }
    }

    func testStaleRevisionIsRejectedWithoutChangingState() throws {
        let (store, _) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)

        XCTAssertThrowsError(try store.commit(first, expectedRevision: 0)) { error in
            XCTAssertEqual(
                error as? WorkspaceStoreError,
                .revisionConflict(expected: 0, current: 1)
            )
        }

        XCTAssertEqual(try store.load(), first)
        XCTAssertEqual(try store.loadJournal().count, 1)
    }

    func testJournalAppendsOneEntryPerCommit() throws {
        let (store, _) = try makeStore()
        var manifest = try store.commit(makeManifest(), expectedRevision: nil)
        manifest = try store.commit(manifest, expectedRevision: 1)
        _ = try store.commit(manifest, expectedRevision: 2)

        let entries = try store.loadJournal()

        XCTAssertEqual(entries.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(entries.map(\.revision), [1, 2, 3])
        XCTAssertEqual(entries.map(\.checkpointSeq), [1, 2, 3])
    }

    func testJournalReplayIgnoresAnEntryAheadOfTheCommittedManifest() throws {
        let (store, _) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)

        var orphan = first
        orphan.revision = 99
        orphan.metadata.name = "Orphan"
        _ = try store.appendJournal(orphan)

        let loaded = try store.load()

        XCTAssertEqual(loaded?.revision, 1)
        XCTAssertEqual(loaded?.metadata.name, "Test Workspace")
        XCTAssertNil(store.lastRecoveryWarning)
    }

    func testCorruptManifestRecoversFromLatestJournalEntry() throws {
        let (store, directory) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)
        var second = first
        second.metadata.name = "Second"
        let committed = try store.commit(second, expectedRevision: 1)

        let manifestURL = directory.appendingPathComponent(NativeWorkspaceStore.manifestFileName)
        try Data("{not json".utf8).write(to: manifestURL)

        let recovered = try store.load()

        XCTAssertEqual(recovered?.revision, 2)
        XCTAssertEqual(recovered?.metadata.name, "Second")
        XCTAssertEqual(recovered?.recovery.integrityHash, committed.recovery.integrityHash)
        XCTAssertEqual(store.lastRecoveryWarning, .corruptManifest)
    }

    func testIntegrityMismatchRecoversFromJournal() throws {
        let (store, directory) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)
        var second = first
        second.metadata.name = "Second"
        let committed = try store.commit(second, expectedRevision: 1)

        let manifestURL = directory.appendingPathComponent(NativeWorkspaceStore.manifestFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var tampered = committed
        tampered.metadata.name = "Tampered"
        try encoder.encode(tampered).write(to: manifestURL)

        let recovered = try store.load()

        XCTAssertEqual(recovered?.revision, 2)
        XCTAssertEqual(recovered?.metadata.name, "Second")
        XCTAssertEqual(store.lastRecoveryWarning, .integrityMismatch)
    }

    func testCorruptJournalTailIsSkipped() throws {
        let (store, directory) = try makeStore()
        _ = try store.commit(makeManifest(), expectedRevision: nil)

        let journalURL = directory.appendingPathComponent(NativeWorkspaceStore.journalFileName)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{partial".utf8))
        try handle.close()

        let entries = try store.loadJournal()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(store.lastRecoveryWarning, .corruptJournal(line: 2))
    }

    func testUnsupportedSchemaFailsClosedWithoutJournal() throws {
        let (store, directory) = try makeStore()
        var future = makeManifest()
        future.schemaVersion = 99

        let manifestURL = directory.appendingPathComponent(NativeWorkspaceStore.manifestFileName)
        try JSONEncoder().encode(future).write(to: manifestURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? WorkspaceStoreError, .unsupportedSchemaVersion(99))
        }
    }

    func testRelaunchLoadsCommittedManifestAndJournal() throws {
        let (store, directory) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)
        var second = first
        second.metadata.name = "Second"
        let committed = try store.commit(second, expectedRevision: 1)

        let relaunched = try NativeWorkspaceStore(directory: directory)

        XCTAssertEqual(try relaunched.load(), committed)
        XCTAssertEqual(try relaunched.loadJournal().map(\.revision), [1, 2])
    }

    func testMissingManifestRecoversFromJournalAndRewritesManifest() throws {
        let (store, directory) = try makeStore()
        let committed = try store.commit(makeManifest(), expectedRevision: nil)
        let manifestURL = directory.appendingPathComponent(NativeWorkspaceStore.manifestFileName)
        try FileManager.default.removeItem(at: manifestURL)

        let relaunched = try NativeWorkspaceStore(directory: directory)

        XCTAssertEqual(try relaunched.load(), committed)
        XCTAssertEqual(relaunched.lastRecoveryWarning, .manifestMissing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testFutureSchemaFailsClosedEvenWithRecoverableJournal() throws {
        let (store, directory) = try makeStore()
        _ = try store.commit(makeManifest(), expectedRevision: nil)
        let manifestURL = directory.appendingPathComponent(NativeWorkspaceStore.manifestFileName)
        let data = try Data(contentsOf: manifestURL)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: manifestURL)

        let relaunched = try NativeWorkspaceStore(directory: directory)

        XCTAssertThrowsError(try relaunched.load()) { error in
            XCTAssertEqual(error as? WorkspaceStoreError, .unsupportedSchemaVersion(2))
        }
        let persisted = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        XCTAssertEqual(persisted["schemaVersion"] as? Int, 2)
    }

    func testInterruptedTemporaryManifestIsIgnored() throws {
        let (store, directory) = try makeStore()
        let committed = try store.commit(makeManifest(), expectedRevision: nil)
        let temporaryURL = directory.appendingPathComponent("workspace.json.tmp-crash")
        try Data("{partial".utf8).write(to: temporaryURL)

        let relaunched = try NativeWorkspaceStore(directory: directory)

        XCTAssertEqual(try relaunched.load(), committed)
        XCTAssertNil(relaunched.lastRecoveryWarning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryURL.path))
    }

    func testManifestWriteFailureLeavesPreviousRevisionAddressable() throws {
        let (store, directory) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)
        var second = first
        second.metadata.name = "Second"

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: directory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: directory.path
            )
        }

        XCTAssertThrowsError(try store.commit(second, expectedRevision: 1)) { error in
            guard let storeError = error as? WorkspaceStoreError,
                  case .writeFailed = storeError else {
                XCTFail("Expected write failure, got \(error)")
                return
            }
        }

        XCTAssertEqual(try store.load(), first)
    }

    func testCorruptJournalMiddleLineFailsWhenReadDirectly() throws {
        let (store, directory) = try makeStore()
        var manifest = try store.commit(makeManifest(), expectedRevision: nil)
        manifest.metadata.name = "Second"
        _ = try store.commit(manifest, expectedRevision: 1)

        let journalURL = directory.appendingPathComponent(NativeWorkspaceStore.journalFileName)
        let text = try String(contentsOf: journalURL, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.insert("{broken", at: 1)
        try lines.joined(separator: "\n").write(to: journalURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.loadJournal()) { error in
            XCTAssertEqual(error as? WorkspaceStoreError, .corruptJournal(line: 2))
        }
    }

    func testCorruptJournalTailIsRepairedBeforeNextAppend() throws {
        let (store, directory) = try makeStore()
        let first = try store.commit(makeManifest(), expectedRevision: nil)

        let journalURL = directory.appendingPathComponent(NativeWorkspaceStore.journalFileName)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{partial".utf8))
        try handle.close()

        var second = first
        second.metadata.name = "Second"
        _ = try store.commit(second, expectedRevision: 1)

        let entries = try store.loadJournal()
        XCTAssertEqual(entries.map(\.sequence), [1, 2])
        XCTAssertEqual(entries.map(\.revision), [1, 2])
    }

    private func makeStore() throws -> (NativeWorkspaceStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirDeskWorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return (try NativeWorkspaceStore(directory: directory), directory)
    }

    private func makeManifest() -> WorkspaceManifest {
        WorkspaceManifest(
            id: "workspace.test",
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            metadata: WorkspaceMetadata(
                name: "Test Workspace",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
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
                        WorkspaceRuntimeTarget(provider: "wanix", world: "wasip1", architectures: ["wasm32"])
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
            ]
        )
    }
}
