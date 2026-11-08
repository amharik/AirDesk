import XCTest
@testable import AirDesk

final class PairingCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let binding = try! AdPairChannelBinding(
        kind: .certificateHash,
        value: String(repeating: "ab", count: 32)
    )

    func testPinFlowProducesMatchingPairingResults() throws {
        let host = AdPairCoordinator(
            role: .initiator,
            identity: try DeviceIdentity(),
            now: { self.now },
            randomBytes: { Data(repeating: 3, count: $0) }
        )
        let controller = AdPairCoordinator(
            role: .responder,
            identity: try DeviceIdentity(),
            now: { self.now }
        )
        let start = try host.startInitiator(
            mode: .pin,
            channelBinding: binding,
            endpointHint: "wss://host.example:443/airdesk",
            capabilities: ["display"]
        )
        let pin = try XCTUnwrap(start.challenge.pin)
        let join = try controller.joinResponder(
            code: start.challenge.serialized,
            pin: pin,
            endpointHint: "wss://controller.example:443/airdesk",
            capabilities: ["controller"]
        )
        let shareP = try host.acceptResponse(join.responseData)
        let reply = try controller.respond(shareP: shareP)
        let finished = try host.finishInitiator(
            shareV: reply.share,
            responderConfirmation: reply.confirmation,
            responderSignature: reply.signature
        )
        let controllerFinished = try controller.finishResponder(
            initiatorConfirmation: finished.confirmation,
            initiatorSignature: finished.signature
        )

        XCTAssertEqual(start.offer.deviceId, host.identity.deviceId)
        XCTAssertEqual(join.response.replyTo, start.offer.nonce)
        XCTAssertEqual(finished.result.transcriptHash, controllerFinished.result.transcriptHash)
        XCTAssertEqual(finished.result.shortAuthenticationString, controllerFinished.result.shortAuthenticationString)
        XCTAssertEqual(finished.result.sessionKeys, controllerFinished.result.sessionKeys)
        XCTAssertEqual(finished.result.capabilities, ["controller", "display"])
        XCTAssertTrue(finished.result.grant.grantsNothing)
        XCTAssertNotEqual(finished.confirmation, reply.confirmation)
        XCTAssertEqual(finished.result.transcriptHash, try AdPairTranscript.hash(
            offer: start.offer,
            response: join.response,
            pake: AdPairPakeEvidence(
                initiatorShare: shareP,
                responderShare: reply.share,
                initiatorConfirmation: finished.confirmation,
                responderConfirmation: reply.confirmation
            )
        ))
    }

    func testQrSecretFlowUsesScannedSecret() throws {
        let host = AdPairCoordinator(
            role: .initiator,
            identity: try DeviceIdentity(),
            now: { self.now },
            randomBytes: { Data(repeating: 8, count: $0) }
        )
        let controller = AdPairCoordinator(
            role: .responder,
            identity: try DeviceIdentity(),
            now: { self.now }
        )
        let start = try host.startInitiator(
            mode: .qrSecret,
            channelBinding: binding
        )
        XCTAssertNil(start.challenge.pin)
        let join = try controller.joinResponder(code: start.challenge.serialized)
        let shareP = try host.acceptResponse(join.responseData)
        let reply = try controller.respond(shareP: shareP)
        let finished = try host.finishInitiator(
            shareV: reply.share,
            responderConfirmation: reply.confirmation,
            responderSignature: reply.signature
        )
        let controllerFinished = try controller.finishResponder(
            initiatorConfirmation: finished.confirmation,
            initiatorSignature: finished.signature
        )

        XCTAssertEqual(finished.result.sessionKeys, controllerFinished.result.sessionKeys)
        XCTAssertEqual(finished.result.shortAuthenticationString, controllerFinished.result.shortAuthenticationString)
    }

    func testWrongPinFailsConfirmation() throws {
        let host = AdPairCoordinator(
            role: .initiator,
            identity: try DeviceIdentity(),
            now: { self.now },
            randomBytes: { Data(repeating: 4, count: $0) }
        )
        let controller = AdPairCoordinator(
            role: .responder,
            identity: try DeviceIdentity(),
            now: { self.now }
        )
        let start = try host.startInitiator(mode: .pin, channelBinding: binding)
        let pin = try XCTUnwrap(start.challenge.pin)
        let wrongPin = pin == "999999" ? "000000" : "999999"
        let join = try controller.joinResponder(
            code: start.challenge.serialized,
            pin: wrongPin
        )
        let shareP = try host.acceptResponse(join.responseData)
        let reply = try controller.respond(shareP: shareP)

        XCTAssertThrowsError(
            try host.finishInitiator(
                shareV: reply.share,
                responderConfirmation: reply.confirmation,
                responderSignature: reply.signature
            )
        ) {
            XCTAssertEqual(($0 as? Spake2PlusP256.Error), .confirmationMismatch)
        }
    }

    func testRejectsWrongRoleWrongStateAndExpiredCode() throws {
        let host = AdPairCoordinator(
            role: .initiator,
            identity: try DeviceIdentity(),
            now: { self.now },
            randomBytes: { Data(repeating: 5, count: $0) }
        )
        let controller = AdPairCoordinator(
            role: .responder,
            identity: try DeviceIdentity(),
            now: { self.now }
        )

        XCTAssertThrowsError(
            try controller.startInitiator(mode: .pin, channelBinding: binding)
        ) { XCTAssertEqual(($0 as? AdPairError)?.code, "invalid-state") }
        XCTAssertThrowsError(
            try host.joinResponder(code: "ADPAIR1:invalid")
        ) { XCTAssertEqual(($0 as? AdPairError)?.code, "invalid-state") }

        let start = try host.startInitiator(mode: .pin, channelBinding: binding)
        let expired = AdPairCoordinator(
            role: .responder,
            identity: try DeviceIdentity(),
            now: { self.now.addingTimeInterval(61) }
        )
        XCTAssertThrowsError(
            try expired.joinResponder(code: start.challenge.serialized)
        ) { XCTAssertEqual(($0 as? AdPairCodeError), .expiredCode) }
    }
}
