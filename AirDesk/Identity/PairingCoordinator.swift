import Foundation

final class AdPairCoordinator {
    enum Role {
        case initiator
        case responder
    }

    enum State {
        case initial
        case offerCreated
        case joined
        case awaitingVerifierResponse
        case awaitingInitiator
        case completed
    }

    struct InitiatorStart {
        let offer: AdPairPayload
        let challenge: AdPairChallenge
    }

    struct ResponderJoin {
        let offer: AdPairPayload
        let response: AdPairPayload
        let responseData: Data
    }

    struct ResponderResponse {
        let share: Data
        let confirmation: Data
        let signature: Data
    }

    struct InitiatorCompletion {
        let result: AdPairResult
        let share: Data
        let confirmation: Data
        let signature: Data
    }

    struct ResponderCompletion {
        let result: AdPairResult
        let share: Data
        let confirmation: Data
        let signature: Data
    }

    let role: Role
    let identity: DeviceIdentity
    private let registry: DeviceRegistry?
    private let peerDisplayLabel: String?
    private let now: () -> Date
    private let randomBytes: (Int) throws -> Data
    private var session: AdPairSession?
    private var offer: AdPairPayload?
    private var response: AdPairPayload?
    private var challenge: AdPairChallenge?
    private var spake: Spake2PlusP256Session?
    private var shareP: Data?
    private var shareV: Data?
    private var confirmP: Data?
    private var confirmV: Data?
    private var responderSignature: Data?
    private(set) var state: State = .initial

    init(
        role: Role,
        identity: DeviceIdentity,
        registry: DeviceRegistry? = nil,
        peerDisplayLabel: String? = nil,
        now: @escaping () -> Date = Date.init,
        randomBytes: @escaping (Int) throws -> Data = { try PairingNonce.random(count: $0) }
    ) {
        self.role = role
        self.identity = identity
        self.registry = registry
        self.peerDisplayLabel = peerDisplayLabel
        self.now = now
        self.randomBytes = randomBytes
    }

    func startInitiator(
        mode: AdPairCode.Mode,
        channelBinding: AdPairChannelBinding,
        expiresIn: TimeInterval = 60,
        endpointHint: String? = nil,
        capabilities: [String] = []
    ) throws -> InitiatorStart {
        guard role == .initiator else {
            throw AdPairError.invalidState("only the initiator creates an offer")
        }
        guard state == .initial else {
            throw AdPairError.invalidState("pairing offer is not expected")
        }
        let offer = try AdPairPayload.make(
            kind: .offer,
            identity: identity,
            expiresIn: expiresIn,
            endpointHint: endpointHint,
            capabilities: capabilities,
            channelBinding: channelBinding,
            now: now()
        )
        let challenge = try makeChallenge(offer: offer, mode: mode)
        let session = AdPairSession(now: now)
        _ = try session.acceptOffer(encode(offer))
        self.offer = offer
        self.challenge = challenge
        self.session = session
        state = .offerCreated
        return InitiatorStart(offer: offer, challenge: challenge)
    }

    func joinResponder(
        code: String,
        pin: String? = nil,
        expiresIn: TimeInterval = 60,
        endpointHint: String? = nil,
        capabilities: [String] = []
    ) throws -> ResponderJoin {
        guard role == .responder else {
            throw AdPairError.invalidState("only the responder scans a pairing code")
        }
        guard state == .initial else {
            throw AdPairError.invalidState("pairing code is not expected")
        }
        let parsed = try AdPairCodec.parse(
            code,
            options: AdPairCodeParseOptions(now: now(), localDeviceId: identity.deviceId)
        )
        let offer = parsed.offer
        guard offer.deviceId != identity.deviceId else {
            throw AdPairError.selfPairing
        }
        try assertNotRevoked(offer.deviceId)
        let session = AdPairSession(now: now)
        _ = try session.acceptOffer(encode(offer))

        let remaining = TimeInterval(offer.expiresAt) / 1000 - now().timeIntervalSince1970
        guard remaining > 0 else {
            throw AdPairCodeError.expiredCode
        }
        let response = try AdPairPayload.make(
            kind: .response,
            identity: identity,
            replyTo: offer.nonce,
            expiresIn: max(1, min(expiresIn, remaining)),
            endpointHint: endpointHint,
            capabilities: capabilities,
            channelBinding: offer.channelBinding,
            now: now()
        )
        let responseData = try encode(response)
        _ = try session.acceptResponse(responseData)

        let registration = try AdPairCodec.deriveRegistration(
            code: parsed,
            pin: pin,
            initiatorDeviceId: offer.deviceId,
            responderDeviceId: response.deviceId
        )
        let spake = Spake2PlusP256Session(
            role: .verifier,
            context: Data(AdPairTranscript.domain.utf8),
            idProver: Data(offer.deviceId.utf8),
            idVerifier: Data(response.deviceId.utf8),
            w0: registration.w0,
            L: registration.L
        )
        self.offer = offer
        self.response = response
        self.challenge = nil
        self.session = session
        self.spake = spake
        state = .joined
        return ResponderJoin(offer: offer, response: response, responseData: responseData)
    }

    func acceptResponse(_ data: Data) throws -> Data {
        guard role == .initiator else {
            throw AdPairError.invalidState("only the initiator accepts a response")
        }
        guard state == .offerCreated,
              let session,
              let offer,
              let challenge else {
            throw AdPairError.invalidState("pairing response is not expected")
        }
        let response = try session.acceptResponse(data)
        guard response.deviceId != identity.deviceId else {
            throw AdPairError.selfPairing
        }
        try assertNotRevoked(response.deviceId)
        let registration = try AdPairCodec.deriveRegistration(
            code: challenge.code,
            pin: challenge.pin,
            initiatorDeviceId: offer.deviceId,
            responderDeviceId: response.deviceId
        )
        let spake = Spake2PlusP256Session(
            role: .prover,
            context: Data(AdPairTranscript.domain.utf8),
            idProver: Data(offer.deviceId.utf8),
            idVerifier: Data(response.deviceId.utf8),
            w0: registration.w0,
            w1: registration.w1
        )
        let shareP = try spake.proverStart()
        self.response = response
        self.spake = spake
        self.shareP = shareP
        state = .awaitingVerifierResponse
        return shareP
    }

    func respond(shareP: Data) throws -> ResponderResponse {
        guard role == .responder else {
            throw AdPairError.invalidState("only the responder responds to a prover share")
        }
        guard state == .joined,
              let offer,
              let response,
              let spake else {
            throw AdPairError.invalidState("responder is not awaiting a prover share")
        }
        let reply = try spake.verifierRespond(shareP: shareP)
        let confirmP = try spake.verifierConfirmationP()
        let evidence = try AdPairPakeEvidence(
            initiatorShare: shareP,
            responderShare: reply.share,
            initiatorConfirmation: confirmP,
            responderConfirmation: reply.confirmation
        )
        let transcript = try AdPairTranscript.canonical(
            offer: offer,
            response: response,
            pake: evidence
        )
        let signature = try identity.sign(transcript)
        self.shareP = shareP
        self.shareV = reply.share
        self.confirmP = confirmP
        self.confirmV = reply.confirmation
        self.responderSignature = signature
        state = .awaitingInitiator
        return ResponderResponse(
            share: reply.share,
            confirmation: reply.confirmation,
            signature: signature
        )
    }

    func finishInitiator(
        shareV: Data,
        responderConfirmation: Data,
        responderSignature: Data
    ) throws -> InitiatorCompletion {
        guard role == .initiator else {
            throw AdPairError.invalidState("only the initiator finishes the prover exchange")
        }
        guard state == .awaitingVerifierResponse,
              let session,
              let offer,
              let response,
              let spake,
              let shareP else {
            throw AdPairError.invalidState("initiator is not awaiting a verifier response")
        }
        let result = try spake.proverFinish(
            shareV: shareV,
            confirmationV: responderConfirmation
        )
        let evidence = try AdPairPakeEvidence(
            initiatorShare: shareP,
            responderShare: shareV,
            initiatorConfirmation: result.confirmation,
            responderConfirmation: result.expectedConfirmation
        )
        let transcript = try AdPairTranscript.canonical(
            offer: offer,
            response: response,
            pake: evidence
        )
        let signature = try identity.sign(transcript)
        try assertNotRevoked(response.deviceId)
        let pairing = try session.finish(
            AdPairFinishInput(
                pake: evidence,
                sharedSecret: result.keys.kShared,
                initiatorSignature: signature,
                responderSignature: responderSignature,
                expectedTranscriptHash: try AdPairTranscript.hash(
                    offer: offer,
                    response: response,
                    pake: evidence
                )
            )
        )
        try recordPeer(response)
        state = .completed
        return InitiatorCompletion(
            result: pairing,
            share: shareP,
            confirmation: result.confirmation,
            signature: signature
        )
    }

    func finishResponder(
        initiatorConfirmation: Data,
        initiatorSignature: Data
    ) throws -> ResponderCompletion {
        guard role == .responder else {
            throw AdPairError.invalidState("only the responder finishes the verifier exchange")
        }
        guard state == .awaitingInitiator,
              let session,
              let offer,
              let response,
              let spake,
              let shareP,
              let shareV,
              let responderSignature else {
            throw AdPairError.invalidState("responder is not awaiting an initiator confirmation")
        }
        let result = try spake.verifierFinish(confirmationP: initiatorConfirmation)
        let evidence = try AdPairPakeEvidence(
            initiatorShare: shareP,
            responderShare: shareV,
            initiatorConfirmation: initiatorConfirmation,
            responderConfirmation: result.expectedConfirmation
        )
        try assertNotRevoked(offer.deviceId)
        let pairing = try session.finish(
            AdPairFinishInput(
                pake: evidence,
                sharedSecret: result.keys.kShared,
                initiatorSignature: initiatorSignature,
                responderSignature: responderSignature,
                expectedTranscriptHash: try AdPairTranscript.hash(
                    offer: offer,
                    response: response,
                    pake: evidence
                )
            )
        )
        try recordPeer(offer)
        state = .completed
        return ResponderCompletion(
            result: pairing,
            share: shareV,
            confirmation: result.expectedConfirmation,
            signature: responderSignature
        )
    }

    private func assertNotRevoked(_ deviceId: String) throws {
        guard registry?.isRevoked(deviceId: deviceId) != true else {
            throw AdPairError.revokedDevice
        }
    }

    private func recordPeer(_ payload: AdPairPayload) throws {
        guard let registry else { return }
        guard let spki = PairingEncoding.data(base64URL: payload.publicKey) else {
            throw AdPairError.invalidPublicKey
        }
        let requested = peerDisplayLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existing = registry.peer(deviceId: payload.deviceId)?.displayLabel ?? ""
        let label = [requested, existing].first { !$0.isEmpty } ?? "Paired device"
        let trustState: DeviceTrustState = registry.isTrusted(deviceId: payload.deviceId)
            ? .trusted
            : .pending
        try registry.upsert(
            PairedPeerRecord(
                deviceId: payload.deviceId,
                displayLabel: label,
                publicKeySPKI: spki,
                trustState: trustState,
                pairedAt: now()
            )
        )
    }

    private func makeChallenge(
        offer: AdPairPayload,
        mode: AdPairCode.Mode
    ) throws -> AdPairChallenge {
        switch mode {
        case .pin:
            return try AdPairCodec.createPinChallenge(
                offer: offer,
                now: now(),
                randomBytes: randomBytes
            )
        case .qrSecret:
            return try AdPairCodec.createQrSecretChallenge(
                offer: offer,
                now: now(),
                randomBytes: randomBytes
            )
        }
    }

    private func encode(_ payload: AdPairPayload) throws -> Data {
        try JSONEncoder().encode(payload)
    }
}
