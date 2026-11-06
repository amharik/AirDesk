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

    func testDegradedHostKeepsRuntimeSelectionAndLeasedInputAvailable() throws {
        let (host, _, _) = try makeHost()
        _ = try createWorkspace(host)
        let registry = RuntimeRegistry()
        try registry.register(WanixRuntimeProvider())
        let application = WorkspaceApplication(
            id: "app.terminal",
            version: "1.0.0",
            name: "Terminal",
            entrypoint: "main",
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
            quotas: nil
        )
        let lease = InputLeaseManager()
        lease.beginSession(sessionId: "session.test", generation: 1)
        try lease.attach(
            controllerId: "controller.test",
            deviceId: "device.controller",
            role: .primaryDriver
        )
        let change = try lease.requestLease(controllerId: "controller.test")

        host.enterDegradedMode(reason: "host offline")

        XCTAssertEqual(try registry.select(application: application).providerId, "wanix")
        XCTAssertEqual(change.activeControllerId, "controller.test")
        let move = try lease.moveCursor(
            controllerId: "controller.test",
            to: InputPoint(x: 0.25, y: 0.5),
            epoch: change.leaseEpoch
        )
        XCTAssertEqual(move.shared, InputPoint(x: 0.25, y: 0.5))
        XCTAssertThrowsError(try host.mutate(expectedWorkspaceSeq: 0) { $0.metadata.name = "Blocked" }) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .hostUnavailable(reason: "host offline")
            )
        }
    }

    func testHandoffQuiesceStageActivateAndRetireTransfersAuthority() throws {
        let (source, store, _) = try makeHost()
        _ = try createWorkspace(source)
        _ = try source.mutate(expectedWorkspaceSeq: 0) { $0.metadata.name = "Before handoff" }

        let quiesced = try source.quiesceForHandoff(targetDeviceId: "device.next")
        XCTAssertEqual(quiesced.phase, .quiesced)
        XCTAssertEqual(quiesced.baseWorkspaceSeq, 1)
        XCTAssertEqual(quiesced.sourceHostEpoch, 1)
        XCTAssertEqual(source.state, .handoffPending(targetDeviceId: "device.next"))
        XCTAssertThrowsError(try source.mutate(expectedWorkspaceSeq: 1) { $0.metadata.name = "Blocked" }) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .hostUnavailable(reason: "handoff in progress")
            )
        }

        let staged = try source.stageHandoff(quiesced)
        XCTAssertEqual(staged.phase, .staged)

        let target = try WorkspaceHost(store: store, deviceId: "device.next")
        let activated = try target.activateHandoff(staged)

        XCTAssertEqual(activated.phase, .activated)
        XCTAssertEqual(activated.targetHostEpoch, 2)
        XCTAssertEqual(target.hostEpoch, 2)
        XCTAssertEqual(target.workspaceSeq, 2)
        XCTAssertEqual(try store.load()?.metadata.lastActiveDeviceId, "device.next")
        XCTAssertEqual(source.state, .handedOff)
        XCTAssertThrowsError(try source.mutate(expectedWorkspaceSeq: 2) { $0.metadata.name = "Stale host" }) { error in
            XCTAssertEqual(error as? WorkspaceHostError, .handedOff)
        }

        let retired = try source.retireAfterHandoff(activated)
        XCTAssertEqual(retired.phase, .retired)
        XCTAssertEqual(source.state, .handedOff)

        let next = try target.mutate(expectedWorkspaceSeq: 2) { $0.metadata.name = "After handoff" }
        XCTAssertEqual(next.workspaceSeq, 3)
        XCTAssertEqual(next.recovery.hostEpoch, 2)
    }

    func testHandoffRequiresStagingBeforeActivation() throws {
        let (source, store, _) = try makeHost()
        _ = try createWorkspace(source)
        let quiesced = try source.quiesceForHandoff(targetDeviceId: "device.next")

        let target = try WorkspaceHost(store: store, deviceId: "device.next")
        XCTAssertThrowsError(try target.activateHandoff(quiesced)) { error in
            XCTAssertEqual(error as? WorkspaceHostError, .handoffNotStaged)
        }
        XCTAssertEqual(target.hostEpoch, 1)
    }

    func testForceTakeoverDemotesPriorHostWithoutQuiesce() throws {
        let (source, store, _) = try makeHost()
        let manifest = try createWorkspace(source)
        let session = WorkspaceHandoffSession(
            workspaceId: manifest.id,
            sourceDeviceId: "device.test",
            targetDeviceId: "device.next",
            baseWorkspaceSeq: manifest.workspaceSeq,
            sourceHostEpoch: manifest.recovery.hostEpoch,
            checkpointSeq: manifest.recovery.checkpointSeq,
            journalSequence: manifest.recovery.journalSequence,
            targetHostEpoch: nil,
            phase: .quiesced
        )

        let target = try WorkspaceHost(store: store, deviceId: "device.next")
        let activated = try target.activateHandoff(session, force: true)

        XCTAssertEqual(activated.phase, .activated)
        XCTAssertEqual(target.hostEpoch, 2)
        XCTAssertEqual(source.state, .handedOff)
        XCTAssertThrowsError(try source.mutate(expectedWorkspaceSeq: 1) { $0.metadata.name = "Stale" }) { error in
            XCTAssertEqual(error as? WorkspaceHostError, .handedOff)
        }
        XCTAssertEqual(try source.retireAfterHandoff(activated).phase, .retired)
    }

    func testStaleHandoffSnapshotIsRejected() throws {
        let (source, store, _) = try makeHost()
        _ = try createWorkspace(source)
        let quiesced = try source.quiesceForHandoff(targetDeviceId: "device.next")

        let staleWriter = try WorkspaceHost(store: store, deviceId: "device.stale")
        _ = try staleWriter.mutate(expectedWorkspaceSeq: 0) { $0.metadata.name = "Concurrent" }

        XCTAssertThrowsError(try source.stageHandoff(quiesced)) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .staleHandoff(workspaceSeq: 1, hostEpoch: 1)
            )
        }
    }

    func testHandoffRejectsUnknownSourceAndTarget() throws {
        let (source, store, _) = try makeHost()
        _ = try createWorkspace(source)
        let quiesced = try source.quiesceForHandoff(targetDeviceId: "device.next")
        let staged = try source.stageHandoff(quiesced)

        let wrongTarget = try WorkspaceHost(store: store, deviceId: "device.other")
        XCTAssertThrowsError(try wrongTarget.activateHandoff(staged)) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .handoffTargetMismatch(expected: "device.next", actual: "device.other")
            )
        }

        let wrongSource = try WorkspaceHost(store: store, deviceId: "device.other")
        XCTAssertThrowsError(try wrongSource.stageHandoff(staged)) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .handoffSourceMismatch(expected: "device.test", actual: "device.other")
            )
        }
    }

    func testRetireBeforeActivationIsRejected() throws {
        let (source, store, _) = try makeHost()
        _ = try createWorkspace(source)
        let quiesced = try source.quiesceForHandoff(targetDeviceId: "device.next")
        let staged = try source.stageHandoff(quiesced)

        XCTAssertThrowsError(try source.retireAfterHandoff(staged)) { error in
            XCTAssertEqual(
                error as? WorkspaceHostError,
                .handoffNotActivated(currentHostEpoch: 1)
            )
        }
        XCTAssertEqual(try store.load()?.recovery.hostEpoch, 1)
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
