import XCTest
@testable import AirDesk

final class WorkspaceHostTests: XCTestCase {
    private enum TestFailure: Error {
        case expected
    }

    func testCreateWritesInitialHostMetadata() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (host, store, _) = try makeHost(now: { now })
        let owner = WorkspaceOwner(identityId: "person.test", displayName: "Tester")

        let manifest = try host.create(owner: owner, name: "Test Workspace", id: "workspace.test")

        XCTAssertEqual(manifest.id, "workspace.test")
        XCTAssertEqual(manifest.workspaceSeq, 0)
        XCTAssertEqual(manifest.revision, 1)
        XCTAssertEqual(manifest.recovery.hostEpoch, 1)
        XCTAssertEqual(manifest.metadata.lastActiveDeviceId, "device.test")
        XCTAssertEqual(manifest.metadata.createdAt, now)
        XCTAssertEqual(manifest.metadata.updatedAt, now)
        XCTAssertEqual(try store.load(), manifest)
        XCTAssertEqual(host.workspaceSeq, 0)
        XCTAssertEqual(host.hostEpoch, 1)
    }

    func testCreateRejectsAnExistingWorkspace() throws {
        let (host, _, _) = try makeHost()
        let owner = WorkspaceOwner(identityId: "person.test", displayName: "Tester")
        _ = try host.create(owner: owner, name: "Test Workspace", id: "workspace.test")

        XCTAssertThrowsError(try host.create(owner: owner, name: "Other", id: "workspace.other")) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .workspaceAlreadyExists(currentRevision: 1)
            )
        }
    }

    func testStructuralMutationsIncrementWorkspaceSequenceContiguously() throws {
        let (host, store, _) = try makeHost()
        _ = try createWorkspace(host)

        for expected in UInt64(0)..<3 {
            let updated = try host.mutate(expectedWorkspaceSeq: expected) {
                $0.metadata.name = "Name \(expected)"
            }
            XCTAssertEqual(updated.workspaceSeq, expected + 1)
            XCTAssertEqual(updated.recovery.hostEpoch, 1)
        }

        XCTAssertEqual(host.workspaceSeq, 3)
        XCTAssertEqual(try store.load()?.workspaceSeq, 3)
        XCTAssertEqual(try store.load()?.revision, 4)
    }

    func testStaleWorkspaceSequenceIsRejectedWithoutCommit() throws {
        let (host, store, _) = try makeHost()
        let initial = try createWorkspace(host)

        XCTAssertThrowsError(try host.mutate(expectedWorkspaceSeq: 1) { $0.metadata.name = "Stale" }) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .staleWorkspaceSequence(expected: 1, current: 0)
            )
        }

        XCTAssertEqual(try store.load(), initial)
        XCTAssertEqual(host.workspaceSeq, 0)
    }

    func testDegradedHostRejectsStructuralMutationsUntilResumed() throws {
        let (host, store, _) = try makeHost()
        let initial = try createWorkspace(host)

        host.enterDegradedMode(reason: "host offline")
        XCTAssertEqual(host.state, .degraded(reason: "host offline"))
        XCTAssertThrowsError(try host.mutate(expectedWorkspaceSeq: 0) { $0.metadata.name = "Degraded" }) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .hostUnavailable(reason: "host offline")
            )
        }
        XCTAssertEqual(try store.load(), initial)

        host.resumeHosting()
        let updated = try host.mutate(expectedWorkspaceSeq: 0) { $0.metadata.name = "Resumed" }
        XCTAssertEqual(updated.workspaceSeq, 1)
        XCTAssertEqual(host.state, .active)
    }

    func testHandedOffHostRejectsStructuralMutations() throws {
        let (host, _, _) = try makeHost()
        _ = try createWorkspace(host)

        host.markHandedOff()

        XCTAssertThrowsError(try host.mutate(expectedWorkspaceSeq: 0) { $0.metadata.name = "Handed off" }) { error in
            XCTAssertEqual(error as? WorkspaceHostError, .handedOff)
        }
    }

    func testMutationBodyFailureDoesNotAdvanceSequenceOrRevision() throws {
        let (host, store, _) = try makeHost()
        let initial = try createWorkspace(host)

        XCTAssertThrowsError(try host.mutate(expectedWorkspaceSeq: 0) { _ in
            throw TestFailure.expected
        }) { error in
            XCTAssertTrue(error is TestFailure)
        }

        XCTAssertEqual(try store.load(), initial)
        XCTAssertEqual(host.workspaceSeq, 0)
    }

    func testMutationCannotChangeWorkspaceIdentity() throws {
        let (host, store, _) = try makeHost()
        let initial = try createWorkspace(host)

        XCTAssertThrowsError(try host.mutate(expectedWorkspaceSeq: 0) { $0.id = "workspace.other" }) { error in
            XCTAssertEqual(error as? WorkspaceHostError, .workspaceIdentityChanged)
        }

        XCTAssertEqual(try store.load(), initial)
    }

    func testMutationCannotChangeHostEpoch() throws {
        let (host, store, _) = try makeHost()
        let initial = try createWorkspace(host)

        XCTAssertThrowsError(try host.mutate(expectedWorkspaceSeq: 0) { $0.recovery.hostEpoch += 1 }) { error in
            XCTAssertEqual(error as? WorkspaceHostError, .hostEpochChangeNotAllowed)
        }

        XCTAssertEqual(try store.load(), initial)
    }

    func testSequenceAndHostEpochSurviveHostReload() throws {
        let (host, store, _) = try makeHost()
        _ = try createWorkspace(host)
        _ = try host.mutate(expectedWorkspaceSeq: 0) { $0.metadata.name = "Persisted" }

        let reloaded = try WorkspaceHost(store: store, deviceId: "device.test")

        XCTAssertEqual(reloaded.workspaceSeq, 1)
        XCTAssertEqual(reloaded.hostEpoch, 1)
        let updated = try reloaded.mutate(expectedWorkspaceSeq: 1) { $0.metadata.name = "After reload" }
        XCTAssertEqual(updated.workspaceSeq, 2)
    }

    func testMutationUsesHostClockForUpdatedAt() throws {
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = Date(timeIntervalSince1970: 1_700_000_100)
        var now = first
        let (host, _, _) = try makeHost(now: { now })

        let created = try createWorkspace(host)
        XCTAssertEqual(created.metadata.updatedAt, first)

        now = second
        let updated = try host.mutate(expectedWorkspaceSeq: 0) { $0.metadata.name = "Renamed" }

        XCTAssertEqual(updated.metadata.updatedAt, second)
        XCTAssertEqual(updated.metadata.createdAt, first)
    }

    private func createWorkspace(_ host: WorkspaceHost) throws -> WorkspaceManifest {
        try host.create(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Test Workspace",
            id: "workspace.test"
        )
    }

    private func makeHost(
        now: @escaping () -> Date = Date.init
    ) throws -> (WorkspaceHost, NativeWorkspaceStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirDeskWorkspaceHostTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try NativeWorkspaceStore(directory: directory)
        let host = try WorkspaceHost(store: store, deviceId: "device.test", now: now)
        return (host, store, directory)
    }
}
