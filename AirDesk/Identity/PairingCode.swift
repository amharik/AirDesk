import Foundation

struct AdPairCode: Codable, Equatable {
    enum Mode: String, Codable {
        case pin
        case qrSecret = "qr-secret"
    }

    static let protocolName = "adpair1"
    static let version = 1
    static let prefix = "ADPAIR1:"

    let protocolName: String
    let version: Int
    let mode: Mode
    let salt: String
    let secret: String?
    let offer: AdPairPayload

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case version
        case mode
        case salt
        case secret
        case offer
    }

    init(mode: Mode, salt: String, secret: String? = nil, offer: AdPairPayload) {
        self.protocolName = Self.protocolName
        self.version = Self.version
        self.mode = mode
        self.salt = salt
        self.secret = secret
        self.offer = offer
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolName, forKey: .protocolName)
        try container.encode(version, forKey: .version)
        try container.encode(mode, forKey: .mode)
        try container.encode(salt, forKey: .salt)
        try container.encodeIfPresent(secret, forKey: .secret)
        try container.encode(offer, forKey: .offer)
    }
}

struct AdPairChallenge {
    let code: AdPairCode
    let serialized: String
    let mode: AdPairCode.Mode
    let salt: Data
    let expiresAt: Int64
    let pin: String?
    let secret: Data?
}

struct AdPairCodeParseOptions {
    var expectedMode: AdPairCode.Mode?
    var now: Date = Date()
    var localDeviceId: String?
}

enum AdPairCodeError: Swift.Error, Equatable, LocalizedError {
    case invalidCode
    case malformedCode
    case unsupportedCodeVersion
    case unknownField(String)
    case invalidMode
    case invalidSalt
    case invalidSecret
    case invalidPin
    case expiredCode
    case pinLocked

    var code: String {
        switch self {
        case .invalidCode: return "invalid-code"
        case .malformedCode: return "malformed-code"
        case .unsupportedCodeVersion: return "unsupported-code-version"
        case .unknownField: return "unknown-field"
        case .invalidMode: return "invalid-mode"
        case .invalidSalt: return "invalid-salt"
        case .invalidSecret: return "invalid-secret"
        case .invalidPin: return "invalid-pin"
        case .expiredCode: return "expired-code"
        case .pinLocked: return "pin-locked"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "Invalid pairing code."
        case .malformedCode: return "Pairing code is not valid base64url JSON."
        case .unsupportedCodeVersion: return "Unsupported pairing code version."
        case .unknownField(let field): return "Unknown pairing code field: \(field)."
        case .invalidMode: return "Pairing code mode must be pin or qr-secret."
        case .invalidSalt: return "Invalid pairing salt."
        case .invalidSecret: return "Invalid QR pairing secret."
        case .invalidPin: return "PIN must be 6 digits."
        case .expiredCode: return "Pairing code has expired."
        case .pinLocked: return "Pairing PIN is locked."
        }
    }
}

enum AdPairCodec {
    static let pinDigits = 6
    static let minimumSaltBytes = 16
    static let maximumSaltBytes = 64
    static let minimumSecretBytes = 16
    static let maximumSecretBytes = 64

    static func serialize(_ code: AdPairCode) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(code)) ?? Data()
        return AdPairCode.prefix + PairingEncoding.base64URLString(data)
    }

    static func parse(
        _ raw: String,
        options: AdPairCodeParseOptions = AdPairCodeParseOptions()
    ) throws -> AdPairCode {
        guard !raw.isEmpty, raw.count <= 16_384 else {
            throw AdPairCodeError.invalidCode
        }
        guard raw.hasPrefix(AdPairCode.prefix) else {
            throw AdPairCodeError.invalidCode
        }
        let encoded = String(raw.dropFirst(AdPairCode.prefix.count))
        guard let data = PairingEncoding.data(base64URL: encoded), !data.isEmpty else {
            throw AdPairCodeError.malformedCode
        }
        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AdPairCodeError.malformedCode
            }
            object = decoded
        } catch {
            throw AdPairCodeError.malformedCode
        }
        let allowed = Set(["protocol", "version", "mode", "salt", "secret", "offer"])
        if let unknown = object.keys.first(where: { !allowed.contains($0) }) {
            throw AdPairCodeError.unknownField(unknown)
        }
        guard let mode = object["mode"] as? String, mode == "pin" || mode == "qr-secret" else {
            throw AdPairCodeError.invalidMode
        }
        let code: AdPairCode
        do {
            code = try JSONDecoder().decode(AdPairCode.self, from: data)
        } catch {
            throw AdPairCodeError.malformedCode
        }
        try validate(code, options: options)
        return code
    }

    static func createPinChallenge(
        offer: AdPairPayload,
        now: Date = Date(),
        randomBytes: (Int) throws -> Data = { try PairingNonce.random(count: $0) }
    ) throws -> AdPairChallenge {
        try requireLiveOffer(offer, now: now)
        let pin = try randomPin(randomBytes: randomBytes)
        let salt = try randomBytes(32)
        let code = AdPairCode(
            mode: .pin,
            salt: PairingEncoding.base64URLString(salt),
            offer: offer
        )
        return AdPairChallenge(
            code: code,
            serialized: serialize(code),
            mode: .pin,
            salt: salt,
            expiresAt: offer.expiresAt,
            pin: pin,
            secret: nil
        )
    }

    static func createQrSecretChallenge(
        offer: AdPairPayload,
        now: Date = Date(),
        randomBytes: (Int) throws -> Data = { try PairingNonce.random(count: $0) }
    ) throws -> AdPairChallenge {
        try requireLiveOffer(offer, now: now)
        let secret = try randomBytes(32)
        let salt = try randomBytes(32)
        let code = AdPairCode(
            mode: .qrSecret,
            salt: PairingEncoding.base64URLString(salt),
            secret: PairingEncoding.base64URLString(secret),
            offer: offer
        )
        return AdPairChallenge(
            code: code,
            serialized: serialize(code),
            mode: .qrSecret,
            salt: salt,
            expiresAt: offer.expiresAt,
            pin: nil,
            secret: secret
        )
    }

    static func deriveRegistration(
        code: AdPairCode,
        pin: String?,
        initiatorDeviceId: String,
        responderDeviceId: String
    ) throws -> Spake2PlusP256.PasswordRegistration {
        guard !initiatorDeviceId.isEmpty, !responderDeviceId.isEmpty else {
            throw AdPairCodeError.invalidCode
        }
        guard initiatorDeviceId != responderDeviceId else {
            throw AdPairCodeError.invalidCode
        }
        let password: Spake2PlusP256.PasswordInput
        switch code.mode {
        case .pin:
            guard code.secret == nil else {
                throw AdPairCodeError.invalidSecret
            }
            guard let pin, isValidPin(pin) else {
                throw AdPairCodeError.invalidPin
            }
            password = .text(pin)
        case .qrSecret:
            guard let secret = code.secret,
                  let bytes = PairingEncoding.data(base64URL: secret),
                  (minimumSecretBytes...maximumSecretBytes).contains(bytes.count) else {
                throw AdPairCodeError.invalidSecret
            }
            password = .bytes(bytes)
        }
        guard let salt = PairingEncoding.data(base64URL: code.salt) else {
            throw AdPairCodeError.invalidSalt
        }
        return try Spake2PlusP256.createPasswordRegistration(
            password: password,
            salt: salt,
            idProver: Data(initiatorDeviceId.utf8),
            idVerifier: Data(responderDeviceId.utf8)
        )
    }

    private static func validate(
        _ code: AdPairCode,
        options: AdPairCodeParseOptions
    ) throws {
        guard code.protocolName == AdPairCode.protocolName else {
            throw AdPairCodeError.invalidCode
        }
        guard code.version == AdPairCode.version else {
            throw AdPairCodeError.unsupportedCodeVersion
        }
        if let expected = options.expectedMode, code.mode != expected {
            throw AdPairCodeError.invalidMode
        }
        guard let salt = PairingEncoding.data(base64URL: code.salt),
              (minimumSaltBytes...maximumSaltBytes).contains(salt.count) else {
            throw AdPairCodeError.invalidSalt
        }
        do {
            try code.offer.validate(
                expectedKind: .offer,
                now: options.now,
                localDeviceId: options.localDeviceId
            )
        } catch AdPairError.expired {
            throw AdPairCodeError.expiredCode
        }
        guard code.offer.expiresAt > Int64((options.now.timeIntervalSince1970 * 1000).rounded()) else {
            throw AdPairCodeError.expiredCode
        }
        switch code.mode {
        case .pin:
            guard code.secret == nil else {
                throw AdPairCodeError.invalidSecret
            }
        case .qrSecret:
            guard let secret = code.secret,
                  let bytes = PairingEncoding.data(base64URL: secret),
                  (minimumSecretBytes...maximumSecretBytes).contains(bytes.count) else {
                throw AdPairCodeError.invalidSecret
            }
        }
    }

    private static func requireLiveOffer(_ offer: AdPairPayload, now: Date) throws {
        guard offer.kind == .offer else {
            throw AdPairCodeError.invalidCode
        }
        guard offer.expiresAt > Int64((now.timeIntervalSince1970 * 1000).rounded()) else {
            throw AdPairCodeError.expiredCode
        }
    }

    private static func randomPin(
        randomBytes: (Int) throws -> Data
    ) throws -> String {
        let range: UInt64 = 1 << 32
        let limit = range - (range % 1_000_000)
        for _ in 0..<64 {
            let bytes = try randomBytes(4)
            guard bytes.count == 4 else {
                throw AdPairCodeError.invalidPin
            }
            var word: UInt32 = 0
            for byte in bytes {
                word = (word << 8) | UInt32(byte)
            }
            if UInt64(word) < limit {
                return String(format: "%06u", word % 1_000_000)
            }
        }
        throw AdPairCodeError.invalidPin
    }

    private static func isValidPin(_ pin: String) -> Bool {
        pin.count == pinDigits && pin.allSatisfy { ("0"..."9").contains($0) }
    }
}

final class AdPairPinAttemptGuard {
    private struct AttemptState {
        var failures: Int
        var expiresAt: Date
    }

    private let maxAttempts: Int
    private let now: () -> Date
    private let lock = NSLock()
    private var attempts: [String: AttemptState] = [:]

    init(
        maxAttempts: Int = 5,
        now: @escaping () -> Date = Date.init
    ) throws {
        guard maxAttempts > 0 else {
            throw AdPairCodeError.invalidCode
        }
        self.maxAttempts = maxAttempts
        self.now = now
    }

    func assertAllowed(key: String, expiresAt: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        pruneUnlocked()
        guard expiresAt > now() else {
            throw AdPairCodeError.expiredCode
        }
        if let state = attempts[key], state.failures >= maxAttempts {
            throw AdPairCodeError.pinLocked
        }
    }

    @discardableResult
    func recordFailure(key: String, expiresAt: Date) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        pruneUnlocked()
        guard expiresAt > now() else {
            throw AdPairCodeError.expiredCode
        }
        var state = attempts[key] ?? AttemptState(failures: 0, expiresAt: expiresAt)
        if state.failures >= maxAttempts {
            throw AdPairCodeError.pinLocked
        }
        state.failures += 1
        state.expiresAt = max(state.expiresAt, expiresAt)
        attempts[key] = state
        return max(0, maxAttempts - state.failures)
    }

    func recordSuccess(key: String) {
        lock.lock()
        defer { lock.unlock() }
        attempts.removeValue(forKey: key)
    }

    func reset(key: String) {
        recordSuccess(key: key)
    }

    func prune() {
        lock.lock()
        defer { lock.unlock() }
        pruneUnlocked()
    }

    private func pruneUnlocked() {
        let current = now()
        attempts = attempts.filter { $0.value.expiresAt > current }
    }
}
