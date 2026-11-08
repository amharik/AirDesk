import CryptoKit
import XCTest
@testable import AirDesk

final class WorkspaceSyncEnvelopeTests: XCTestCase {
    private let keyBase64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    private let nonceBase64 = "oKGio6Slpqeoqaqr"
    private let ciphertextBase64 = "kXcORja7Y9wHRfeycxmo/gDNIHz91iaRhfQKkhsRADzIp6hneun+"

    func testMatchesBrowserEnvelopeVector() throws {
        let key = try WorkspaceSyncCrypto.importKey(try decode(keyBase64))
        let nonce = try decode(nonceBase64)
        let envelope = try WorkspaceSyncCrypto.encrypt(
            key: key,
            workspaceId: "ws-1",
            senderDeviceId: "dev-a",
            hostEpoch: 2,
            syncSeq: 7,
            plaintext: Data("workspace patch payload".utf8),
            aad: Data("patch-v1".utf8),
            nonce: nonce
        )

        XCTAssertEqual(envelope.version, WorkspaceSyncEnvelope.version)
        XCTAssertEqual(envelope.nonce, nonceBase64)
        XCTAssertEqual(envelope.aad, "cGF0Y2gtdjE=")
        XCTAssertEqual(envelope.ciphertext, ciphertextBase64)
        XCTAssertEqual(
            String(decoding: try WorkspaceSyncCrypto.canonicalAad(for: envelope), as: UTF8.self),
            "[1,\"ws-1\",\"dev-a\",2,7,\"cGF0Y2gtdjE=\"]"
        )

        let plaintext = try WorkspaceSyncCrypto.decrypt(
            key: key,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(
                workspaceId: "ws-1",
                hostEpoch: 2,
                senderDeviceId: "dev-a",
                lastSyncSeq: 6
            )
        )
        XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), "workspace patch payload")
    }

    func testRejectsWrongMetadataRevokedSenderAndReplay() throws {
        let key = try WorkspaceSyncCrypto.importKey(try decode(keyBase64))
        let envelope = try makeEnvelope(key: key)
        let valid = WorkspaceSyncExpectations(
            workspaceId: "ws-1",
            hostEpoch: 2,
            senderDeviceId: "dev-a"
        )

        XCTAssertThrowsError(try decrypt(
            key: key,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(workspaceId: "ws-2", hostEpoch: 2)
        )) { XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "WorkspaceMismatch") }

        XCTAssertThrowsError(try decrypt(
            key: key,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(workspaceId: "ws-1", hostEpoch: 3)
        )) { XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "EpochMismatch") }

        XCTAssertThrowsError(try decrypt(
            key: key,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(
                workspaceId: "ws-1",
                hostEpoch: 2,
                senderDeviceId: "dev-b"
            )
        )) { XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "DeviceMismatch") }

        XCTAssertThrowsError(try decrypt(
            key: key,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(
                workspaceId: valid.workspaceId,
                hostEpoch: valid.hostEpoch,
                revokedSenderDeviceIds: ["dev-a"]
            )
        )) { XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "SenderRevoked") }

        XCTAssertThrowsError(try decrypt(
            key: key,
            envelope: envelope,
            expected: WorkspaceSyncExpectations(
                workspaceId: valid.workspaceId,
                hostEpoch: valid.hostEpoch,
                lastSyncSeq: 7
            )
        )) { XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "StaleSequence") }
    }

    func testRejectsTamperedMetadataAndTruncatedCiphertext() throws {
        let key = try WorkspaceSyncCrypto.importKey(try decode(keyBase64))
        let envelope = try makeEnvelope(key: key)
        let expected = WorkspaceSyncExpectations(workspaceId: "ws-1", hostEpoch: 2)

        let tampered = WorkspaceSyncEnvelope(
            version: envelope.version,
            workspaceId: envelope.workspaceId,
            senderDeviceId: envelope.senderDeviceId,
            hostEpoch: envelope.hostEpoch,
            syncSeq: envelope.syncSeq + 1,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext,
            aad: envelope.aad
        )
        XCTAssertThrowsError(try decrypt(key: key, envelope: tampered, expected: expected)) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "AuthenticationFailed")
        }

        let ciphertext = try decode(envelope.ciphertext)
        let truncated = WorkspaceSyncEnvelope(
            version: envelope.version,
            workspaceId: envelope.workspaceId,
            senderDeviceId: envelope.senderDeviceId,
            hostEpoch: envelope.hostEpoch,
            syncSeq: envelope.syncSeq,
            nonce: envelope.nonce,
            ciphertext: ciphertext.prefix(8).base64EncodedString(),
            aad: envelope.aad
        )
        XCTAssertThrowsError(try decrypt(key: key, envelope: truncated, expected: expected)) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "TruncatedCiphertext")
        }
    }

    func testDerivesAutomaticPairingWorkspaceKey() throws {
        let secret = Data((0..<32).map(UInt8.init))
        let key = try WorkspaceSyncCrypto.derivePairingKey(secret: secret)
        let raw = key.withUnsafeBytes { Data($0) }
        XCTAssertEqual(raw.base64EncodedString(), "CKSAQxNdKw4f9gblaQ7lt+pFezUlD+qRVbRJuyaAFSQ=")

        let envelope = try makeEnvelope(key: key)
        let expected = WorkspaceSyncExpectations(workspaceId: "ws-1", hostEpoch: 2)
        XCTAssertNoThrow(try WorkspaceSyncCrypto.decrypt(key: key, envelope: envelope, expected: expected))
        XCTAssertThrowsError(try WorkspaceSyncCrypto.derivePairingKey(secret: Data(repeating: 0, count: 15))) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "InvalidSyncKey")
        }
    }

    func testImportsAndDerivesWorkspaceScopedKeys() throws {
        let secret = Data((0..<32).map(UInt8.init))
        let first = try WorkspaceSyncCrypto.deriveKey(secret: secret, workspaceId: "ws-1")
        let second = try WorkspaceSyncCrypto.deriveKey(secret: secret, workspaceId: "ws-2")
        let envelope = try makeEnvelope(key: first)
        let expected = WorkspaceSyncExpectations(workspaceId: "ws-1", hostEpoch: 2)

        XCTAssertNoThrow(try WorkspaceSyncCrypto.decrypt(key: first, envelope: envelope, expected: expected))
        XCTAssertThrowsError(try WorkspaceSyncCrypto.decrypt(key: second, envelope: envelope, expected: expected)) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "AuthenticationFailed")
        }

        XCTAssertThrowsError(try WorkspaceSyncCrypto.importKey(Data(repeating: 0, count: 16))) {
            XCTAssertEqual(($0 as? WorkspaceSyncEnvelopeError)?.code, "InvalidSyncKey")
        }
        XCTAssertThrowsError(try WorkspaceSyncCrypto.deriveKey(secret: Data(repeating: 0, count: 15), workspaceId: "ws-1"))
        XCTAssertThrowsError(try WorkspaceSyncCrypto.deriveKey(secret: secret, workspaceId: ""))
    }

    private func makeEnvelope(key: SymmetricKey) throws -> WorkspaceSyncEnvelope {
        try WorkspaceSyncCrypto.encrypt(
            key: key,
            workspaceId: "ws-1",
            senderDeviceId: "dev-a",
            hostEpoch: 2,
            syncSeq: 7,
            plaintext: Data("payload".utf8),
            nonce: try decode(nonceBase64)
        )
    }

    private func decrypt(
        key: SymmetricKey,
        envelope: WorkspaceSyncEnvelope,
        expected: WorkspaceSyncExpectations
    ) throws -> Data {
        try WorkspaceSyncCrypto.decrypt(key: key, envelope: envelope, expected: expected)
    }

    private func decode(_ value: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: value))
    }
}
