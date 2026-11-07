import CryptoKit
import XCTest
@testable import AirDesk

@MainActor
final class WorkspaceSyncControllerTests: XCTestCase {
    func testControllerSendsSnapshotAndAppliesRemoteManifest() throws {
        let key = try WorkspaceSyncCrypto.deriveKey(
            secret: Data(repeating: 0x31, count: 32),
            workspaceId: "ws-1"
        )
        let hostA = try makeHost(deviceId: "device-a")
        let hostB = try makeHost(deviceId: "device-b")
        _ = try hostA.create(
            owner: WorkspaceOwner(identityId: "owner", displayName: "Owner"),
            name: "Shared",
            id: "ws-1"
        )
        _ = try hostB.create(
            owner: WorkspaceOwner(identityId: "owner", displayName: "Owner"),
            name: "Shared",
            id: "ws-1"
        )
        _ = try hostB.mutate(expectedWorkspaceSeq: 0) { manifest in
            manifest.metadata.name = "Remote"
        }

        let controllerA = WorkspaceSyncController(
            session: WorkspaceSyncSession(
                key: key,
                workspaceId: "ws-1",
                senderDeviceId: "device-a",
                hostEpoch: 1
            ),
            host: hostA
        )
        let controllerB = WorkspaceSyncController(
            session: WorkspaceSyncSession(
                key: key,
                workspaceId: "ws-1",
                senderDeviceId: "device-b",
                hostEpoch: 1
            ),
            host: hostB
        )

        let envelope = try controllerB.enqueueCurrentSnapshot()
        XCTAssertEqual(controllerB.pendingCount, 1)
        var sent: [Data] = []
        XCTAssertEqual(try controllerB.flush { data in
            sent.append(data)
            return true
        }, 1)
        XCTAssertEqual(controllerB.pendingCount, 0)

        let encoded = try JSONEncoder().encode(envelope)
        let applied = try controllerA.receive(encoded)
        XCTAssertEqual(applied.status, .applied)
        XCTAssertEqual(try XCTUnwrap(hostA.load()).metadata.name, "Remote")
        XCTAssertEqual(try XCTUnwrap(hostA.load()).workspaceSeq, 1)
        XCTAssertEqual(controllerA.session.state.lastReceivedSeqBySender["device-b"], 1)

        XCTAssertThrowsError(try controllerA.receive(encoded)) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "StaleSequence")
        }
    }

    func testControllerRequiresAnExistingWorkspace() throws {
        let key = try WorkspaceSyncCrypto.deriveKey(
            secret: Data(repeating: 0x32, count: 32),
            workspaceId: "ws-1"
        )
        let host = try makeHost(deviceId: "device-a")
        let controller = WorkspaceSyncController(
            session: WorkspaceSyncSession(
                key: key,
                workspaceId: "ws-1",
                senderDeviceId: "device-a",
                hostEpoch: 1
            ),
            host: host
        )
        XCTAssertThrowsError(try controller.enqueueCurrentSnapshot()) {
            XCTAssertEqual($0 as? WorkspaceSyncControllerError, .workspaceMissing)
        }
    }

    private func makeHost(deviceId: String) throws -> WorkspaceHost {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("airdesk-sync-controller-\(UUID().uuidString)", isDirectory: true)
        let store = try NativeWorkspaceStore(directory: directory)
        return try WorkspaceHost(store: store, deviceId: deviceId)
    }
}
