import CryptoKit
import XCTest
@testable import AirDesk

final class AdPairSessionTests: XCTestCase {
    private let certificateHash = String(repeating: "ab", count: 32)
    private let initiatorPKCS8 = "MC4CAQAwBQYDK2VwBCIEIOtYcwX1wGZGNeo12HdIN1NPe6FhByCoa56tUm5Jj35T"
    private let responderPKCS8 = "MC4CAQAwBQYDK2VwBCIEIOX6bNZf-BG7fSmfikUAp0RcmFxN2EuWxr03eSNjlyjf"
    private let initiatorDeviceId = "ad-device:bf49f1ff3d9f3aece51b722385c7d07a610b0cd69f0145da24f17a7b14529592"
    private let responderDeviceId = "ad-device:f2c55a697ca4e2a671b99d7aa9fdf4d09222f64125cbb4735d1f28356252a3e9"
    private let expectedTranscriptHash = "b11a14c0c9b48e68bf8a5f63844ad252b4965aca7fd7e34307528506325a946d"
    private let expectedSAS = "726110"
    private let expectedInitiatorSignature = "0moSm9MqRy-WvamcCmGlEFKY0DoxbN5cDaCTGxP81ntvdvYvsQaYkhDzmzg95Dvk7muwPb_OIyai231_4rWLDg"
    private let expectedResponderSignature = "jyk6_s9FpQAmoLdWdbSbyRDW-upxu4eT8yCeCuZJrccLb851WDLjTI8U0_i3AX8EkHbWZcty11FfsY2J_mBGDQ"
    private let expectedInitiatorToResponderKey = "a0885c05c54fe82f5dc06913e8431765aa514be7782c7217f9e512cf78f559c6"
    private let expectedResponderToInitiatorKey = "13a3ca8258829d32d6f564ae05ca40e9c619d007a31e4f9b8239743c29deaed0"
    private let expectedTransportKey = "4f355ecc94dc6560a67e159ff092ec71917e7ba0cfdc82916789761edc8220d6"

    func testCanonicalTranscriptMatchesBrowserFixture() throws {
        let transcript = try AdPairTranscript.canonical(
            offer: try offer(),
            response: try response(),
            pake: try pake()
        )
        let hash = Data(SHA256.hash(data: transcript))

        XCTAssertEqual(hex(hash), expectedTranscriptHash)
        XCTAssertEqual(
            AdPairTranscript.shortAuthenticationString(transcriptHash: hash),
            expectedSAS
        )
    }

    func testSessionMatchesBrowserSignaturesAndKeys() throws {
        let offer = try offer()
        let response = try response()
        let pake = try pake()
        let session = AdPairSession(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        _ = try session.acceptOffer(JSONEncoder().encode(offer))
        _ = try session.acceptResponse(JSONEncoder().encode(response))

        let initiator = try identity(pkcs8: initiatorPKCS8)
        let responder = try identity(pkcs8: responderPKCS8)
        XCTAssertEqual(initiator.deviceId, initiatorDeviceId)
        XCTAssertEqual(responder.deviceId, responderDeviceId)

        let transcript = try AdPairTranscript.canonical(
            offer: offer,
            response: response,
            pake: pake
        )
        let initiatorSignature = try initiator.sign(transcript)
        let responderSignature = try responder.sign(transcript)
        XCTAssertTrue(
            initiator.publicKey.verify(signature: initiatorSignature, for: transcript)
        )
        XCTAssertTrue(
            responder.publicKey.verify(signature: responderSignature, for: transcript)
        )
        XCTAssertTrue(
            try initiator.publicKey.verify(
                signature: data(base64URL: expectedInitiatorSignature),
                for: transcript
            )
        )
        XCTAssertTrue(
            try responder.publicKey.verify(
                signature: data(base64URL: expectedResponderSignature),
                for: transcript
            )
        )

        let result = try session.finish(
            AdPairFinishInput(
                pake: pake,
                sharedSecret: try data(base64URL: "CwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws"),
                initiatorSignature: initiatorSignature,
                responderSignature: responderSignature,
                expectedTranscriptHash: try data(hex: expectedTranscriptHash)
            )
        )

        XCTAssertEqual(result.transcriptHash, try data(hex: expectedTranscriptHash))
        XCTAssertEqual(result.shortAuthenticationString, expectedSAS)
        XCTAssertEqual(hex(result.sessionKeys.initiatorToResponder.bytes), expectedInitiatorToResponderKey)
        XCTAssertEqual(hex(result.sessionKeys.responderToInitiator.bytes), expectedResponderToInitiatorKey)
        XCTAssertEqual(hex(result.sessionKeys.transport.bytes), expectedTransportKey)
        XCTAssertEqual(result.capabilities, ["clipboard-read", "display"])
        XCTAssertTrue(result.grant.grantsNothing)
    }

    func testSessionRejectsTamperedSignatureAndBinding() throws {
        let offer = try offer()
        let response = try response()
        let pake = try pake()
        let session = AdPairSession(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        _ = try session.acceptOffer(JSONEncoder().encode(offer))
        _ = try session.acceptResponse(JSONEncoder().encode(response))
        let initiator = try identity(pkcs8: initiatorPKCS8)
        let responder = try identity(pkcs8: responderPKCS8)
        let transcript = try AdPairTranscript.canonical(
            offer: offer,
            response: response,
            pake: pake
        )
        var tampered = try initiator.sign(transcript)
        tampered[0] ^= 1
        XCTAssertThrowsError(
            try session.finish(
                AdPairFinishInput(
                    pake: pake,
                    sharedSecret: Data(repeating: 11, count: 32),
                    initiatorSignature: tampered,
                    responderSignature: try responder.sign(transcript)
                )
            )
        ) { XCTAssertEqual(($0 as? AdPairError)?.code, "invalid-signature") }

        let otherBinding = try AdPairChannelBinding(
            kind: .certificateHash,
            value: String(repeating: "cd", count: 32)
        )
        let mismatched = AdPairPayload(
            kind: .response,
            deviceId: response.deviceId,
            publicKey: response.publicKey,
            nonce: response.nonce,
            replyTo: response.replyTo,
            expiresAt: response.expiresAt,
            endpointHint: response.endpointHint,
            capabilities: response.capabilities,
            channelBinding: otherBinding
        )
        let rejected = AdPairSession(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        _ = try rejected.acceptOffer(JSONEncoder().encode(offer))
        XCTAssertThrowsError(
            try rejected.acceptResponse(JSONEncoder().encode(mismatched))
        ) { XCTAssertEqual(($0 as? AdPairError)?.code, "channel-binding-mismatch") }
    }

    private func offer() throws -> AdPairPayload {
        AdPairPayload(
            kind: .offer,
            deviceId: initiatorDeviceId,
            publicKey: "MCowBQYDK2VwAyEA--KKsMwStkz3ugymNTHz7bDSzD0C1nL1puCwV96jQME",
            nonce: "AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM",
            expiresAt: 1_700_000_060_000,
            endpointHint: "wss://host.example:443/airdesk",
            relayHint: "https://relay.example/session/ad-pair-1",
            capabilities: ["display", "clipboard-read"],
            channelBinding: try AdPairChannelBinding(
                kind: .certificateHash,
                value: certificateHash
            )
        )
    }

    private func response() throws -> AdPairPayload {
        AdPairPayload(
            kind: .response,
            deviceId: responderDeviceId,
            publicKey: "MCowBQYDK2VwAyEAK63pMiSLqtPnAtKVup_xjO5TkDrI3UOKhW103ajRxTQ",
            nonce: "BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ",
            replyTo: "AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM",
            expiresAt: 1_700_000_060_000,
            endpointHint: "wss://host.example:443/airdesk",
            capabilities: ["display"],
            channelBinding: try AdPairChannelBinding(
                kind: .certificateHash,
                value: certificateHash
            )
        )
    }

    private func pake() throws -> AdPairPakeEvidence {
        try AdPairPakeEvidence(
            initiatorShare: "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE",
            responderShare: "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI",
            initiatorConfirmation: "BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU",
            responderConfirmation: "BgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgY"
        )
    }

    private func identity(pkcs8: String) throws -> DeviceIdentity {
        let data = try data(base64URL: pkcs8)
        return try DeviceIdentity(algorithm: .ed25519, privateKeyRaw: Data(data.suffix(32)))
    }

    private func data(base64URL: String) throws -> Data {
        try XCTUnwrap(PairingEncoding.data(base64URL: base64URL))
    }

    private func data(hex: String) throws -> Data {
        try XCTUnwrap(PairingEncoding.data(hex: hex))
    }

    private func hex(_ data: Data) -> String {
        PairingEncoding.hexString(data)
    }
}
