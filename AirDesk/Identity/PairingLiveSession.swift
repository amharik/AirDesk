import Combine
import Foundation

@MainActor
final class AdPairLiveSession: ObservableObject {
    enum Role {
        case host
        case controller
    }

    enum State: Equatable {
        case idle
        case waitingForController
        case awaitingShare
        case awaitingVerifierResponse
        case awaitingInitiatorFinish
        case awaitingUserVerification
        case completed
        case failed(String)
    }

    let role: Role
    @Published private(set) var state: State = .idle
    @Published private(set) var code: String?
    @Published private(set) var pin: String?
    @Published private(set) var shortAuthenticationString: String?
    @Published private(set) var peerDeviceId: String?
    @Published private(set) var lastError: String?

    private let identity: DeviceIdentity
    private let peer: IrohFabricPeer
    private let registry: DeviceRegistry?
    private let relayPolicy: IrohRelayPolicy
    private let peerDisplayLabel: String?
    private let now: () -> Date
    private let randomBytes: (Int) throws -> Data
    private var coordinator: AdPairCoordinator?
    private var result: AdPairResult?
    private var callbackInstalled = false

    init(
        role: Role,
        identity: DeviceIdentity,
        peer: IrohFabricPeer,
        registry: DeviceRegistry? = nil,
        relayPolicy: IrohRelayPolicy = .directOnly,
        peerDisplayLabel: String? = nil,
        now: @escaping () -> Date = Date.init,
        randomBytes: @escaping (Int) throws -> Data = { try PairingNonce.random(count: $0) }
    ) {
        self.role = role
        self.identity = identity
        self.peer = peer
        self.registry = registry
        self.relayPolicy = relayPolicy
        self.peerDisplayLabel = peerDisplayLabel
        self.now = now
        self.randomBytes = randomBytes
    }

    func startHost(
        mode: AdPairCode.Mode,
        expiresIn: TimeInterval = 60,
        capabilities: [String] = []
    ) async throws {
        guard role == .host, state == .idle else {
            throw AdPairLiveError.invalidState
        }
        do {
            try await ensurePeerReady(requireTicket: true)
            let binding = try AdPairChannelBinding(
                kind: .irohEndpoint,
                value: peer.endpointID
            )
            let coordinator = AdPairCoordinator(
                role: .initiator,
                identity: identity,
                registry: registry,
                peerDisplayLabel: peerDisplayLabel,
                now: now,
                randomBytes: randomBytes
            )
            let start = try coordinator.startInitiator(
                mode: mode,
                channelBinding: binding,
                expiresIn: expiresIn,
                endpointHint: peer.ticket,
                capabilities: capabilities
            )
            self.coordinator = coordinator
            self.code = start.challenge.serialized
            self.pin = start.challenge.pin
            installCallback()
            state = .waitingForController
        } catch {
            fail(error)
            throw error
        }
    }

    func join(
        code: String,
        pin: String? = nil,
        expiresIn: TimeInterval = 60,
        capabilities: [String] = []
    ) async throws {
        guard role == .controller, state == .idle else {
            throw AdPairLiveError.invalidState
        }
        do {
            let parsed = try AdPairCodec.parse(
                code,
                options: AdPairCodeParseOptions(now: now(), localDeviceId: identity.deviceId)
            )
            guard parsed.offer.channelBinding.kind == .irohEndpoint else {
                throw AdPairError.invalidBinding
            }
            guard let ticket = parsed.offer.endpointHint else {
                throw AdPairError.invalidHint
            }
            try await ensurePeerReady(requireTicket: false)
            try await peer.connect(to: ticket)
            guard peer.remoteEndpointID == parsed.offer.channelBinding.value else {
                throw AdPairError.bindingMismatch
            }
            let coordinator = AdPairCoordinator(
                role: .responder,
                identity: identity,
                registry: registry,
                peerDisplayLabel: peerDisplayLabel,
                now: now,
                randomBytes: randomBytes
            )
            let join = try coordinator.joinResponder(
                code: code,
                pin: pin,
                expiresIn: expiresIn,
                endpointHint: peer.ticket,
                capabilities: capabilities
            )
            self.coordinator = coordinator
            self.peerDeviceId = parsed.offer.deviceId
            installCallback()
            try send(try AdPairWireMessage.response(join.responseData))
            state = .awaitingShare
        } catch {
            fail(error)
            throw error
        }
    }

    func confirmShortAuthenticationString(_ entered: String) throws -> PairingKeySchedule.Keys {
        guard state == .awaitingUserVerification, let result else {
            throw AdPairLiveError.invalidState
        }
        let normalized = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized == result.shortAuthenticationString else {
            throw AdPairLiveError.shortAuthenticationStringMismatch
        }
        state = .completed
        return result.sessionKeys
    }

    func cancel() {
        if callbackInstalled {
            peer.onPairingMessage = nil
            callbackInstalled = false
        }
        coordinator = nil
        result = nil
        code = nil
        pin = nil
        shortAuthenticationString = nil
        peerDeviceId = nil
        lastError = nil
        state = .idle
    }

    private func ensurePeerReady(requireTicket: Bool) async throws {
        switch peer.state {
        case .stopped, .failed:
            await peer.start(relayPolicy: relayPolicy)
        case .starting, .ready, .connecting, .connected:
            break
        }
        for _ in 0..<50 {
            if peer.state == .failed {
                throw AdPairLiveError.peerUnavailable(peer.lastError ?? "The Iroh fabric failed.")
            }
            if !peer.endpointID.isEmpty, !requireTicket || !peer.ticket.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw AdPairLiveError.peerUnavailable(
            peer.lastError ?? "The Iroh fabric did not become ready."
        )
    }

    private func installCallback() {
        guard !callbackInstalled else { return }
        callbackInstalled = true
        peer.onPairingMessage = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.receive(data)
            }
        }
    }

    private func receive(_ data: Data) {
        do {
            let message = try AdPairWireMessage.decode(data)
            switch (role, message.kind) {
            case (.host, .response):
                guard state == .waitingForController,
                      let coordinator,
                      let response = message.response else {
                    throw AdPairLiveError.invalidState
                }
                let share = try coordinator.acceptResponse(response)
                try send(try AdPairWireMessage.share(share))
                state = .awaitingVerifierResponse
            case (.controller, .share):
                guard state == .awaitingShare,
                      let coordinator,
                      let share = message.share else {
                    throw AdPairLiveError.invalidState
                }
                let reply = try coordinator.respond(shareP: share)
                try send(
                    try AdPairWireMessage.verifierResponse(
                        share: reply.share,
                        confirmation: reply.confirmation,
                        signature: reply.signature
                    )
                )
                state = .awaitingInitiatorFinish
            case (.host, .verifierResponse):
                guard state == .awaitingVerifierResponse,
                      let coordinator,
                      let share = message.share,
                      let confirmation = message.confirmation,
                      let signature = message.signature else {
                    throw AdPairLiveError.invalidState
                }
                let completion = try coordinator.finishInitiator(
                    shareV: share,
                    responderConfirmation: confirmation,
                    responderSignature: signature
                )
                try send(
                    try AdPairWireMessage.initiatorFinish(
                        confirmation: completion.confirmation,
                        signature: completion.signature
                    )
                )
                complete(with: completion.result)
            case (.controller, .initiatorFinish):
                guard state == .awaitingInitiatorFinish,
                      let coordinator,
                      let confirmation = message.confirmation,
                      let signature = message.signature else {
                    throw AdPairLiveError.invalidState
                }
                let completion = try coordinator.finishResponder(
                    initiatorConfirmation: confirmation,
                    initiatorSignature: signature
                )
                try? send(
                    try AdPairWireMessage.responderFinish(
                        confirmation: completion.confirmation,
                        signature: completion.signature
                    )
                )
                complete(with: completion.result)
            case (.host, .responderFinish):
                break
            default:
                throw AdPairLiveError.invalidState
            }
        } catch {
            fail(error)
        }
    }

    private func complete(with result: AdPairResult) {
        self.result = result
        shortAuthenticationString = result.shortAuthenticationString
        peerDeviceId = peerDeviceId
            ?? result.response.deviceId
        state = .awaitingUserVerification
    }

    private func send(_ message: AdPairWireMessage) throws {
        guard peer.sendPairing(try message.encoded()) else {
            throw AdPairLiveError.peerUnavailable("The pairing connection is not active.")
        }
    }

    private func fail(_ error: Error) {
        let message = error.localizedDescription
        lastError = message
        state = .failed(message)
    }
}

enum AdPairLiveError: Swift.Error, Equatable, LocalizedError {
    case invalidState
    case shortAuthenticationStringMismatch
    case peerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidState: return "The pairing session is not in the expected state."
        case .shortAuthenticationStringMismatch:
            return "The pairing verification code does not match."
        case .peerUnavailable(let detail): return detail
        }
    }
}
