import XCTest
@testable import AirDesk

final class PairingOfferTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let nonce = Data((0..<32).map { UInt8($0) })
    private let bindingValue = String(repeating: "a", count: 64)

    private func makeOffer(
        identity: DeviceIdentity,
        now: Date? = nil,
        expiresIn: TimeInterval = PairingProtocol.defaultLifetime
    ) throws -> PairingOffer {
        try PairingOffer.make(
            identity: identity,
            expiresIn: expiresIn,
            endpointHint: "192.0.2.10:443",
            relayHint: "https://relay.example.com",
            requestedCapabilities: ["input"],
            channelBinding: PairingChannelBinding(
                kind: .certificateSHA256,
                value: bindingValue
            ),
            nonce: nonce,
            now: now ?? self.now
        )
    }

    private func makeValidator(
        offer: PairingOffer
    ) throws -> PairingOfferValidator {
        let local = try DeviceIdentity(algorithm: .ed25519)
        return PairingOfferValidator(localDeviceId: local.deviceId)
    }

    func testOfferJSONRoundTripAndValidation() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let offer = try makeOffer(identity: identity)
        let validator = try makeValidator(offer: offer)

        let data = try offer.jsonData()
        let decoded = try validator.decodeAndValidate(data, now: now)

        XCTAssertEqual(decoded, offer)
        XCTAssertEqual(decoded.deviceId, identity.deviceId)
        XCTAssertEqual(decoded.publicKeySPKI, identity.spki)
        XCTAssertEqual(decoded.requestedCapabilities, ["input"])
        XCTAssertEqual(decoded.channelBinding.kind, .certificateSHA256)
    }

    func testWrongProtocolIsRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        var offer = try makeOffer(identity: identity)
        offer.protocolName = "other-pairing"

        XCTAssertThrowsError(try makeValidator(offer: offer).validate(offer, now: now)) { error in
            XCTAssertEqual(
                error as? PairingOfferValidationError,
                .unsupportedProtocol("other-pairing")
            )
        }
    }

    func testWrongVersionIsRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        var offer = try makeOffer(identity: identity)
        offer.version = "2"

        XCTAssertThrowsError(try makeValidator(offer: offer).validate(offer, now: now)) { error in
            XCTAssertEqual(
                error as? PairingOfferValidationError,
                .unsupportedVersion("2")
            )
        }
    }

    func testExpiredOfferIsRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let offer = try makeOffer(identity: identity)
        let validator = try makeValidator(offer: offer)

        XCTAssertThrowsError(
            try validator.validate(offer, now: now.addingTimeInterval(121))
        ) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .offerExpired)
        }
    }

    func testOverlongOfferLifetimeIsRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        var offer = try makeOffer(identity: identity)
        offer.expiresAt = now.addingTimeInterval(PairingProtocol.maximumLifetime + 1)

        XCTAssertThrowsError(try makeValidator(offer: offer).validate(offer, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .invalidExpiry)
        }
        XCTAssertThrowsError(
            try makeOffer(identity: identity, expiresIn: PairingProtocol.maximumLifetime + 1)
        )
    }

    func testInvalidDeviceIdAndMismatchedSPKIAreRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let validator = try makeValidator(offer: try makeOffer(identity: identity))

        var invalidId = try makeOffer(identity: identity)
        invalidId.deviceId = "device.local"
        XCTAssertThrowsError(try validator.validate(invalidId, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .invalidDeviceId)
        }

        var mismatched = try makeOffer(identity: identity)
        mismatched.deviceId = "ad-device:" + String(repeating: "0", count: 64)
        XCTAssertThrowsError(try validator.validate(mismatched, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .publicKeyMismatch)
        }
    }

    func testInvalidNonceIsRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let validator = try makeValidator(offer: try makeOffer(identity: identity))

        var empty = try makeOffer(identity: identity)
        empty.nonce = ""
        XCTAssertThrowsError(try validator.validate(empty, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .invalidNonce)
        }

        var uppercase = try makeOffer(identity: identity)
        uppercase.nonce = PairingEncoding.hexString(Data(repeating: 0xab, count: 32)).uppercased()
        XCTAssertThrowsError(try validator.validate(uppercase, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .invalidNonce)
        }
    }

    func testUnboundChannelBindingIsRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let offer = try makeOffer(identity: identity)
        let validator = try makeValidator(offer: offer)
        let json = try offer.jsonString()
        let unbound = Data(
            json.replacingOccurrences(of: "certificate-sha256", with: "none").utf8
        )

        XCTAssertThrowsError(try validator.decodeAndValidate(unbound, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .malformedJSON)
        }

        var emptyBinding = try makeOffer(identity: identity)
        emptyBinding.channelBinding.value = ""
        XCTAssertThrowsError(try validator.validate(emptyBinding, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .invalidChannelBinding)
        }

        var uppercaseBinding = try makeOffer(identity: identity)
        uppercaseBinding.channelBinding.value = bindingValue.uppercased()
        XCTAssertThrowsError(try validator.validate(uppercaseBinding, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .invalidChannelBinding)
        }
    }

    func testSelfPairingIsRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let offer = try makeOffer(identity: identity)
        let validator = PairingOfferValidator(localDeviceId: identity.deviceId)

        XCTAssertThrowsError(try validator.validate(offer, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .selfPairing)
        }
    }

    func testReplayedOfferIsRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let offer = try makeOffer(identity: identity)
        let validator = try makeValidator(offer: offer)
        let data = try offer.jsonData()

        _ = try validator.decodeAndValidateAndClaim(data, now: now)
        XCTAssertThrowsError(
            try validator.decodeAndValidateAndClaim(data, now: now.addingTimeInterval(1))
        ) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .replayedOffer)
        }
    }

    func testInvalidRequestedCapabilitiesAreRejected() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let validator = try makeValidator(offer: try makeOffer(identity: identity))

        var empty = try makeOffer(identity: identity)
        empty.requestedCapabilities = [""]
        XCTAssertThrowsError(try validator.validate(empty, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .invalidCapabilities)
        }

        var duplicate = try makeOffer(identity: identity)
        duplicate.requestedCapabilities = ["input", "input"]
        XCTAssertThrowsError(try validator.validate(duplicate, now: now)) { error in
            XCTAssertEqual(error as? PairingOfferValidationError, .invalidCapabilities)
        }
    }

    func testPairingAloneGrantsNothing() throws {
        let localIdentity = try DeviceIdentity(algorithm: .ed25519)
        let remoteIdentity = try DeviceIdentity(algorithm: .ed25519)
        let registry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let service = PairingService(identity: localIdentity, registry: registry)
        let offer = try makeOffer(identity: remoteIdentity)
        var requested = offer
        requested.requestedCapabilities = ["input", "clipboard", "workspace-owner"]

        let acceptance = try service.accept(
            offerJSON: requested.jsonData(),
            displayLabel: "Remote controller",
            now: now
        )

        XCTAssertTrue(acceptance.grant.grantsNothing)
        XCTAssertTrue(acceptance.grant.capabilities.isEmpty)
        XCTAssertNil(acceptance.grant.workspaceMembershipId)
        XCTAssertNil(acceptance.grant.controllerRole)
        XCTAssertNil(acceptance.transcriptHash)
        XCTAssertEqual(acceptance.peer.trustState, .trusted)
        XCTAssertEqual(acceptance.peer.displayLabel, "Remote controller")
        XCTAssertEqual(registry.trustedCount, 1)
        XCTAssertTrue(registry.canEstablishSession(deviceId: remoteIdentity.deviceId))
    }

    func testTranscriptHashAndSASAreCanonicalAndFieldSensitive() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let offer = try makeOffer(identity: identity)
        let responderNonce = PairingEncoding.hexString(Data(repeating: 0xcd, count: 32))

        let first = PairingTranscript.make(
            offer: offer,
            responderDeviceId: "ad-device:" + String(repeating: "b", count: 64),
            responderNonce: responderNonce
        )
        let second = PairingTranscript.make(
            offer: offer,
            responderDeviceId: "ad-device:" + String(repeating: "b", count: 64),
            responderNonce: responderNonce
        )
        XCTAssertEqual(first.canonicalData, second.canonicalData)
        XCTAssertEqual(first.hash, second.hash)
        XCTAssertEqual(first.hash.count, 32)
        XCTAssertEqual(first.sas, second.sas)
        XCTAssertEqual(first.sas.count, 6)
        XCTAssertTrue(first.sas.allSatisfy { ("0"..."9").contains($0) })

        var changedBinding = first
        changedBinding.channelBindingValue = String(repeating: "f", count: 64)
        XCTAssertNotEqual(changedBinding.hash, first.hash)

        var changedCapabilities = first
        changedCapabilities.requestedCapabilities = ["input", "clipboard"]
        XCTAssertNotEqual(changedCapabilities.hash, first.hash)

        var changedHint = first
        changedHint.endpointHint = "198.51.100.20:443"
        XCTAssertNotEqual(changedHint.hash, first.hash)
    }
}
