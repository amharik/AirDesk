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

    func testPairingRecordsPeersInRegistry() throws {
        let hostIdentity = try DeviceIdentity()
        let controllerIdentity = try DeviceIdentity()
        let hostRegistry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let controllerRegistry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let host = AdPairCoordinator(
            role: .initiator,
            identity: hostIdentity,
            registry: hostRegistry,
            peerDisplayLabel: "Controller",
            now: { self.now },
            randomBytes: { Data(repeating: 6, count: $0) }
        )
        let controller = AdPairCoordinator(
            role: .responder,
            identity: controllerIdentity,
            registry: controllerRegistry,
            peerDisplayLabel: "Host",
            now: { self.now }
        )
        let start = try host.startInitiator(mode: .pin, channelBinding: binding)
        let pin = try XCTUnwrap(start.challenge.pin)
        let join = try controller.joinResponder(
            code: start.challenge.serialized,
            pin: pin
        )
        let shareP = try host.acceptResponse(join.responseData)
        let reply = try controller.respond(shareP: shareP)
        let finished = try host.finishInitiator(
            shareV: reply.share,
            responderConfirmation: reply.confirmation,
            responderSignature: reply.signature
        )
        _ = try controller.finishResponder(
            initiatorConfirmation: finished.confirmation,
            initiatorSignature: finished.signature
        )

        XCTAssertEqual(hostRegistry.peer(deviceId: controllerIdentity.deviceId)?.displayLabel, "Controller")
        XCTAssertTrue(hostRegistry.isTrusted(deviceId: controllerIdentity.deviceId))
        XCTAssertEqual(controllerRegistry.peer(deviceId: hostIdentity.deviceId)?.displayLabel, "Host")
        XCTAssertTrue(controllerRegistry.isTrusted(deviceId: hostIdentity.deviceId))
    }

    func testRevokedPeersCannotJoinOrComplete() throws {
        let offerRegistry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let responseRegistry = try DeviceRegistry(storage: InMemoryDeviceRegistryStorage())
        let hostIdentity = try DeviceIdentity()
        let controllerIdentity = try DeviceIdentity()
        try offerRegistry.upsert(
            PairedPeerRecord(
                deviceId: hostIdentity.deviceId,
                displayLabel: "Host",
                publicKeySPKI: hostIdentity.spki,
                pairedAt: now
            )
        )
        try offerRegistry.revoke(deviceId: hostIdentity.deviceId, at: now)
        try responseRegistry.upsert(
            PairedPeerRecord(
                deviceId: controllerIdentity.deviceId,
                displayLabel: "Controller",
                publicKeySPKI: controllerIdentity.spki,
                pairedAt: now
            )
        )
        try responseRegistry.revoke(deviceId: controllerIdentity.deviceId, at: now)

        let host = AdPairCoordinator(
            role: .initiator,
            identity: hostIdentity,
            registry: responseRegistry,
            now: { self.now },
            randomBytes: { Data(repeating: 7, count: $0) }
        )
        let controller = AdPairCoordinator(
            role: .responder,
            identity: controllerIdentity,
            registry: offerRegistry,
            now: { self.now }
        )
        let start = try host.startInitiator(mode: .pin, channelBinding: binding)
        let pin = try XCTUnwrap(start.challenge.pin)
        XCTAssertThrowsError(
            try controller.joinResponder(code: start.challenge.serialized, pin: pin)
        ) { XCTAssertEqual(($0 as? AdPairError)?.code, "revoked-device") }

        let cleanController = AdPairCoordinator(
            role: .responder,
            identity: controllerIdentity,
            now: { self.now }
        )
        let join = try cleanController.joinResponder(
            code: start.challenge.serialized,
            pin: pin
        )
        XCTAssertThrowsError(try host.acceptResponse(join.responseData)) {
            XCTAssertEqual(($0 as? AdPairError)?.code, "revoked-device")
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
