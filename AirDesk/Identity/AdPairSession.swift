import CryptoKit
import Foundation

struct AdPairChannelBinding: Codable, Equatable {
    enum Kind: String, Codable {
        case exporter
        case certificateHash = "certificate-hash"
    }

    let kind: Kind
    let value: String

    init(kind: Kind, value: String) throws {
        switch kind {
        case .certificateHash:
            guard Self.isHex(value, byteCount: 32) else {
                throw AdPairError.invalidBinding
            }
            self.kind = kind
            self.value = value.lowercased()
        case .exporter:
            guard let bytes = PairingEncoding.data(base64URL: value), bytes.count >= 16 else {
                throw AdPairError.invalidBinding
            }
            self.kind = kind
            self.value = value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        try self.init(kind: kind, value: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private static func isHex(_ value: String, byteCount: Int) -> Bool {
        guard value.count == byteCount * 2 else { return false }
        return value.allSatisfy { character in
            ("0"..."9").contains(character)
                || ("a"..."f").contains(character)
                || ("A"..."F").contains(character)
        }
    }
}

struct AdPairPakeEvidence: Codable, Equatable {
    let initiatorShare: String
    let responderShare: String
    let initiatorConfirmation: String
    let responderConfirmation: String

    init(
        initiatorShare: String,
        responderShare: String,
        initiatorConfirmation: String,
        responderConfirmation: String
    ) throws {
        try Self.validate(initiatorShare, name: "initiator share")
        try Self.validate(responderShare, name: "responder share")
        try Self.validate(initiatorConfirmation, name: "initiator confirmation")
        try Self.validate(responderConfirmation, name: "responder confirmation")
        self.initiatorShare = initiatorShare
        self.responderShare = responderShare
        self.initiatorConfirmation = initiatorConfirmation
        self.responderConfirmation = responderConfirmation
    }

    init(
        initiatorShare: Data,
        responderShare: Data,
        initiatorConfirmation: Data,
        responderConfirmation: Data
    ) throws {
        try self.init(
            initiatorShare: PairingEncoding.base64URLString(initiatorShare),
            responderShare: PairingEncoding.base64URLString(responderShare),
            initiatorConfirmation: PairingEncoding.base64URLString(initiatorConfirmation),
            responderConfirmation: PairingEncoding.base64URLString(responderConfirmation)
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            initiatorShare: container.decode(String.self, forKey: .initiatorShare),
            responderShare: container.decode(String.self, forKey: .responderShare),
            initiatorConfirmation: container.decode(String.self, forKey: .initiatorConfirmation),
            responderConfirmation: container.decode(String.self, forKey: .responderConfirmation)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case initiatorShare
        case responderShare
        case initiatorConfirmation
        case responderConfirmation
    }

    private static func validate(_ value: String, name: String) throws {
        guard let bytes = PairingEncoding.data(base64URL: value),
              (16...1024).contains(bytes.count) else {
            throw AdPairError.invalidPakeEvidence("\(name) is invalid")
        }
    }
}

struct AdPairPayload: Codable, Equatable {
    enum Kind: String, Codable {
        case offer
        case response
    }

    static let protocolName = "adfp"
    static let version = "0.1"

    let protocolName: String
    let version: String
    let kind: Kind
    let deviceId: String
    let publicKey: String
    let nonce: String
    let replyTo: String?
    let expiresAt: Int64
    let endpointHint: String?
    let relayHint: String?
    let capabilities: [String]
    let channelBinding: AdPairChannelBinding

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case version
        case kind = "type"
        case deviceId
        case publicKey
        case nonce
        case replyTo
        case expiresAt
        case endpointHint
        case relayHint
        case capabilities
        case channelBinding
    }

    init(
        kind: Kind,
        deviceId: String,
        publicKey: String,
        nonce: String,
        replyTo: String? = nil,
        expiresAt: Int64,
        endpointHint: String? = nil,
        relayHint: String? = nil,
        capabilities: [String],
        channelBinding: AdPairChannelBinding
    ) {
        self.protocolName = Self.protocolName
        self.version = Self.version
        self.kind = kind
        self.deviceId = deviceId
        self.publicKey = publicKey
        self.nonce = nonce
        self.replyTo = replyTo
        self.expiresAt = expiresAt
        self.endpointHint = endpointHint
        self.relayHint = relayHint
        self.capabilities = capabilities
        self.channelBinding = channelBinding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolName = try container.decode(String.self, forKey: .protocolName)
        version = try container.decode(String.self, forKey: .version)
        kind = try container.decode(Kind.self, forKey: .kind)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        publicKey = try container.decode(String.self, forKey: .publicKey)
        nonce = try container.decode(String.self, forKey: .nonce)
        replyTo = try container.decodeIfPresent(String.self, forKey: .replyTo)
        expiresAt = try container.decode(Int64.self, forKey: .expiresAt)
        endpointHint = try container.decodeIfPresent(String.self, forKey: .endpointHint)
        relayHint = try container.decodeIfPresent(String.self, forKey: .relayHint)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        channelBinding = try container.decode(AdPairChannelBinding.self, forKey: .channelBinding)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolName, forKey: .protocolName)
        try container.encode(version, forKey: .version)
        try container.encode(kind, forKey: .kind)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(nonce, forKey: .nonce)
        try container.encodeIfPresent(replyTo, forKey: .replyTo)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(endpointHint, forKey: .endpointHint)
        try container.encodeIfPresent(relayHint, forKey: .relayHint)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(channelBinding, forKey: .channelBinding)
    }

    static func make(
        kind: Kind,
        identity: DeviceIdentity,
        replyTo: String? = nil,
        expiresIn: TimeInterval = 60,
        endpointHint: String? = nil,
        relayHint: String? = nil,
        capabilities: [String] = [],
        channelBinding: AdPairChannelBinding,
        nonce: Data? = nil,
        now: Date = Date()
    ) throws -> AdPairPayload {
        guard expiresIn > 0 else {
            throw AdPairError.invalidExpiry
        }
        let nonce = try nonce ?? PairingNonce.random()
        return AdPairPayload(
            kind: kind,
            deviceId: identity.deviceId,
            publicKey: PairingEncoding.base64URLString(identity.spki),
            nonce: PairingEncoding.base64URLString(nonce),
            replyTo: replyTo,
            expiresAt: Int64((now.addingTimeInterval(expiresIn).timeIntervalSince1970 * 1000).rounded()),
            endpointHint: endpointHint,
            relayHint: relayHint,
            capabilities: capabilities,
            channelBinding: channelBinding
        )
    }

    func validate(
        expectedKind: Kind,
        now: Date = Date(),
        localDeviceId: String? = nil
    ) throws {
        guard protocolName == Self.protocolName else {
            throw AdPairError.unsupportedProtocol
        }
        guard version == Self.version else {
            throw AdPairError.unsupportedVersion
        }
        guard kind == expectedKind else {
            throw AdPairError.unexpectedType
        }
        guard PairingEncoding.isDeviceId(deviceId) else {
            throw AdPairError.invalidDeviceId
        }
        let publicKeyData: Data
        do {
            guard let data = PairingEncoding.data(base64URL: publicKey) else {
                throw AdPairError.invalidPublicKey
            }
            publicKeyData = data
        } catch {
            throw AdPairError.invalidPublicKey
        }
        let devicePublicKey: DevicePublicKey
        do {
            devicePublicKey = try DevicePublicKey(spki: publicKeyData)
        } catch {
            throw AdPairError.invalidPublicKey
        }
        guard devicePublicKey.deviceId == deviceId else {
            throw AdPairError.publicKeyMismatch
        }
        if let localDeviceId, localDeviceId == deviceId {
            throw AdPairError.selfPairing
        }
        guard let nonceData = PairingEncoding.data(base64URL: nonce),
              (16...128).contains(nonceData.count) else {
            throw AdPairError.invalidNonce
        }
        if expectedKind == .offer {
            guard replyTo == nil else {
                throw AdPairError.invalidReplyTo
            }
        } else {
            guard let replyTo,
                  let replyToData = PairingEncoding.data(base64URL: replyTo),
                  (16...128).contains(replyToData.count) else {
                throw AdPairError.invalidReplyTo
            }
        }
        guard expiresAt > Int64((now.timeIntervalSince1970 * 1000).rounded()) else {
            throw AdPairError.expired
        }
        if let endpointHint {
            try Self.validateHint(endpointHint)
        }
        if let relayHint {
            try Self.validateHint(relayHint)
        }
        guard capabilities.count <= 64,
              capabilities.allSatisfy({ !$0.isEmpty && $0.count <= 128 }),
              Set(capabilities).count == capabilities.count else {
            throw AdPairError.invalidCapabilities
        }
    }

    private static func validateHint(_ value: String) throws {
        guard !value.isEmpty, value.count <= 2048 else {
            throw AdPairError.invalidHint
        }
    }
}

enum AdPairError: Swift.Error, Equatable, LocalizedError {
    case unsupportedProtocol
    case unsupportedVersion
    case unexpectedType
    case invalidDeviceId
    case invalidPublicKey
    case publicKeyMismatch
    case invalidNonce
    case invalidReplyTo
    case invalidExpiry
    case expired
    case invalidBinding
    case bindingMismatch
    case invalidPakeEvidence(String)
    case missingSignature
    case invalidSignature(String)
    case transcriptMismatch
    case replayedNonce
    case selfPairing
    case invalidCapabilities
    case invalidHint
    case invalidState(String)

    var code: String {
        switch self {
        case .unsupportedProtocol: return "unsupported-protocol"
        case .unsupportedVersion: return "unsupported-version"
        case .unexpectedType: return "unexpected-type"
        case .invalidDeviceId: return "invalid-device-id"
        case .invalidPublicKey: return "invalid-public-key"
        case .publicKeyMismatch: return "signature-device-mismatch"
        case .invalidNonce: return "invalid-nonce"
        case .invalidReplyTo: return "invalid-reply-to"
        case .invalidExpiry: return "invalid-expiry"
        case .expired: return "expired"
        case .invalidBinding: return "invalid-binding"
        case .bindingMismatch: return "channel-binding-mismatch"
        case .invalidPakeEvidence: return "invalid-pake-evidence"
        case .missingSignature: return "missing-signature"
        case .invalidSignature: return "invalid-signature"
        case .transcriptMismatch: return "transcript-mismatch"
        case .replayedNonce: return "replayed-nonce"
        case .selfPairing: return "self-pairing"
        case .invalidCapabilities: return "invalid-capabilities"
        case .invalidHint: return "invalid-hint"
        case .invalidState: return "invalid-state"
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocol: return "Unsupported pairing protocol."
        case .unsupportedVersion: return "Unsupported pairing version."
        case .unexpectedType: return "Unexpected pairing payload type."
        case .invalidDeviceId: return "Invalid pairing device ID."
        case .invalidPublicKey: return "Invalid pairing public key."
        case .publicKeyMismatch: return "Device ID does not match the pairing public key."
        case .invalidNonce: return "Invalid pairing nonce."
        case .invalidReplyTo: return "Invalid pairing reply-to nonce."
        case .invalidExpiry: return "Invalid pairing expiry."
        case .expired: return "Pairing payload has expired."
        case .invalidBinding: return "Invalid pairing channel binding."
        case .bindingMismatch: return "Pairing channel binding mismatch."
        case .invalidPakeEvidence(let detail): return "Invalid PAKE evidence: \(detail)."
        case .missingSignature: return "Pairing transcript signature is required."
        case .invalidSignature(let role): return "Invalid \(role) transcript signature."
        case .transcriptMismatch: return "Pairing transcript mismatch."
        case .replayedNonce: return "Pairing nonce has already been used."
        case .selfPairing: return "A device cannot pair with itself."
        case .invalidCapabilities: return "Invalid pairing capabilities."
        case .invalidHint: return "Invalid pairing hint."
        case .invalidState(let detail): return "Invalid pairing state: \(detail)."
        }
    }
}

enum AdPairTranscript {
    static let domain = "AD-PAIR-1"
    static let sasDomain = "AD-PAIR-1-SAS"

    static func canonical(
        offer: AdPairPayload,
        response: AdPairPayload,
        pake: AdPairPakeEvidence
    ) throws -> Data {
        guard offer.channelBinding == response.channelBinding else {
            throw AdPairError.bindingMismatch
        }
        let json = """
        {"domain":"\(domain)","protocol":\(quoted(offer.protocolName)),"version":\(quoted(offer.version)),"channelBinding":\(bindingJSON(offer.channelBinding)),"offer":\(payloadJSON(offer)),"response":\(payloadJSON(response)),"pake":{"initiatorShare":\(quoted(pake.initiatorShare)),"responderShare":\(quoted(pake.responderShare)),"initiatorConfirmation":\(quoted(pake.initiatorConfirmation)),"responderConfirmation":\(quoted(pake.responderConfirmation))}}
        """
        return Data("\(domain)\n\(json)".utf8)
    }

    static func hash(
        offer: AdPairPayload,
        response: AdPairPayload,
        pake: AdPairPakeEvidence
    ) throws -> Data {
        Data(SHA256.hash(data: try canonical(offer: offer, response: response, pake: pake)))
    }

    static func shortAuthenticationString(transcriptHash: Data) -> String {
        let digest = Data(SHA256.hash(data: Data("\(sasDomain)\n".utf8) + transcriptHash))
        var value: UInt32 = 0
        for byte in digest.prefix(4) {
            value = (value << 8) | UInt32(byte)
        }
        return String(format: "%06u", value % 1_000_000)
    }

    private static func payloadJSON(_ payload: AdPairPayload) -> String {
        let replyTo = payload.replyTo.map(quoted) ?? "null"
        let endpointHint = payload.endpointHint.map(quoted) ?? "null"
        let relayHint = payload.relayHint.map(quoted) ?? "null"
        let capabilities = payload.capabilities.sorted().map(quoted).joined(separator: ",")
        return """
        {"type":\(quoted(payload.kind.rawValue)),"deviceId":\(quoted(payload.deviceId)),"publicKey":\(quoted(payload.publicKey)),"nonce":\(quoted(payload.nonce)),"replyTo":\(replyTo),"expiresAt":\(payload.expiresAt),"endpointHint":\(endpointHint),"relayHint":\(relayHint),"capabilities":[\(capabilities)],"channelBinding":\(bindingJSON(payload.channelBinding))}
        """
    }

    private static func bindingJSON(_ binding: AdPairChannelBinding) -> String {
        "{\"kind\":\(quoted(binding.kind.rawValue)),\"value\":\(quoted(binding.value))}"
    }

    private static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}

struct AdPairFinishInput {
    let pake: AdPairPakeEvidence
    let sharedSecret: Data
    let initiatorSignature: Data
    let responderSignature: Data
    let expectedTranscriptHash: Data?

    init(
        pake: AdPairPakeEvidence,
        sharedSecret: Data,
        initiatorSignature: Data,
        responderSignature: Data,
        expectedTranscriptHash: Data? = nil
    ) {
        self.pake = pake
        self.sharedSecret = sharedSecret
        self.initiatorSignature = initiatorSignature
        self.responderSignature = responderSignature
        self.expectedTranscriptHash = expectedTranscriptHash
    }
}

struct AdPairResult {
    let offer: AdPairPayload
    let response: AdPairPayload
    let transcript: Data
    let transcriptHash: Data
    let shortAuthenticationString: String
    let channelBinding: AdPairChannelBinding
    let capabilities: [String]
    let initiatorSignature: Data
    let responderSignature: Data
    let sessionKeys: PairingKeySchedule.Keys
    let grant: PairingGrant
}

final class AdPairSession {
    enum State {
        case initial
        case offerAccepted
        case responseAccepted
        case completed
    }

    private let now: () -> Date
    private let localDeviceId: String?
    private var seenNonces: Set<String> = []
    private var offer: AdPairPayload?
    private var response: AdPairPayload?
    private(set) var state: State = .initial

    init(
        localDeviceId: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.localDeviceId = localDeviceId
        self.now = now
    }

    func acceptOffer(_ data: Data) throws -> AdPairPayload {
        guard state == .initial else {
            throw AdPairError.invalidState("pairing offer is not expected")
        }
        do {
            let payload = try JSONDecoder().decode(AdPairPayload.self, from: data)
            try payload.validate(
                expectedKind: .offer,
                now: now(),
                localDeviceId: localDeviceId
            )
            try claimNonce(payload.nonce)
            offer = payload
            state = .offerAccepted
            return payload
        } catch {
            state = .initial
            throw error
        }
    }

    func acceptResponse(_ data: Data) throws -> AdPairPayload {
        guard state == .offerAccepted, let offer else {
            throw AdPairError.invalidState("pairing response is not expected")
        }
        do {
            let payload = try JSONDecoder().decode(AdPairPayload.self, from: data)
            try payload.validate(
                expectedKind: .response,
                now: now(),
                localDeviceId: localDeviceId
            )
            guard payload.replyTo == offer.nonce else {
                throw AdPairError.invalidReplyTo
            }
            guard payload.channelBinding == offer.channelBinding else {
                throw AdPairError.bindingMismatch
            }
            try claimNonce(payload.nonce)
            response = payload
            state = .responseAccepted
            return payload
        } catch {
            state = .offerAccepted
            throw error
        }
    }

    func finish(_ input: AdPairFinishInput) throws -> AdPairResult {
        guard state == .responseAccepted, let offer, let response else {
            throw AdPairError.invalidState("pairing is not ready to finish")
        }
        guard input.sharedSecret.count >= 16, input.sharedSecret.count <= 1024 else {
            throw AdPairError.invalidPakeEvidence("shared secret length out of range")
        }
        guard PairingEncoding.data(base64URL: input.pake.initiatorConfirmation)?.count == 32,
              PairingEncoding.data(base64URL: input.pake.responderConfirmation)?.count == 32 else {
            throw AdPairError.invalidPakeEvidence("confirmation must be 32 bytes")
        }
        guard !input.initiatorSignature.isEmpty else {
            throw AdPairError.missingSignature
        }
        guard !input.responderSignature.isEmpty else {
            throw AdPairError.missingSignature
        }
        let transcript = try AdPairTranscript.canonical(
            offer: offer,
            response: response,
            pake: input.pake
        )
        let transcriptHash = Data(SHA256.hash(data: transcript))
        if let expected = input.expectedTranscriptHash, expected != transcriptHash {
            throw AdPairError.transcriptMismatch
        }
        try verify(
            input.initiatorSignature,
            transcript: transcript,
            publicKey: offer.publicKey,
            role: "initiator"
        )
        try verify(
            input.responderSignature,
            transcript: transcript,
            publicKey: response.publicKey,
            role: "responder"
        )
        let sessionKeys = try PairingKeySchedule.derive(
            pakeSharedSecret: input.sharedSecret,
            transcriptHash: transcriptHash,
            channelBinding: PairingChannelBinding(
                kind: offer.channelBinding.kind == .certificateHash
                    ? .certificateSHA256
                    : .tlsExporter,
                value: offer.channelBinding.value
            )
        )
        state = .completed
        return AdPairResult(
            offer: offer,
            response: response,
            transcript: transcript,
            transcriptHash: transcriptHash,
            shortAuthenticationString: AdPairTranscript.shortAuthenticationString(
                transcriptHash: transcriptHash
            ),
            channelBinding: offer.channelBinding,
            capabilities: Array(Set(offer.capabilities + response.capabilities)).sorted(),
            initiatorSignature: input.initiatorSignature,
            responderSignature: input.responderSignature,
            sessionKeys: sessionKeys,
            grant: .none
        )
    }

    private func verify(
        _ signature: Data,
        transcript: Data,
        publicKey: String,
        role: String
    ) throws {
        guard let spki = PairingEncoding.data(base64URL: publicKey),
              let key = try? DevicePublicKey(spki: spki),
              key.verify(signature: signature, for: transcript) else {
            throw AdPairError.invalidSignature(role)
        }
    }

    private func claimNonce(_ nonce: String) throws {
        guard seenNonces.insert(nonce).inserted else {
            throw AdPairError.replayedNonce
        }
    }
}
