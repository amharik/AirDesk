import CryptoKit
import XCTest
@testable import AirDesk

@MainActor
final class WorkspaceSyncRuntimeTests: XCTestCase {
    func testPublishesPersistsAndReloadsPendingOutbox() throws {
        let key = try WorkspaceSyncCrypto.deriveKey(
            secret: Data(repeating: 0x51, count: 32),
            workspaceId: "ws-1"
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("airdesk-sync-runtime-\(UUID().uuidString)", isDirectory: true)
        let store = try NativeWorkspaceStore(directory: directory)
        let host = try WorkspaceHost(store: store, deviceId: "device-a")
        _ = try host.create(
            owner: WorkspaceOwner(identityId: "owner", displayName: "Owner"),
            name: "Desk",
            id: "ws-1"
        )
        let fabric = IrohFabricPeer(identitySeed: Data(repeating: 0x52, count: 32))
        let runtime = try WorkspaceSyncRuntime(
            key: key,
            workspaceId: "ws-1",
            senderDeviceId: "device-a",
            hostEpoch: 1,
            host: host,
            fabric: fabric,
            stateURL: store.syncStateURL
        )

        let envelope = try runtime.publishLocalSnapshot()
        XCTAssertEqual(envelope.syncSeq, 1)
        XCTAssertEqual(runtime.pendingCount, 1)
        XCTAssertEqual(try runtime.flushPending(), 0)
        XCTAssertEqual(runtime.pendingCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.syncStateURL.path))

        let reloaded = try WorkspaceSyncRuntime(
            key: key,
            workspaceId: "ws-1",
            senderDeviceId: "device-a",
            hostEpoch: 1,
            host: host,
            fabric: fabric,
            stateURL: store.syncStateURL
        )
        XCTAssertEqual(reloaded.pendingCount, 1)
        XCTAssertEqual(reloaded.controller.session.state.nextOutboundSeq, 2)
    }

    func testInvalidEnvelopeIsRecordedWithoutThrowingFromCallback() throws {
        let key = try WorkspaceSyncCrypto.deriveKey(
            secret: Data(repeating: 0x53, count: 32),
            workspaceId: "ws-1"
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("airdesk-sync-runtime-\(UUID().uuidString)", isDirectory: true)
        let store = try NativeWorkspaceStore(directory: directory)
        let host = try WorkspaceHost(store: store, deviceId: "device-a")
        _ = try host.create(
            owner: WorkspaceOwner(identityId: "owner", displayName: "Owner"),
            name: "Desk",
            id: "ws-1"
        )
        let runtime = try WorkspaceSyncRuntime(
            key: key,
            workspaceId: "ws-1",
            senderDeviceId: "device-a",
            hostEpoch: 1,
            host: host,
            fabric: IrohFabricPeer(identitySeed: Data(repeating: 0x54, count: 32)),
            stateURL: store.syncStateURL
        )

        runtime.handleEnvelope(Data("not-an-envelope".utf8))
        XCTAssertNotNil(runtime.lastError)
    }
}
