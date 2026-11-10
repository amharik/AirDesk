import CryptoKit
import XCTest
@testable import AirDesk

final class WorkspaceSyncKeyRotationTests: XCTestCase {
    private let currentKeyHex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    private let newKeyHex = "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f"
    private let nonceBase64 = "AAECAwQFBgcICQoL"
    private let ciphertextBase64 = "B0OUWIGghFzFCN3A/aQ2ItOH1WekLgkrYD6/3kE0Xu0QoJ8m0QjWW7e+DQoNB7ak"
    private let grantCiphertextBase64 = "B0OUWIGghFzFCN3A/aQ2ItOH1WekLgkrYD6/3kE0Xu0NHWvtaDL2FsEmQ26gXNE5"

    func testMatchesBrowserRotationVector() throws {
        let currentKey = try WorkspaceSyncCrypto.importKey(try hex(currentKeyHex))
        let newKey = try WorkspaceSyncCrypto.importKey(try hex(newKeyHex))
        let rotated = try WorkspaceSyncKeyRotationCrypto.rotate(
            currentKey: currentKey,
            workspaceId: "ws-1",
            issuerDeviceId: "ad-device:issuer",
            nextGeneration: 2,
            newKey: newKey,
            nonce: try decode(nonceBase64)
        )

        XCTAssertEqual(rotated.message.version, 1)
        XCTAssertEqual(rotated.message.kind, "workspace-key-rotation")
        XCTAssertEqual(rotated.message.nonce, nonceBase64)
        XCTAssertEqual(rotated.message.ciphertext, ciphertextBase64)
        XCTAssertEqual(
            String(
                decoding: try WorkspaceSyncKeyRotationCrypto.canonicalAad(
                    for: rotated.message
                ),
                as: UTF8.self
            ),
            "[1,\"workspace-key-rotation\",\"ws-1\",\"ad-device:issuer\",2]"
        )

        let accepted = try WorkspaceSyncKeyRotationCrypto.accept(
            rotated.message,
            currentKey: currentKey,
            workspaceId: "ws-1",
            currentGeneration: 1,
            expectedIssuerDeviceId: "ad-device:issuer"
        )
        XCTAssertEqual(hexString(accepted.key), newKeyHex)
        XCTAssertEqual(accepted.generation, 2)
    }

    func testRejectsReplayedSkippedWrongIssuerAndTamperedRotations() throws {
        let currentKey = try WorkspaceSyncCrypto.importKey(try hex(currentKeyHex))
        let rotated = try rotation(currentKey: currentKey)

        XCTAssertThrowsError(try WorkspaceSyncKeyRotationCrypto.accept(
            rotated.message,
            currentKey: currentKey,
            workspaceId: "ws-1",
            currentGeneration: 2
        )) { XCTAssertEqual($0 as? WorkspaceSyncKeyRotationError, .generationReplay) }

        XCTAssertThrowsError(try WorkspaceSyncKeyRotationCrypto.accept(
            rotated.message,
            currentKey: currentKey,
            workspaceId: "ws-1",
            currentGeneration: 0
        )) { XCTAssertEqual($0 as? WorkspaceSyncKeyRotationError, .generationGap) }

        XCTAssertThrowsError(try WorkspaceSyncKeyRotationCrypto.accept(
            rotated.message,
            currentKey: currentKey,
            workspaceId: "ws-1",
            currentGeneration: 1,
            expectedIssuerDeviceId: "ad-device:other"
        )) { XCTAssertEqual($0 as? WorkspaceSyncKeyRotationError, .invalidIssuer) }

        XCTAssertThrowsError(try WorkspaceSyncKeyRotationCrypto.accept(
            rotated.message,
            currentKey: currentKey,
            workspaceId: "ws-2",
            currentGeneration: 1
        )) { XCTAssertEqual($0 as? WorkspaceSyncKeyRotationError, .workspaceMismatch) }

        let tampered = WorkspaceSyncKeyRotation(
            version: rotated.message.version,
            kind: rotated.message.kind,
            workspaceId: rotated.message.workspaceId,
            issuerDeviceId: rotated.message.issuerDeviceId,
            generation: rotated.message.generation,
            nonce: rotated.message.nonce,
            ciphertext: tamperedBase64(rotated.message.ciphertext)
        )
        XCTAssertThrowsError(try WorkspaceSyncKeyRotationCrypto.accept(
            tampered,
            currentKey: currentKey,
            workspaceId: "ws-1",
            currentGeneration: 1
        )) { XCTAssertEqual($0 as? WorkspaceSyncKeyRotationError, .authenticationFailed) }
    }

    func testMatchesBrowserKeyGrantVector() throws {
        let bootstrapKey = try WorkspaceSyncCrypto.importKey(try hex(currentKeyHex))
        let workspaceKey = try WorkspaceSyncCrypto.importKey(try hex(newKeyHex))
        let message = try WorkspaceSyncKeyGrantCrypto.grant(
            currentKey: workspaceKey,
            bootstrapKey: bootstrapKey,
            workspaceId: "ws-1",
            issuerDeviceId: "ad-device:issuer",
            generation: 2,
            nonce: try decode(nonceBase64)
        )

        XCTAssertEqual(message.kind, "workspace-key-grant")
        XCTAssertEqual(message.nonce, nonceBase64)
        XCTAssertEqual(message.ciphertext, grantCiphertextBase64)
        XCTAssertEqual(
            String(
                decoding: try WorkspaceSyncKeyGrantCrypto.canonicalAad(for: message),
                as: UTF8.self
            ),
            "[1,\"workspace-key-grant\",\"ws-1\",\"ad-device:issuer\",2]"
        )

        let accepted = try WorkspaceSyncKeyGrantCrypto.accept(
            message,
            bootstrapKey: bootstrapKey,
            workspaceId: "ws-1",
            expectedIssuerDeviceId: "ad-device:issuer"
        )
        XCTAssertEqual(hexString(accepted.key), newKeyHex)
        XCTAssertEqual(accepted.generation, 2)

        XCTAssertThrowsError(try WorkspaceSyncKeyGrantCrypto.accept(
            message,
            bootstrapKey: try WorkspaceSyncCrypto.importKey(
                try hex("101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f")
            ),
            workspaceId: "ws-1"
        )) { XCTAssertEqual($0 as? WorkspaceSyncKeyGrantError, .authenticationFailed) }

        XCTAssertThrowsError(try WorkspaceSyncKeyGrantCrypto.accept(
            message,
            bootstrapKey: bootstrapKey,
            workspaceId: "ws-1",
            expectedIssuerDeviceId: "ad-device:other"
        )) { XCTAssertEqual($0 as? WorkspaceSyncKeyGrantError, .invalidIssuer) }
    }

    func testRevokedPeerCannotDecryptAfterRotation() throws {
        let oldKey = try WorkspaceSyncCrypto.importKey(try hex(currentKeyHex))
        let rotated = try rotation(currentKey: oldKey)
        let envelope = try WorkspaceSyncCrypto.encrypt(
            key: rotated.key,
            workspaceId: "ws-1",
            senderDeviceId: "host",
            hostEpoch: 1,
            syncSeq: 1,
            plaintext: Data("after rotation".utf8)
        )

        XCTAssertThrowsError(try WorkspaceSyncCrypto.decrypt(
            key: oldKey,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(workspaceId: "ws-1", hostEpoch: 1)
        )) { XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "AuthenticationFailed") }

        let plaintext = try WorkspaceSyncCrypto.decrypt(
            key: rotated.key,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(workspaceId: "ws-1", hostEpoch: 1)
        )
        XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), "after rotation")
    }

    @MainActor
    func testRuntimeQueuesAndAcceptsRotation() throws {
        let key = try WorkspaceSyncCrypto.importKey(try hex(currentKeyHex))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("airdesk-sync-rotation-\(UUID().uuidString)", isDirectory: true)
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
            fabric: IrohFabricPeer(identitySeed: Data(repeating: 0x61, count: 32)),
            stateURL: store.syncStateURL
        )

        let rotation = try runtime.rotateKey(for: ["endpoint-b"], newKey: try WorkspaceSyncCrypto.importKey(try hex(newKeyHex)))
        XCTAssertEqual(runtime.keyGeneration, 2)
        XCTAssertNotNil(runtime.pendingRotation(for: "endpoint-b"))
        XCTAssertEqual(runtime.pendingRotation(for: "endpoint-a"), nil)

        let controllerDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("airdesk-sync-rotation-\(UUID().uuidString)", isDirectory: true)
        let controllerStore = try NativeWorkspaceStore(directory: controllerDirectory)
        let controllerHost = try WorkspaceHost(store: controllerStore, deviceId: "device-b")
        _ = try controllerHost.create(
            owner: WorkspaceOwner(identityId: "owner", displayName: "Owner"),
            name: "Desk",
            id: "ws-1"
        )
        let controller = try WorkspaceSyncRuntime(
            key: key,
            workspaceId: "ws-1",
            senderDeviceId: "device-b",
            hostEpoch: 1,
            host: controllerHost,
            fabric: IrohFabricPeer(identitySeed: Data(repeating: 0x62, count: 32)),
            stateURL: controllerStore.syncStateURL
        )

        XCTAssertTrue(try controller.acceptRotation(
            rotation,
            expectedIssuerDeviceId: "device-a"
        ))
        XCTAssertEqual(controller.keyGeneration, 2)
        XCTAssertFalse(try controller.acceptRotation(
            rotation,
            expectedIssuerDeviceId: "device-a"
        ))
        XCTAssertEqual(
            hexString(controller.controller.session.currentKey),
            newKeyHex
        )
    }

    @MainActor
    func testRuntimeAcceptsBootstrapKeyGrant() throws {
        let bootstrapKey = try WorkspaceSyncCrypto.importKey(try hex(currentKeyHex))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("airdesk-sync-grant-\(UUID().uuidString)", isDirectory: true)
        let store = try NativeWorkspaceStore(directory: directory)
        let host = try WorkspaceHost(store: store, deviceId: "device-b")
        _ = try host.create(
            owner: WorkspaceOwner(identityId: "owner", displayName: "Owner"),
            name: "Desk",
            id: "ws-1"
        )
        let runtime = try WorkspaceSyncRuntime(
            key: bootstrapKey,
            workspaceId: "ws-1",
            senderDeviceId: "device-b",
            hostEpoch: 1,
            host: host,
            fabric: IrohFabricPeer(identitySeed: Data(repeating: 0x63, count: 32)),
            stateURL: store.syncStateURL
        )
        let grant = try WorkspaceSyncKeyGrantCrypto.grant(
            currentKey: try WorkspaceSyncCrypto.importKey(try hex(newKeyHex)),
            bootstrapKey: bootstrapKey,
            workspaceId: "ws-1",
            issuerDeviceId: "device-a",
            generation: 2,
            nonce: try decode(nonceBase64)
        )

        XCTAssertTrue(try runtime.acceptKeyGrant(
            grant,
            bootstrapKey: bootstrapKey,
            expectedIssuerDeviceId: "device-a"
        ))
        XCTAssertEqual(runtime.keyGeneration, 2)
        XCTAssertEqual(hexString(runtime.currentKey), newKeyHex)
        XCTAssertTrue(try runtime.acceptKeyGrant(
            grant,
            bootstrapKey: bootstrapKey,
            expectedIssuerDeviceId: "device-a"
        ))
    }

    private func rotation(currentKey: SymmetricKey) throws -> (key: SymmetricKey, message: WorkspaceSyncKeyRotation) {
        try WorkspaceSyncKeyRotationCrypto.rotate(
            currentKey: currentKey,
            workspaceId: "ws-1",
            issuerDeviceId: "ad-device:issuer",
            nextGeneration: 2,
            newKey: try WorkspaceSyncCrypto.importKey(try hex(newKeyHex)),
            nonce: try decode(nonceBase64)
        )
    }

    private func hex(_ value: String) throws -> Data {
        try XCTUnwrap(PairingEncoding.data(hex: value))
    }

    private func decode(_ value: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: value))
    }

    private func hexString(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { data in
            data.map { String(format: "%02x", $0) }.joined()
        }
    }

    private func tamperedBase64(_ value: String) -> String {
        guard let last = value.last else { return value }
        return String(value.dropLast()) + (last == "A" ? "B" : "A")
    }
}
