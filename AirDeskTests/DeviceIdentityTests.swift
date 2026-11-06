import CryptoKit
import XCTest
@testable import AirDesk

final class DeviceIdentityTests: XCTestCase {
    private let fixedSeed = Data((0..<32).map { UInt8($0) })
    private let expectedPublicKeyRaw = Data([
        0x03, 0xa1, 0x07, 0xbf, 0xf3, 0xce, 0x10, 0xbe,
        0x1d, 0x70, 0xdd, 0x18, 0xe7, 0x4b, 0xc0, 0x99,
        0x67, 0xe4, 0xd6, 0x30, 0x9b, 0xa5, 0x0d, 0x5f,
        0x1d, 0xdc, 0x86, 0x64, 0x12, 0x55, 0x31, 0xb8
    ])

    func testEd25519SPKIIsExactCanonicalDER() throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: fixedSeed)
        XCTAssertEqual(key.publicKey.rawRepresentation, expectedPublicKeyRaw)
        let publicKey = try DevicePublicKey(
            algorithm: .ed25519,
            rawRepresentation: key.publicKey.rawRepresentation
        )
        let expected = Data([
            0x30, 0x2a,
            0x30, 0x05,
            0x06, 0x03, 0x2b, 0x65, 0x70,
            0x03, 0x21, 0x00
        ]) + expectedPublicKeyRaw

        XCTAssertEqual(publicKey.spki, expected)
        XCTAssertEqual(publicKey.spki.count, 44)
        XCTAssertEqual(publicKey.spkiHex, expected.map { String(format: "%02x", $0) }.joined())

        let decoded = try DevicePublicKey(spki: expected)
        XCTAssertEqual(decoded.algorithm, .ed25519)
        XCTAssertEqual(decoded.rawRepresentation, expectedPublicKeyRaw)
        XCTAssertEqual(decoded.spki, expected)
    }

    func testDeviceIdIsLowercaseSHA256OfSPKI() throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: fixedSeed)
        let publicKey = try DevicePublicKey(
            algorithm: .ed25519,
            rawRepresentation: key.publicKey.rawRepresentation
        )
        let expected = "ad-device:a050837d85070582ccf7394b0988847cc312cb88259b894899f6f239cf1791a5"

        XCTAssertEqual(publicKey.deviceId, expected)
        XCTAssertEqual(DeviceIdentity.deviceId(forSPKI: publicKey.spki), expected)
        XCTAssertEqual(publicKey.deviceId, publicKey.deviceId.lowercased())
        XCTAssertEqual(publicKey.deviceId.count, "ad-device:".count + 64)
    }

    func testP256SPKIRoundTripsUncompressedPoint() throws {
        let key = try P256.Signing.PrivateKey(
            rawRepresentation: Data((1...32).map { UInt8($0) })
        )
        let point = key.publicKey.x963Representation
        let publicKey = try DevicePublicKey(algorithm: .p256, rawRepresentation: point)
        let expectedPrefix = Data([
            0x30, 0x59,
            0x30, 0x13,
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00
        ])

        XCTAssertEqual(point.count, 65)
        XCTAssertEqual(point.first, 0x04)
        XCTAssertEqual(publicKey.spki.prefix(26), expectedPrefix)
        XCTAssertEqual(publicKey.spki.count, 91)
        XCTAssertEqual(publicKey.spki.suffix(65), point)

        let decoded = try DevicePublicKey(spki: publicKey.spki)
        XCTAssertEqual(decoded.algorithm, .p256)
        XCTAssertEqual(decoded.rawRepresentation, point)
        XCTAssertEqual(decoded.deviceId, publicKey.deviceId)
        XCTAssertEqual(publicKey.deviceId.count, "ad-device:".count + 64)
    }

    func testInvalidSPKIIsRejected() throws {
        XCTAssertThrowsError(try DevicePublicKey(spki: Data()))
        XCTAssertThrowsError(try DevicePublicKey(spki: Data([0x30, 0x00])))
        XCTAssertThrowsError(
            try DevicePublicKey(spki: DevicePublicKey.ed25519SPKIPrefix + Data(repeating: 0, count: 31))
        )
        XCTAssertThrowsError(
            try DevicePublicKey(spki: DevicePublicKey.p256SPKIPrefix + Data(repeating: 0, count: 64))
        )
        let compressedPoint = Data([0x02]) + Data(repeating: 0x01, count: 32)
        XCTAssertThrowsError(
            try DevicePublicKey(spki: DevicePublicKey.p256SPKIPrefix + compressedPoint)
        )
    }

    func testEd25519SignAndVerify() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let message = Data("pairing transcript".utf8)
        let signature = try identity.sign(message)

        XCTAssertEqual(signature.count, 64)
        XCTAssertTrue(identity.publicKey.verify(signature: signature, for: message))
        XCTAssertFalse(identity.publicKey.verify(signature: signature, for: Data("other".utf8)))
        XCTAssertFalse(
            identity.publicKey.verify(
                signature: Data(repeating: 0, count: signature.count),
                for: message
            )
        )
    }

    func testP256SignAndVerify() throws {
        let identity = try DeviceIdentity(algorithm: .p256)
        let message = Data("pairing transcript".utf8)
        let signature = try identity.sign(message)

        XCTAssertEqual(signature.count, 64)
        XCTAssertTrue(identity.publicKey.verify(signature: signature, for: message))
        XCTAssertFalse(identity.publicKey.verify(signature: signature, for: Data("other".utf8)))
    }

    func testStoreLoadOrCreateIsStableAcrossRelaunch() throws {
        let secretStore = InMemoryDeviceIdentitySecretStore()
        let store = DeviceIdentityStore(secretStore: secretStore, preferredAlgorithm: .ed25519)

        let first = try store.loadOrCreate()
        XCTAssertEqual(secretStore.saveCount, 1)

        let second = try store.loadOrCreate()
        XCTAssertEqual(secretStore.saveCount, 1)
        XCTAssertEqual(first.deviceId, second.deviceId)
        XCTAssertEqual(first.spki, second.spki)
        XCTAssertEqual(first.algorithm, .ed25519)
    }

    func testStoreKeepsStoredAlgorithmInsteadOfPreferredAlgorithm() throws {
        let secretStore = InMemoryDeviceIdentitySecretStore()
        let writer = DeviceIdentityStore(secretStore: secretStore, preferredAlgorithm: .p256)
        let original = try writer.loadOrCreate()

        let reader = DeviceIdentityStore(secretStore: secretStore, preferredAlgorithm: .ed25519)
        let loaded = try reader.loadOrCreate()

        XCTAssertEqual(original.algorithm, .p256)
        XCTAssertEqual(loaded.algorithm, .p256)
        XCTAssertEqual(loaded.deviceId, original.deviceId)
    }

    func testExplicitRotationChangesIdentity() throws {
        let secretStore = InMemoryDeviceIdentitySecretStore()
        let store = DeviceIdentityStore(secretStore: secretStore)
        let original = try store.loadOrCreate()
        let rotated = try store.rotateIdentity()

        XCTAssertNotEqual(rotated.deviceId, original.deviceId)
        XCTAssertEqual(secretStore.deleteCount, 1)
        XCTAssertEqual(secretStore.saveCount, 2)
        XCTAssertEqual(try store.loadOrCreate().deviceId, rotated.deviceId)
    }

    func testCorruptStoredIdentityIsNotSilentlyRotated() throws {
        let secretStore = InMemoryDeviceIdentitySecretStore()
        secretStore.data = Data("not a stored identity".utf8)
        let store = DeviceIdentityStore(secretStore: secretStore)

        XCTAssertThrowsError(try store.loadOrCreate()) { error in
            XCTAssertEqual(error as? DeviceIdentityError, .corruptedStoredIdentity)
        }
        XCTAssertEqual(secretStore.saveCount, 0)
        XCTAssertEqual(secretStore.deleteCount, 0)
    }

    func testUnsupportedStoredVersionIsNotSilentlyRotated() throws {
        let secretStore = InMemoryDeviceIdentitySecretStore()
        secretStore.data = Data(#"{"algorithm":"ed25519","privateKey":"AA==","version":99}"#.utf8)
        let store = DeviceIdentityStore(secretStore: secretStore)

        XCTAssertThrowsError(try store.loadOrCreate()) { error in
            XCTAssertEqual(error as? DeviceIdentityError, .unsupportedStoredVersion(99))
        }
        XCTAssertEqual(secretStore.saveCount, 0)
    }
}
