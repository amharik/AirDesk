import XCTest
@testable import AirDesk

final class WorkspaceSyncMergeTests: XCTestCase {
    func testCanonicalValuesIgnoreObjectKeyOrder() {
        let left: WorkspaceSyncJSONValue = .object([
            "name": .string("desk"),
            "count": .number(2)
        ])
        let right: WorkspaceSyncJSONValue = .object([
            "count": .number(2),
            "name": .string("desk")
        ])
        XCTAssertEqual(left.canonicalString, right.canonicalString)
        XCTAssertTrue(WorkspaceSyncMerge.valuesEqual(left, right))
        XCTAssertFalse(WorkspaceSyncMerge.valuesEqual(left, .string("desk")))
    }

    func testLWWUsesRevisionThenDeviceIdAndDetectsAmbiguity() {
        let local = WorkspaceSyncLWWValue(value: .string("local"), revision: 2, deviceId: "a")
        let older = WorkspaceSyncLWWValue(value: .string("remote"), revision: 1, deviceId: "z")
        XCTAssertEqual(WorkspaceSyncMerge.mergeLWW(local: local, remote: older).winner, .local)

        let newerDevice = WorkspaceSyncLWWValue(value: .string("remote"), revision: 2, deviceId: "b")
        XCTAssertEqual(WorkspaceSyncMerge.mergeLWW(local: local, remote: newerDevice).winner, .remote)

        let sameValue = WorkspaceSyncLWWValue(value: .string("local"), revision: 2, deviceId: "a")
        let equal = WorkspaceSyncMerge.mergeLWW(local: local, remote: sameValue)
        XCTAssertEqual(equal.winner, .equal)
        XCTAssertNil(equal.conflict)

        let sameDevice = WorkspaceSyncLWWValue(value: .string("other"), revision: 2, deviceId: "a")
        let conflict = WorkspaceSyncMerge.mergeLWW(local: local, remote: sameDevice, path: "metadata.name")
        XCTAssertEqual(conflict.winner, .conflict)
        XCTAssertEqual(conflict.conflict?.reason, .ambiguousLWW)
        XCTAssertEqual(conflict.conflict?.path, "metadata.name")
    }

    func testAppendLogDedupesSortsAndFlagsConflictingDuplicates() {
        let local = [
            WorkspaceSyncAppendEntry(id: "b", value: .string("local"), revision: 2),
            WorkspaceSyncAppendEntry(id: "a", value: .string("one"), revision: 1)
        ]
        let remote = [
            WorkspaceSyncAppendEntry(id: "a", value: .string("one"), revision: 1),
            WorkspaceSyncAppendEntry(id: "b", value: .string("remote"), revision: 2),
            WorkspaceSyncAppendEntry(id: "c", value: .string("three"), revision: 3)
        ]

        let result = WorkspaceSyncMerge.mergeAppendLog(local: local, remote: remote, path: "events")
        XCTAssertEqual(result.entries.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(result.entries.first(where: { $0.id == "b" })?.value, .string("remote"))
        XCTAssertEqual(result.added, 1)
        XCTAssertTrue(result.duplicates.contains("a"))
        XCTAssertTrue(result.duplicates.contains("b"))
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts.first?.reason, .appendLogDuplicateConflict)
    }

    func testPatchAppliesLWWAndRejectsStaleCoordinates() {
        var snapshot = makeSnapshot(fields: ["metadata.name": lww("local", revision: 1, deviceId: "a")])
        snapshot.revision = 1
        let patch = makePatch(fields: [
            field("metadata.name", lww("remote", revision: 2, deviceId: "b"), revision: 2)
        ], revision: 2)

        let applied = WorkspaceSyncMerge.applyPatch(snapshot, patch)
        XCTAssertEqual(applied.status, .applied)
        XCTAssertEqual(applied.snapshot.workspaceSeq, 1)
        XCTAssertEqual(applied.snapshot.revision, 2)
        XCTAssertEqual(applied.snapshot.fields["metadata.name"], lww("remote", revision: 2, deviceId: "b"))
        XCTAssertEqual(applied.fieldResults.first?.winner, .remote)

        var wrongEpoch = patch
        wrongEpoch.hostEpoch = 2
        XCTAssertEqual(WorkspaceSyncMerge.applyPatch(snapshot, wrongEpoch).reason, .staleEpoch)

        wrongEpoch.hostEpoch = 4
        XCTAssertEqual(WorkspaceSyncMerge.applyPatch(snapshot, wrongEpoch).reason, .futureEpoch)

        var wrongSeq = patch
        wrongSeq.baseWorkspaceSeq = 1
        XCTAssertEqual(WorkspaceSyncMerge.applyPatch(snapshot, wrongSeq).reason, .futureSeq)

        var staleRevision = patch
        staleRevision.revision = 0
        XCTAssertEqual(WorkspaceSyncMerge.applyPatch(snapshot, staleRevision).reason, .staleRevision)

        var wrongWorkspace = patch
        wrongWorkspace.workspaceId = "ws-other"
        XCTAssertEqual(WorkspaceSyncMerge.applyPatch(snapshot, wrongWorkspace).reason, .workspaceMismatch)
    }

    func testPatchAddsAppendLogAndRejectsUnclassifiedManualField() {
        let snapshot = makeSnapshot(fields: [:])
        let appendPatch = makePatch(fields: [
            field("events", .string("started"), revision: 3, appendId: "event-1")
        ])
        let append = WorkspaceSyncMerge.applyPatch(snapshot, appendPatch)
        XCTAssertEqual(append.status, .applied)
        XCTAssertEqual(append.snapshot.fields["events"]?.arrayValue?.count, 1)
        XCTAssertEqual(append.snapshot.fields["events"]?.arrayValue?.first?.objectValue?["id"], .string("event-1"))

        let unclassified = WorkspaceSyncMerge.applyPatch(
            snapshot,
            makePatch(fields: [field("unknown", .string("value"), revision: 2)])
        )
        XCTAssertEqual(unclassified.status, .conflict)
        XCTAssertEqual(unclassified.conflicts.first?.reason, .unclassifiedField)
    }

    func testClassifiedManualFieldMergesWhenNewAndConflictsWhenDifferent() {
        let empty = makeSnapshot(fields: [:])
        let newValue = WorkspaceSyncMerge.applyPatch(
            empty,
            makePatch(fields: [field("settings", .string("remote"), revision: 2)])
        )
        XCTAssertEqual(newValue.status, .applied)
        XCTAssertEqual(newValue.snapshot.fields["settings"], .string("remote"))

        let snapshot = makeSnapshot(fields: ["settings": .string("local")])
        let conflicting = WorkspaceSyncMerge.applyPatch(
            snapshot,
            makePatch(fields: [field("settings", .string("remote"), revision: 2)])
        )
        XCTAssertEqual(conflicting.status, .conflict)
        XCTAssertEqual(conflicting.conflicts.first?.reason, .manualMerge)
    }

    func testSnapshotMergeCombinesFieldsAndKeepsLocalOnConflict() {
        var local = makeSnapshot(fields: [
            "metadata.name": lww("local", revision: 1, deviceId: "a"),
            "layout.focusOrder": .array([.string("window-a")])
        ])
        local.workspaceSeq = 4
        local.revision = 4
        var remote = makeSnapshot(fields: [
            "metadata.name": lww("remote", revision: 2, deviceId: "b"),
            "preferences": lww("dark", revision: 1, deviceId: "b")
        ])
        remote.workspaceSeq = 7
        remote.revision = 7

        let merged = WorkspaceSyncMerge.mergeSnapshots(local: local, remote: remote)
        XCTAssertEqual(merged.status, .applied)
        XCTAssertEqual(merged.snapshot.workspaceSeq, 8)
        XCTAssertEqual(merged.snapshot.revision, 8)
        XCTAssertEqual(merged.snapshot.fields["metadata.name"], lww("remote", revision: 2, deviceId: "b"))
        XCTAssertEqual(merged.snapshot.fields["layout.focusOrder"], .array([.string("window-a")]))
        XCTAssertEqual(merged.snapshot.fields["preferences"], lww("dark", revision: 1, deviceId: "b"))

        var conflicting = makeSnapshot(fields: ["settings": .string("local")])
        conflicting.workspaceSeq = 1
        var remoteConflict = makeSnapshot(fields: ["settings": .string("remote")])
        remoteConflict.workspaceSeq = 2
        let conflict = WorkspaceSyncMerge.mergeSnapshots(local: conflicting, remote: remoteConflict)
        XCTAssertEqual(conflict.status, .conflict)
        XCTAssertEqual(conflict.snapshot.fields["settings"], .string("local"))
    }

    func testCoreBackendMatchesNativeSnapshotMerge() throws {
        var local = makeSnapshot(fields: [
            "metadata.name": lww("local", revision: 1, deviceId: "a"),
            "layout.focusOrder": .array([.string("window-a")])
        ])
        local.workspaceSeq = 4
        local.revision = 4
        var remote = makeSnapshot(fields: [
            "metadata.name": lww("remote", revision: 2, deviceId: "b"),
            "preferences": lww("dark", revision: 1, deviceId: "b")
        ])
        remote.workspaceSeq = 7
        remote.revision = 7

        let native = WorkspaceSyncMerge.mergeSnapshots(local: local, remote: remote)
        let core = try WorkspaceSyncCoreMerge.mergeSnapshots(local: local, remote: remote)
        XCTAssertEqual(core.status, native.status)
        XCTAssertEqual(core.snapshot, native.snapshot)
        XCTAssertEqual(core.fieldResults, native.fieldResults)
        XCTAssertEqual(core.conflicts, native.conflicts)
    }

    func testOfflineQueueHaltsAndRetriesRemainingEdits() {
        let queue = WorkspaceSyncOfflineQueue()
        for index in 0 ..< 3 {
            queue.enqueue(field("value.\(index)", .string("v\(index)"), revision: UInt64(index + 1)))
        }
        var attempts = 0
        let first = queue.drain { _ in
            attempts += 1
            return attempts == 3
                ? makeResult(status: .conflict)
                : makeResult(status: .applied)
        }
        XCTAssertEqual(first.applied.count, 2)
        XCTAssertEqual(first.remaining.count, 1)
        XCTAssertEqual(first.haltedBy?.status, .conflict)
        XCTAssertEqual(queue.size, 1)

        let second = queue.drain { _ in makeResult(status: .applied) }
        XCTAssertEqual(second.applied.count, 1)
        XCTAssertEqual(queue.size, 0)
    }

    func testEngineOnlyAdvancesOnAcceptedPatches() {
        let initial = makeSnapshot(fields: ["metadata.name": lww("local", revision: 1, deviceId: "a")])
        let engine = WorkspaceSyncEngine(initial: initial)
        let accepted = engine.apply(
            patch: makePatch(fields: [
                field("metadata.name", lww("remote", revision: 2, deviceId: "b"), revision: 2)
            ], revision: 2)
        )
        XCTAssertEqual(accepted.status, .applied)
        XCTAssertEqual(engine.snapshot.fields["metadata.name"], lww("remote", revision: 2, deviceId: "b"))
        XCTAssertEqual(engine.recover(), engine.snapshot)

        let rejected = engine.apply(
            patch: makePatch(
                fields: [field("metadata.name", .string("bad"), revision: 3)],
                revision: 3,
                baseWorkspaceSeq: 1
            )
        )
        XCTAssertEqual(rejected.status, .conflict)
        XCTAssertEqual(engine.snapshot.fields["metadata.name"], lww("remote", revision: 2, deviceId: "b"))
    }

    func testSnapshotAndPatchCodableRoundTrip() throws {
        let snapshot = makeSnapshot(fields: ["metadata.name": lww("desk", revision: 3, deviceId: "device")])
        let patch = makePatch(fields: [
            field("events", .string("event"), revision: 4, appendId: "event-1")
        ], revision: 4)

        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let decodedSnapshot = try JSONDecoder().decode(WorkspaceSyncSnapshot.self, from: encodedSnapshot)
        XCTAssertEqual(decodedSnapshot, snapshot)

        let encodedPatch = try JSONEncoder().encode(patch)
        let decodedPatch = try JSONDecoder().decode(WorkspaceSyncPatch.self, from: encodedPatch)
        XCTAssertEqual(decodedPatch, patch)
    }

    private func makeSnapshot(fields: [String: WorkspaceSyncJSONValue]) -> WorkspaceSyncSnapshot {
        WorkspaceSyncSnapshot(
            workspaceId: "ws-1",
            hostEpoch: 3,
            workspaceSeq: 0,
            revision: 1,
            fields: fields,
            metadata: [
                WorkspaceFieldMetadata(path: "metadata.name", merge: .lww, sinceSchemaVersion: 1),
                WorkspaceFieldMetadata(path: "layout.focusOrder", merge: .lww, sinceSchemaVersion: 1),
                WorkspaceFieldMetadata(path: "preferences", merge: .lww, sinceSchemaVersion: 1),
                WorkspaceFieldMetadata(path: "events", merge: .appendLog, sinceSchemaVersion: 1),
                WorkspaceFieldMetadata(path: "settings", merge: .manual, sinceSchemaVersion: 1)
            ]
        )
    }

    private func makePatch(
        fields: [WorkspaceSyncFieldPatch],
        revision: UInt64 = 2,
        baseWorkspaceSeq: UInt64 = 0
    ) -> WorkspaceSyncPatch {
        WorkspaceSyncPatch(
            workspaceId: "ws-1",
            senderDeviceId: "device-b",
            hostEpoch: 3,
            baseWorkspaceSeq: baseWorkspaceSeq,
            revision: revision,
            fields: fields
        )
    }

    private func field(
        _ path: String,
        _ value: WorkspaceSyncJSONValue,
        revision: UInt64,
        appendId: String? = nil
    ) -> WorkspaceSyncFieldPatch {
        WorkspaceSyncFieldPatch(
            path: path,
            value: value,
            revision: revision,
            deviceId: "device-b",
            appendId: appendId
        )
    }

    private func lww(
        _ value: String,
        revision: UInt64,
        deviceId: String
    ) -> WorkspaceSyncJSONValue {
        WorkspaceSyncLWWValue(value: .string(value), revision: revision, deviceId: deviceId).json
    }

    private func makeResult(status: WorkspaceSyncApplyStatus) -> WorkspaceSyncApplyResult {
        WorkspaceSyncApplyResult(
            status: status,
            snapshot: makeSnapshot(fields: [:]),
            fieldResults: [],
            conflicts: []
        )
    }
}
