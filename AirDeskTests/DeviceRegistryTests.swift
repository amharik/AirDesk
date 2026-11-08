import XCTest
@testable import AirDesk

final class DeviceRegistryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePeer(label: String = "Test peer") throws -> (DeviceIdentity, PairedPeerRecord) {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let record = PairedPeerRecord(
            deviceId: identity.deviceId,
            displayLabel: label,
            publicKeySPKI: identity.spki,
            pairedAt: now
        )
        return (identity, record)
    }

    func testRegistryPersistsPairedPeerAcrossReload() throws {
        let storage = InMemoryDeviceRegistryStorage()
        let registry = try DeviceRegistry(storage: storage)
        let (_, record) = try makePeer()

        try registry.upsert(record)
        XCTAssertEqual(registry.pairedCount, 1)
        XCTAssertEqual(registry.trustedCount, 1)
        XCTAssertEqual(registry.revokedCount, 0)
        XCTAssertEqual(registry.peer(deviceId: record.deviceId)?.displayLabel, "Test peer")

        let reloaded = try DeviceRegistry(storage: storage)
        XCTAssertEqual(reloaded.peer(deviceId: record.deviceId), record)
        XCTAssertTrue(reloaded.isTrusted(deviceId: record.deviceId))
    }

    func testPendingPeerBecomesTrustedOnlyAfterExplicitTrust() throws {
        let storage = InMemoryDeviceRegistryStorage()
        let registry = try DeviceRegistry(storage: storage)
        var (_, record) = try makePeer()
        record.trustState = .pending
        try registry.upsert(record)

        XCTAssertEqual(registry.pendingCount, 1)
        XCTAssertEqual(registry.trustedCount, 0)
        XCTAssertFalse(registry.isTrusted(deviceId: record.deviceId))
        XCTAssertFalse(registry.canEstablishSession(deviceId: record.deviceId))

        let trusted = try registry.trust(deviceId: record.deviceId, at: now)
        XCTAssertEqual(trusted.trustState, .trusted)
        XCTAssertEqual(trusted.pairedAt, now)
        XCTAssertTrue(registry.isTrusted(deviceId: record.deviceId))
        XCTAssertEqual(registry.trustedCount, 1)
        XCTAssertEqual(registry.pendingCount, 0)

        let reloaded = try DeviceRegistry(storage: storage)
        XCTAssertTrue(reloaded.isTrusted(deviceId: record.deviceId))
    }

    func testPendingUpsertDoesNotDowngradeTrustedPeer() throws {
        let registry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        var (_, record) = try makePeer()
        try registry.upsert(record)

        record.trustState = .pending
        record.pairedAt = now.addingTimeInterval(60)
        try registry.upsert(record)

        XCTAssertTrue(registry.isTrusted(deviceId: record.deviceId))
        XCTAssertEqual(registry.peer(deviceId: record.deviceId)?.pairedAt, now)
    }

    func testPendingUpsertCannotReviveRevokedPeer() throws {
        let registry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        var (_, record) = try makePeer()
        try registry.upsert(record)
        try registry.revoke(deviceId: record.deviceId, at: now, reason: "Lost device")

        record.trustState = .pending
        XCTAssertThrowsError(try registry.upsert(record))
        XCTAssertEqual(registry.peer(deviceId: record.deviceId)?.trustState, .revoked)
    }

    func testOnlyUntrustedPeerRecordsCanBeRemoved() throws {
        let storage = InMemoryDeviceRegistryStorage()
        let registry = try DeviceRegistry(storage: storage)
        var (_, record) = try makePeer(label: "Pending peer")
        record.trustState = .pending
        try registry.upsert(record)

        try registry.remove(deviceId: record.deviceId)
        XCTAssertNil(registry.peer(deviceId: record.deviceId))

        let (_, trusted) = try makePeer(label: "Trusted peer")
        try registry.upsert(trusted)
        XCTAssertThrowsError(try registry.remove(deviceId: trusted.deviceId))
        XCTAssertTrue(registry.isTrusted(deviceId: trusted.deviceId))

        try registry.revoke(deviceId: trusted.deviceId, at: now, reason: "Lost device")
        try registry.remove(deviceId: trusted.deviceId)
        XCTAssertNil(registry.peer(deviceId: trusted.deviceId))

        let reloaded = try DeviceRegistry(storage: storage)
        XCTAssertEqual(reloaded.pairedCount, 0)
    }

    func testRevocationInvalidatesTrustAndSessionCredential() throws {
        let storage = InMemoryDeviceRegistryStorage()
        let registry = try DeviceRegistry(storage: storage)
        let (_, record) = try makePeer()
        try registry.upsert(record)

        let credential = DeviceSessionCredential(
            deviceId: record.deviceId,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(3_600)
        )
        XCTAssertTrue(registry.canEstablishSession(deviceId: record.deviceId))
        XCTAssertTrue(registry.validate(credential, now: now.addingTimeInterval(10)))

        let revoked = try registry.revoke(
            deviceId: record.deviceId,
            at: now.addingTimeInterval(20),
            reason: "Lost device"
        )

        XCTAssertEqual(revoked.trustState, .revoked)
        XCTAssertEqual(revoked.revokedAt, now.addingTimeInterval(20))
        XCTAssertEqual(revoked.revocationReason, "Lost device")
        XCTAssertFalse(registry.isTrusted(deviceId: record.deviceId))
        XCTAssertFalse(registry.canEstablishSession(deviceId: record.deviceId))
        XCTAssertFalse(registry.validate(credential, now: now.addingTimeInterval(30)))
        XCTAssertEqual(registry.trustedCount, 0)
        XCTAssertEqual(registry.revokedCount, 1)

        let reloaded = try DeviceRegistry(storage: storage)
        XCTAssertFalse(reloaded.canEstablishSession(deviceId: record.deviceId))
        XCTAssertEqual(reloaded.revokedCount, 1)
    }

    func testRevokedPeerCannotBeSilentlyRetrustedByUpsert() throws {
        let storage = InMemoryDeviceRegistryStorage()
        let registry = try DeviceRegistry(storage: storage)
        let (_, record) = try makePeer()
        try registry.upsert(record)
        try registry.revoke(deviceId: record.deviceId, at: now, reason: "Lost device")

        XCTAssertThrowsError(try registry.upsert(record))
        XCTAssertFalse(registry.isTrusted(deviceId: record.deviceId))
        XCTAssertEqual(registry.revokedCount, 1)
    }

    func testRevocationOfUnknownPeerFails() throws {
        let registry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        XCTAssertThrowsError(try registry.revoke(deviceId: "ad-device:missing")) { error in
            XCTAssertEqual(
                error as? DeviceRegistryError,
                .peerNotFound("ad-device:missing")
            )
        }
    }

    func testRegistryRejectsRecordWithMismatchedDeviceId() throws {
        let registry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let (identity, _) = try makePeer()
        let mismatched = PairedPeerRecord(
            deviceId: "ad-device:" + String(repeating: "0", count: 64),
            displayLabel: "Spoofed",
            publicKeySPKI: identity.spki,
            pairedAt: now
        )

        XCTAssertThrowsError(try registry.upsert(mismatched))
        XCTAssertEqual(registry.pairedCount, 0)
    }

    func testRegistryRejectsEmptyDisplayLabel() throws {
        let registry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let (identity, _) = try makePeer()
        let emptyLabel = PairedPeerRecord(
            deviceId: identity.deviceId,
            displayLabel: "   ",
            publicKeySPKI: identity.spki,
            pairedAt: now
        )

        XCTAssertThrowsError(try registry.upsert(emptyLabel))
        XCTAssertEqual(registry.pairedCount, 0)
    }

    func testCredentialValidationRequiresTrustedPeerAndValidWindow() throws {
        let registry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let (_, record) = try makePeer()
        try registry.upsert(record)

        let expired = DeviceSessionCredential(
            deviceId: record.deviceId,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        XCTAssertFalse(registry.validate(expired, now: now.addingTimeInterval(60)))
        XCTAssertFalse(
            registry.validate(
                DeviceSessionCredential(
                    deviceId: "ad-device:" + String(repeating: "a", count: 64),
                    issuedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                ),
                now: now
            )
        )
    }
}
