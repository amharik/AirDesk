// Pairing primitives only: offer payload validation, local registry and transcript hashing.
// AD-PAIR-1 (SPAKE2+, QR/PIN, TLS exporter binding and network transport) is not implemented here.
import CryptoKit
import Foundation
import Security

enum PairingProtocol {
    static let name = "airdesk-pairing"
    static let version = "1"
    static let defaultLifetime: TimeInterval = 120
    static let maximumLifetime: TimeInterval = 600
    static let nonceByteCount = 32
}

enum PairingChannelBindingKind: String, Codable {
    case tlsExporter = "tls-exporter"
    case certificateSHA256 = "certificate-sha256"
}

struct PairingChannelBinding: Codable, Equatable {
    var kind: PairingChannelBindingKind
    var value: String
}

struct PairingOffer: Codable, Equatable {
    var protocolName: String
    var version: String
    var deviceId: String
    var publicKeySPKI: Data
    var nonce: String
    var expiresAt: Date
    var endpointHint: String?
    var relayHint: String?
    var requestedCapabilities: [String]
    var channelBinding: PairingChannelBinding

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case version
        case deviceId
        case publicKeySPKI = "publicKey"
        case nonce
        case expiresAt
        case endpointHint
        case relayHint
        case requestedCapabilities
        case channelBinding
    }

    init(
        protocolName: String,
        version: String,
        deviceId: String,
        publicKeySPKI: Data,
        nonce: String,
        expiresAt: Date,
        endpointHint: String?,
        relayHint: String?,
        requestedCapabilities: [String],
        channelBinding: PairingChannelBinding
    ) {
        self.protocolName = protocolName
        self.version = version
        self.deviceId = deviceId
        self.publicKeySPKI = publicKeySPKI
        self.nonce = nonce
        self.expiresAt = expiresAt
        self.endpointHint = endpointHint
        self.relayHint = relayHint
        self.requestedCapabilities = requestedCapabilities
        self.channelBinding = channelBinding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolName = try container.decode(String.self, forKey: .protocolName)
        version = try container.decode(String.self, forKey: .version)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        publicKeySPKI = try container.decode(Data.self, forKey: .publicKeySPKI)
        nonce = try container.decode(String.self, forKey: .nonce)
        let expiry = try container.decode(String.self, forKey: .expiresAt)
        guard let date = PairingEncoding.date(from: expiry) else {
            throw DecodingError.dataCorruptedError(
                forKey: .expiresAt,
                in: container,
                debugDescription: "The offer expiry is not an ISO 8601 timestamp."
            )
        }
        expiresAt = date
        endpointHint = try container.decodeIfPresent(String.self, forKey: .endpointHint)
        relayHint = try container.decodeIfPresent(String.self, forKey: .relayHint)
        requestedCapabilities = try container.decodeIfPresent(
            [String].self,
            forKey: .requestedCapabilities
        ) ?? []
        channelBinding = try container.decode(PairingChannelBinding.self, forKey: .channelBinding)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolName, forKey: .protocolName)
        try container.encode(version, forKey: .version)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(publicKeySPKI, forKey: .publicKeySPKI)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(PairingEncoding.string(from: expiresAt), forKey: .expiresAt)
        try container.encodeIfPresent(endpointHint, forKey: .endpointHint)
        try container.encodeIfPresent(relayHint, forKey: .relayHint)
        try container.encode(requestedCapabilities, forKey: .requestedCapabilities)
        try container.encode(channelBinding, forKey: .channelBinding)
    }

    static func make(
        identity: DeviceIdentity,
        expiresIn: TimeInterval = PairingProtocol.defaultLifetime,
        endpointHint: String? = nil,
        relayHint: String? = nil,
        requestedCapabilities: [String] = [],
        channelBinding: PairingChannelBinding,
        nonce: Data? = nil,
        now: Date = Date()
    ) throws -> PairingOffer {
        guard expiresIn > 0, expiresIn <= PairingProtocol.maximumLifetime else {
            throw PairingOfferValidationError.invalidExpiry
        }
        let nonceData = try nonce ?? PairingNonce.random()
        guard nonceData.count == PairingProtocol.nonceByteCount else {
            throw PairingOfferValidationError.invalidNonce
        }
        return PairingOffer(
            protocolName: PairingProtocol.name,
            version: PairingProtocol.version,
            deviceId: identity.deviceId,
            publicKeySPKI: identity.spki,
            nonce: PairingEncoding.hexString(nonceData),
            expiresAt: now.addingTimeInterval(expiresIn),
            endpointHint: endpointHint,
            relayHint: relayHint,
            requestedCapabilities: requestedCapabilities,
            channelBinding: channelBinding
        )
    }

    func jsonData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    func jsonString(prettyPrinted: Bool = false) throws -> String {
        let data = try jsonData(prettyPrinted: prettyPrinted)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PairingOfferValidationError.malformedJSON
        }
        return string
    }
}

enum PairingOfferValidationError: LocalizedError, Equatable {
    case malformedJSON
    case unsupportedProtocol(String)
    case unsupportedVersion(String)
    case invalidDeviceId
    case publicKeyMismatch
    case invalidNonce
    case invalidExpiry
    case offerExpired
    case invalidChannelBinding
    case invalidCapabilities
    case selfPairing
    case replayedOffer

    var errorDescription: String? {
        switch self {
        case .malformedJSON:
            return "The pairing offer is not valid JSON for this protocol."
        case .unsupportedProtocol(let value):
            return "Unsupported pairing protocol: \(value)."
        case .unsupportedVersion(let value):
            return "Unsupported pairing protocol version: \(value)."
        case .invalidDeviceId:
            return "The pairing offer device ID is invalid."
        case .publicKeyMismatch:
            return "The pairing offer device ID does not match its public key."
        case .invalidNonce:
            return "The pairing offer nonce is invalid."
        case .invalidExpiry:
            return "The pairing offer expiry is outside the accepted window."
        case .offerExpired:
            return "The pairing offer has expired."
        case .invalidChannelBinding:
            return "The pairing offer channel binding is missing or invalid."
        case .invalidCapabilities:
            return "The pairing offer requests invalid capabilities."
        case .selfPairing:
            return "A device cannot pair with itself."
        case .replayedOffer:
            return "The pairing offer has already been used."
        }
    }
}

final class PairingOfferReplayCache {
    private let lock = NSLock()
    private var seen: [String: Date] = [:]

    func claim(_ offer: PairingOffer, now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        seen = seen.filter { $0.value > now }
        let key = offer.deviceId + ":" + offer.nonce
        guard seen[key] == nil else {
            throw PairingOfferValidationError.replayedOffer
        }
        seen[key] = offer.expiresAt
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        seen.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return seen.count
    }
}

final class PairingOfferValidator {
    let localDeviceId: String
    let replayCache: PairingOfferReplayCache

    init(
        localDeviceId: String,
        replayCache: PairingOfferReplayCache = PairingOfferReplayCache()
    ) {
        self.localDeviceId = localDeviceId
        self.replayCache = replayCache
    }

    func decodeAndValidate(_ data: Data, now: Date = Date()) throws -> PairingOffer {
        let offer: PairingOffer
        do {
            offer = try JSONDecoder().decode(PairingOffer.self, from: data)
        } catch {
            throw PairingOfferValidationError.malformedJSON
        }
        try validate(offer, now: now)
        return offer
    }

    func decodeAndValidateAndClaim(_ data: Data, now: Date = Date()) throws -> PairingOffer {
        let offer = try decodeAndValidate(data, now: now)
        try replayCache.claim(offer, now: now)
        return offer
    }

    func validate(_ offer: PairingOffer, now: Date = Date()) throws {
        guard offer.protocolName == PairingProtocol.name else {
            throw PairingOfferValidationError.unsupportedProtocol(offer.protocolName)
        }
        guard offer.version == PairingProtocol.version else {
            throw PairingOfferValidationError.unsupportedVersion(offer.version)
        }
        guard PairingEncoding.isDeviceId(offer.deviceId) else {
            throw PairingOfferValidationError.invalidDeviceId
        }

        let publicKey: DevicePublicKey
        do {
            publicKey = try DevicePublicKey(spki: offer.publicKeySPKI)
        } catch {
            throw PairingOfferValidationError.publicKeyMismatch
        }
        guard publicKey.deviceId == offer.deviceId else {
            throw PairingOfferValidationError.publicKeyMismatch
        }
        guard offer.deviceId != localDeviceId else {
            throw PairingOfferValidationError.selfPairing
        }

        guard let nonce = PairingEncoding.data(hex: offer.nonce),
              nonce.count == PairingProtocol.nonceByteCount,
              PairingEncoding.hexString(nonce) == offer.nonce else {
            throw PairingOfferValidationError.invalidNonce
        }

        let remaining = offer.expiresAt.timeIntervalSince(now)
        guard remaining > 0 else {
            throw PairingOfferValidationError.offerExpired
        }
        guard remaining <= PairingProtocol.maximumLifetime else {
            throw PairingOfferValidationError.invalidExpiry
        }

        guard PairingEncoding.isLowercaseHex(offer.channelBinding.value, byteCount: 32) else {
            throw PairingOfferValidationError.invalidChannelBinding
        }

        let capabilities = offer.requestedCapabilities
        guard capabilities.count <= 32,
              capabilities.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              Set(capabilities).count == capabilities.count else {
            throw PairingOfferValidationError.invalidCapabilities
        }
    }
}

struct PairingGrant: Codable, Equatable {
    var capabilities: [String]
    var workspaceMembershipId: String?
    var controllerRole: String?

    static let none = PairingGrant(
        capabilities: [],
        workspaceMembershipId: nil,
        controllerRole: nil
    )

    var grantsNothing: Bool {
        capabilities.isEmpty && workspaceMembershipId == nil && controllerRole == nil
    }
}

struct PairingAcceptance: Equatable {
    let peer: PairedPeerRecord
    let grant: PairingGrant
    let transcriptHash: Data?
}

final class PairingService {
    let identity: DeviceIdentity
    let registry: DeviceRegistry
    let validator: PairingOfferValidator

    init(
        identity: DeviceIdentity,
        registry: DeviceRegistry,
        replayCache: PairingOfferReplayCache = PairingOfferReplayCache()
    ) {
        self.identity = identity
        self.registry = registry
        self.validator = PairingOfferValidator(
            localDeviceId: identity.deviceId,
            replayCache: replayCache
        )
    }

    func accept(
        offerJSON: Data,
        displayLabel: String? = nil,
        now: Date = Date()
    ) throws -> PairingAcceptance {
        let offer = try validator.decodeAndValidateAndClaim(offerJSON, now: now)
        let label = displayLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let record = PairedPeerRecord(
            deviceId: offer.deviceId,
            displayLabel: label.isEmpty ? "Paired device" : label,
            publicKeySPKI: offer.publicKeySPKI,
            trustState: .trusted,
            pairedAt: now
        )
        try registry.upsert(record)
        return PairingAcceptance(
            peer: record,
            grant: .none,
            transcriptHash: nil
        )
    }
}

struct PairingTranscript: Equatable {
    var protocolName: String
    var version: String
    var initiatorDeviceId: String
    var responderDeviceId: String
    var initiatorNonce: String
    var responderNonce: String
    var expiresAt: Date
    var endpointHint: String?
    var relayHint: String?
    var requestedCapabilities: [String]
    var channelBindingKind: PairingChannelBindingKind
    var channelBindingValue: String

    static let domain = "airdesk.pairing.transcript.primitives.v1"

    static func make(
        offer: PairingOffer,
        responderDeviceId: String,
        responderNonce: String
    ) -> PairingTranscript {
        PairingTranscript(
            protocolName: offer.protocolName,
            version: offer.version,
            initiatorDeviceId: offer.deviceId,
            responderDeviceId: responderDeviceId,
            initiatorNonce: offer.nonce,
            responderNonce: responderNonce,
            expiresAt: offer.expiresAt,
            endpointHint: offer.endpointHint,
            relayHint: offer.relayHint,
            requestedCapabilities: offer.requestedCapabilities,
            channelBindingKind: offer.channelBinding.kind,
            channelBindingValue: offer.channelBinding.value
        )
    }

    var canonicalData: Data {
        var data = Data()
        PairingEncoding.append(Self.domain, to: &data)
        PairingEncoding.append(protocolName, to: &data)
        PairingEncoding.append(version, to: &data)
        PairingEncoding.append(initiatorDeviceId, to: &data)
        PairingEncoding.append(responderDeviceId, to: &data)
        PairingEncoding.append(initiatorNonce, to: &data)
        PairingEncoding.append(responderNonce, to: &data)
        PairingEncoding.append(
            String(Int64((expiresAt.timeIntervalSince1970 * 1000).rounded())),
            to: &data
        )
        PairingEncoding.append(optional: endpointHint, to: &data)
        PairingEncoding.append(optional: relayHint, to: &data)
        PairingEncoding.append(String(requestedCapabilities.count), to: &data)
        for capability in requestedCapabilities {
            PairingEncoding.append(capability, to: &data)
        }
        PairingEncoding.append(channelBindingKind.rawValue, to: &data)
        PairingEncoding.append(channelBindingValue, to: &data)
        return data
    }

    var hash: Data {
        Data(SHA256.hash(data: canonicalData))
    }

    var sas: String {
        var value: UInt32 = 0
        for byte in hash.prefix(4) {
            value = (value << 8) | UInt32(byte)
        }
        return String(format: "%06u", value % 1_000_000)
    }
}

enum PairingEncoding {
    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func data(hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        data.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    static func isDeviceId(_ value: String) -> Bool {
        guard value.hasPrefix(DeviceIdentity.deviceIdPrefix) else { return false }
        let fingerprint = value.dropFirst(DeviceIdentity.deviceIdPrefix.count)
        return isLowercaseHex(String(fingerprint), byteCount: 32)
    }

    static func isLowercaseHex(_ value: String, byteCount: Int) -> Bool {
        guard value.count == byteCount * 2 else { return false }
        return value.allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }
    }

    static func append(_ string: String, to data: inout Data) {
        let bytes = Data(string.utf8)
        var length = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(bytes)
    }

    static func append(optional string: String?, to data: inout Data) {
        data.append(string == nil ? 0 : 1)
        if let string {
            append(string, to: &data)
        }
    }

    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: string)
    }

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

enum PairingNonce {
    static func random(count: Int = PairingProtocol.nonceByteCount) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PairingOfferValidationError.invalidNonce
        }
        return Data(bytes)
    }
}
