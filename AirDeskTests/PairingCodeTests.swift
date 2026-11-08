import XCTest
@testable import AirDesk

final class PairingCodeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let certificateHash = String(repeating: "ab", count: 32)

    func testPinChallengeRoundTripsWithoutSerializingThePin() throws {
        let offer = try makeOffer()
        let challenge = try AdPairCodec.createPinChallenge(
            offer: offer,
            now: now,
            randomBytes: { Data(repeating: 0, count: $0) }
        )
        let parsed = try AdPairCodec.parse(
            challenge.serialized,
            options: AdPairCodeParseOptions(now: now)
        )

        XCTAssertEqual(challenge.pin, "000000")
        XCTAssertEqual(parsed.mode, .pin)
        XCTAssertNil(parsed.secret)
        XCTAssertEqual(parsed.offer, offer)
        XCTAssertEqual(parsed.salt, challenge.code.salt)
        let encoded = try XCTUnwrap(
            PairingEncoding.data(base64URL: String(challenge.serialized.dropFirst(AdPairCode.prefix.count)))
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["pin"])
        XCTAssertNil(object["secret"])
    }

    func testQrSecretChallengeRoundTrips() throws {
        let offer = try makeOffer()
        let challenge = try AdPairCodec.createQrSecretChallenge(
            offer: offer,
            now: now,
            randomBytes: { Data(repeating: 7, count: $0) }
        )
        let parsed = try AdPairCodec.parse(
            challenge.serialized,
            options: AdPairCodeParseOptions(now: now)
        )

        XCTAssertEqual(challenge.secret, Data(repeating: 7, count: 32))
        XCTAssertEqual(parsed.mode, .qrSecret)
        XCTAssertEqual(parsed.secret, challenge.code.secret)
        XCTAssertEqual(challenge.mode, .qrSecret)
    }

    func testRejectsMalformedUnknownUnsupportedExpiredAndModeMismatchCodes() throws {
        let challenge = try AdPairCodec.createPinChallenge(
            offer: try makeOffer(),
            now: now,
            randomBytes: { Data(repeating: 1, count: $0) }
        )
        let parsed = try AdPairCodec.parse(
            challenge.serialized,
            options: AdPairCodeParseOptions(now: now)
        )

        XCTAssertThrowsError(try AdPairCodec.parse("not-a-code")) {
            XCTAssertEqual(($0 as? AdPairCodeError)?.code, "invalid-code")
        }
        XCTAssertThrowsError(try AdPairCodec.parse("ADPAIR1:!")) {
            XCTAssertEqual(($0 as? AdPairCodeError)?.code, "malformed-code")
        }
        XCTAssertThrowsError(try AdPairCodec.parse(try encode(["extra": true], code: parsed))) {
            XCTAssertEqual(($0 as? AdPairCodeError)?.code, "unknown-field")
        }
        XCTAssertThrowsError(try AdPairCodec.parse(try encode(["version": 2], code: parsed))) {
            XCTAssertEqual(($0 as? AdPairCodeError)?.code, "unsupported-code-version")
        }
        XCTAssertThrowsError(try AdPairCodec.parse(try encode(["mode": "other"], code: parsed))) {
            XCTAssertEqual(($0 as? AdPairCodeError)?.code, "invalid-mode")
        }
        XCTAssertThrowsError(
            try AdPairCodec.parse(
                challenge.serialized,
                options: AdPairCodeParseOptions(now: Date(timeIntervalSince1970: Double(parsed.offer.expiresAt) / 1000))
            )
        ) { XCTAssertEqual(($0 as? AdPairCodeError)?.code, "expired-code") }
        XCTAssertThrowsError(
            try AdPairCodec.parse(
                challenge.serialized,
                options: AdPairCodeParseOptions(expectedMode: .qrSecret, now: now)
            )
        ) { XCTAssertEqual(($0 as? AdPairCodeError)?.code, "invalid-mode") }
    }

    func testPinRegistrationIsDeterministicAndBoundToPinAndIdentities() throws {
        let challenge = try AdPairCodec.createPinChallenge(
            offer: try makeOffer(),
            now: now,
            randomBytes: { Data(repeating: 1, count: $0) }
        )
        let code = try AdPairCodec.parse(
            challenge.serialized,
            options: AdPairCodeParseOptions(now: now)
        )
        let pin = try XCTUnwrap(challenge.pin)
        let host = try AdPairCodec.deriveRegistration(
            code: code,
            pin: pin,
            initiatorDeviceId: "ad-device:" + String(repeating: "1", count: 64),
            responderDeviceId: "ad-device:" + String(repeating: "2", count: 64)
        )
        let controller = try AdPairCodec.deriveRegistration(
            code: code,
            pin: pin,
            initiatorDeviceId: "ad-device:" + String(repeating: "1", count: 64),
            responderDeviceId: "ad-device:" + String(repeating: "2", count: 64)
        )
        let wrongPin = try AdPairCodec.deriveRegistration(
            code: code,
            pin: pin == "999999" ? "000000" : "999999",
            initiatorDeviceId: "ad-device:" + String(repeating: "1", count: 64),
            responderDeviceId: "ad-device:" + String(repeating: "2", count: 64)
        )
        let wrongIdentity = try AdPairCodec.deriveRegistration(
            code: code,
            pin: pin,
            initiatorDeviceId: "ad-device:" + String(repeating: "1", count: 64),
            responderDeviceId: "ad-device:" + String(repeating: "3", count: 64)
        )

        XCTAssertEqual(host, controller)
        XCTAssertNotEqual(host.w0, wrongPin.w0)
        XCTAssertNotEqual(host.w1, wrongIdentity.w1)
        XCTAssertEqual(host.L.count, 65)
        XCTAssertEqual(host.profile, Spake2PlusP256.passwordPBKDFProfile)
    }

    func testQrSecretRegistrationDrivesInteractiveSpakeSession() throws {
        let challenge = try AdPairCodec.createQrSecretChallenge(
            offer: try makeOffer(),
            now: now,
            randomBytes: { Data(repeating: 9, count: $0) }
        )
        let code = try AdPairCodec.parse(
            challenge.serialized,
            options: AdPairCodeParseOptions(now: now)
        )
        let idProver = "ad-device:" + String(repeating: "4", count: 64)
        let idVerifier = "ad-device:" + String(repeating: "5", count: 64)
        let registration = try AdPairCodec.deriveRegistration(
            code: code,
            pin: nil,
            initiatorDeviceId: idProver,
            responderDeviceId: idVerifier
        )
        let prover = Spake2PlusP256Session(
            role: .prover,
            context: Data("AD-PAIR-1".utf8),
            idProver: Data(idProver.utf8),
            idVerifier: Data(idVerifier.utf8),
            w0: registration.w0,
            w1: registration.w1
        )
        let verifier = Spake2PlusP256Session(
            role: .verifier,
            context: Data("AD-PAIR-1".utf8),
            idProver: Data(idProver.utf8),
            idVerifier: Data(idVerifier.utf8),
            w0: registration.w0,
            L: registration.L
        )
        let shareP = try prover.proverStart()
        let response = try verifier.verifierRespond(shareP: shareP)
        let proverResult = try prover.proverFinish(
            shareV: response.share,
            confirmationV: response.confirmation
        )
        let verifierResult = try verifier.verifierFinish(
            confirmationP: proverResult.confirmation
        )

        XCTAssertEqual(proverResult.keys.kShared, verifierResult.keys.kShared)
        XCTAssertEqual(proverResult.transcript, verifierResult.transcript)
    }

    func testPinAttemptGuardLocksResetsAndExpires() throws {
        let expiresAt = now.addingTimeInterval(60)
        var current = now
        let attempts = try AdPairPinAttemptGuard(maxAttempts: 3, now: { current })
        let key = "pin"

        try attempts.assertAllowed(key: key, expiresAt: expiresAt)
        XCTAssertEqual(try attempts.recordFailure(key: key, expiresAt: expiresAt), 2)
        XCTAssertEqual(try attempts.recordFailure(key: key, expiresAt: expiresAt), 1)
        XCTAssertEqual(try attempts.recordFailure(key: key, expiresAt: expiresAt), 0)
        XCTAssertThrowsError(try attempts.assertAllowed(key: key, expiresAt: expiresAt)) {
            XCTAssertEqual(($0 as? AdPairCodeError)?.code, "pin-locked")
        }
        attempts.reset(key: key)
        try attempts.assertAllowed(key: key, expiresAt: expiresAt)
        attempts.recordSuccess(key: key)

        current = expiresAt
        XCTAssertThrowsError(try attempts.assertAllowed(key: key, expiresAt: expiresAt)) {
            XCTAssertEqual(($0 as? AdPairCodeError)?.code, "expired-code")
        }
    }

    private func makeOffer() throws -> AdPairPayload {
        try AdPairPayload.make(
            kind: .offer,
            identity: try DeviceIdentity(),
            expiresIn: 60,
            endpointHint: "wss://host.example:443/airdesk",
            capabilities: ["display"],
            channelBinding: try AdPairChannelBinding(
                kind: .certificateHash,
                value: certificateHash
            ),
            now: now
        )
    }

    private func encode(_ overrides: [String: Any], code: AdPairCode) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(code)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        for (key, value) in overrides {
            object[key] = value
        }
        let updated = try JSONSerialization.data(withJSONObject: object)
        return AdPairCode.prefix + PairingEncoding.base64URLString(updated)
    }
}
