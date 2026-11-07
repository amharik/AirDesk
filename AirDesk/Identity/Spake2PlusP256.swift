import CryptoKit
import Foundation
import OpenSSL

enum Spake2PlusP256 {
    static let suite = "SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256"
    static let mCompressedHex = "02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f"
    static let nCompressedHex = "03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49"
    static let scalarBytes = 32
    static let confirmationBytes = 32
    static let passwordSaltBytes = 32
    static let passwordPBKDFProfile = PasswordPBKDFProfile(
        name: "scrypt",
        n: 32768,
        r: 8,
        p: 1,
        dkLen: 80
    )

    struct Keys: Equatable {
        let kMain: Data
        let kConfirmP: Data
        let kConfirmV: Data
        let kShared: Data
    }

    struct PasswordPBKDFProfile: Equatable {
        let name: String
        let n: Int
        let r: Int
        let p: Int
        let dkLen: Int
    }

    enum PasswordInput: Equatable {
        case text(String)
        case bytes(Data)
    }

    struct PasswordScalars: Equatable {
        let w0: Data
        let w1: Data
    }

    struct PasswordRegistration: Equatable {
        let w0: Data
        let w1: Data
        let salt: Data
        let L: Data
        let profile: PasswordPBKDFProfile
    }

    struct ProverInit: Equatable {
        let x: Data
        let shareP: Data
    }

    struct Finish: Equatable {
        let shareP: Data
        let shareV: Data
        let z: Data
        let v: Data
        let transcript: Data
        let keys: Keys
        let confirmation: Data
        let expectedConfirmation: Data
    }

    struct VerifierFinish: Equatable {
        let y: Data
        let finish: Finish
    }

    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidInput(String)
        case invalidLength(String)
        case invalidPoint(String)
        case identityPoint(String)
        case nonSubgroupPoint(String)
        case invalidScalar(String)
        case confirmationMismatch
        case invalidState(String)

        var code: String {
            switch self {
            case .invalidInput: return "invalid-input"
            case .invalidLength: return "invalid-length"
            case .invalidPoint: return "invalid-point"
            case .identityPoint: return "identity-point"
            case .nonSubgroupPoint: return "non-subgroup-point"
            case .invalidScalar: return "invalid-scalar"
            case .confirmationMismatch: return "confirmation-mismatch"
            case .invalidState: return "invalid-state"
            }
        }

        var errorDescription: String? {
            switch self {
            case .invalidInput(let detail): return "InvalidInput: \(detail)"
            case .invalidLength(let detail): return "InvalidLength: \(detail)"
            case .invalidPoint(let detail): return "InvalidPoint: \(detail)"
            case .identityPoint(let detail): return "IdentityPoint: \(detail)"
            case .nonSubgroupPoint(let detail): return "NonSubgroupPoint: \(detail)"
            case .invalidScalar(let detail): return "InvalidScalar: \(detail)"
            case .confirmationMismatch: return "ConfirmationMismatch: confirmation mismatch."
            case .invalidState(let detail): return "InvalidState: \(detail)"
            }
        }
    }

    static func canonicalPasswordMaterial(
        password: PasswordInput,
        idProver: Data = Data(),
        idVerifier: Data = Data()
    ) throws -> Data {
        lengthPrefixed(try canonicalPasswordBytes(password))
            + lengthPrefixed(idProver)
            + lengthPrefixed(idVerifier)
    }

    static func createPasswordSalt() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    static func derivePasswordScalars(
        password: PasswordInput,
        salt: Data,
        idProver: Data = Data(),
        idVerifier: Data = Data()
    ) throws -> PasswordScalars {
        guard (16...64).contains(salt.count) else {
            throw Error.invalidLength("salt must be 16 to 64 bytes")
        }
        let material = try canonicalPasswordMaterial(
            password: password,
            idProver: idProver,
            idVerifier: idVerifier
        )
        let output = try scryptPasswordMaterial(material, salt: salt)
        let half = passwordPBKDFProfile.dkLen / 2
        let group = try NativeP256Group()
        let w0 = try group.reduceWideScalar(Data(output.prefix(half)))
        let w1 = try group.reduceWideScalar(Data(output.suffix(half)))
        guard w1.contains(where: { $0 != 0 }) else {
            throw Error.invalidScalar("derived w1 must not be zero")
        }
        return PasswordScalars(w0: w0, w1: w1)
    }

    static func createPasswordRegistration(
        password: PasswordInput,
        salt: Data? = nil,
        idProver: Data = Data(),
        idVerifier: Data = Data()
    ) throws -> PasswordRegistration {
        let salt = salt ?? createPasswordSalt()
        let scalars = try derivePasswordScalars(
            password: password,
            salt: salt,
            idProver: idProver,
            idVerifier: idVerifier
        )
        return PasswordRegistration(
            w0: scalars.w0,
            w1: scalars.w1,
            salt: salt,
            L: try registrationRecord(w1: scalars.w1),
            profile: passwordPBKDFProfile
        )
    }

    static func registrationRecord(w1: Data) throws -> Data {
        let group = try NativeP256Group()
        let generator = try group.generator()
        return try group.encode(group.multiply(generator, by: w1))
    }

    static func proverInit(w0: Data, x: Data? = nil) throws -> ProverInit {
        let group = try NativeP256Group()
        let generator = try group.generator()
        _ = try group.multiply(generator, by: w0, allowZero: true)
        let x = try x ?? randomScalar()
        _ = try group.multiply(generator, by: x)
        let m = try group.decode(try hexData(mCompressedHex), requireUncompressed: false)
        let shareP = try group.linearCombination(
            generatorScalar: x,
            point: m,
            pointScalar: w0
        )
        return ProverInit(x: x, shareP: try group.encode(shareP))
    }

    static func proverFinish(
        w0: Data,
        w1: Data,
        x: Data,
        shareV: Data,
        context: Data,
        idProver: Data,
        idVerifier: Data
    ) throws -> Finish {
        let group = try NativeP256Group()
        let generator = try group.generator()
        _ = try group.multiply(generator, by: w0, allowZero: true)
        _ = try group.multiply(generator, by: w1)
        _ = try group.multiply(generator, by: x)

        let m = try group.decode(try hexData(mCompressedHex), requireUncompressed: false)
        let n = try group.decode(try hexData(nCompressedHex), requireUncompressed: false)
        let shareVPoint = try decodePoint(group, shareV)
        let sharePPoint = try group.linearCombination(
            generatorScalar: x,
            point: m,
            pointScalar: w0
        )
        let unblindedShareV = try group.subtract(
            shareVPoint,
            group.multiply(n, by: w0, allowZero: true)
        )
        guard !group.isInfinity(unblindedShareV) else {
            throw Error.identityPoint("shareV unblinds to the identity point")
        }
        let zPoint = try group.multiply(unblindedShareV, by: x)
        let vPoint = try group.multiply(unblindedShareV, by: w1)
        return try finish(
            group: group,
            shareP: sharePPoint,
            shareV: shareVPoint,
            z: zPoint,
            v: vPoint,
            w0: w0,
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
            proverRole: true
        )
    }

    static func verifierFinish(
        w0: Data,
        L: Data,
        shareP: Data,
        context: Data,
        idProver: Data,
        idVerifier: Data,
        y: Data? = nil
    ) throws -> VerifierFinish {
        let group = try NativeP256Group()
        let generator = try group.generator()
        _ = try group.multiply(generator, by: w0, allowZero: true)
        let y = try y ?? randomScalar()
        _ = try group.multiply(generator, by: y)

        let LPoint = try decodePoint(group, L)
        let sharePPoint = try decodePoint(group, shareP)
        let m = try group.decode(try hexData(mCompressedHex), requireUncompressed: false)
        let n = try group.decode(try hexData(nCompressedHex), requireUncompressed: false)
        let shareVPoint = try group.linearCombination(
            generatorScalar: y,
            point: n,
            pointScalar: w0
        )
        let unblindedShareP = try group.subtract(
            sharePPoint,
            group.multiply(m, by: w0, allowZero: true)
        )
        guard !group.isInfinity(unblindedShareP) else {
            throw Error.identityPoint("shareP unblinds to the identity point")
        }
        let zPoint = try group.multiply(unblindedShareP, by: y)
        let vPoint = try group.multiply(LPoint, by: y)
        let finish = try finish(
            group: group,
            shareP: sharePPoint,
            shareV: shareVPoint,
            z: zPoint,
            v: vPoint,
            w0: w0,
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
            proverRole: false
        )
        return VerifierFinish(y: y, finish: finish)
    }

    static func transcript(
        context: Data,
        idProver: Data,
        idVerifier: Data,
        shareP: Data,
        shareV: Data,
        z: Data,
        v: Data,
        w0: Data
    ) throws -> Data {
        let group = try NativeP256Group()
        let m = try group.decode(try hexData(mCompressedHex), requireUncompressed: false)
        let n = try group.decode(try hexData(nCompressedHex), requireUncompressed: false)
        guard w0.count == scalarBytes else {
            throw Error.invalidLength("w0 must be 32 bytes")
        }
        var result = Data()
        result.append(lengthPrefixed(context))
        result.append(lengthPrefixed(idProver))
        result.append(lengthPrefixed(idVerifier))
        result.append(lengthPrefixed(try group.encode(m)))
        result.append(lengthPrefixed(try group.encode(n)))
        result.append(lengthPrefixed(try group.encode(decodePoint(group, shareP))))
        result.append(lengthPrefixed(try group.encode(decodePoint(group, shareV))))
        result.append(lengthPrefixed(try group.encode(decodePoint(group, z))))
        result.append(lengthPrefixed(try group.encode(decodePoint(group, v))))
        result.append(lengthPrefixed(w0))
        return result
    }

    static func deriveKeys(transcript: Data) -> Keys {
        let kMain = Data(SHA256.hash(data: transcript))
        let material = SymmetricKey(data: kMain)
        let confirmation = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: Data(),
            info: Data("ConfirmationKeys".utf8),
            outputByteCount: confirmationBytes * 2
        )
        let confirmationData = confirmation.withUnsafeBytes { Data($0) }
        let kShared = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: Data(),
            info: Data("SharedKey".utf8),
            outputByteCount: 32
        )
        return Keys(
            kMain: kMain,
            kConfirmP: Data(confirmationData.prefix(confirmationBytes)),
            kConfirmV: Data(confirmationData.suffix(confirmationBytes)),
            kShared: kShared.withUnsafeBytes { Data($0) }
        )
    }

    static func confirmations(keys: Keys, shareP: Data, shareV: Data) throws -> (prover: Data, verifier: Data) {
        let group = try NativeP256Group()
        let shareP = try group.encode(decodePoint(group, shareP))
        let shareV = try group.encode(decodePoint(group, shareV))
        return (
            hmac(key: keys.kConfirmP, message: shareV),
            hmac(key: keys.kConfirmV, message: shareP)
        )
    }

    static func assertConfirmation(expected: Data, received: Data) throws {
        guard expected.count == confirmationBytes, received.count == confirmationBytes else {
            throw Error.invalidLength("confirmation must be 32 bytes")
        }
        guard constantTimeEqual(expected, received) else {
            throw Error.confirmationMismatch
        }
    }

    private static func finish(
        group: NativeP256Group,
        shareP: NativeP256Point,
        shareV: NativeP256Point,
        z: NativeP256Point,
        v: NativeP256Point,
        w0: Data,
        context: Data,
        idProver: Data,
        idVerifier: Data,
        proverRole: Bool
    ) throws -> Finish {
        let sharePData = try group.encode(shareP)
        let shareVData = try group.encode(shareV)
        let zData = try group.encode(z)
        let vData = try group.encode(v)
        let transcript = try transcript(
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
            shareP: sharePData,
            shareV: shareVData,
            z: zData,
            v: vData,
            w0: w0
        )
        let keys = deriveKeys(transcript: transcript)
        let confirmation = try confirmations(keys: keys, shareP: sharePData, shareV: shareVData)
        return Finish(
            shareP: sharePData,
            shareV: shareVData,
            z: zData,
            v: vData,
            transcript: transcript,
            keys: keys,
            confirmation: proverRole ? confirmation.prover : confirmation.verifier,
            expectedConfirmation: proverRole ? confirmation.verifier : confirmation.prover
        )
    }

    private static func decodePoint(_ group: NativeP256Group, _ data: Data) throws -> NativeP256Point {
        do {
            return try group.decode(data)
        } catch NativeP256Error.identityPoint(let detail) {
            throw Error.identityPoint(detail)
        } catch NativeP256Error.invalidPoint(let detail) {
            throw Error.invalidPoint(detail)
        } catch NativeP256Error.invalidLength(let detail) {
            throw Error.invalidLength(detail)
        } catch NativeP256Error.invalidScalar(let detail) {
            throw Error.invalidScalar(detail)
        } catch {
            throw Error.invalidPoint("could not decode P-256 point")
        }
    }

    private static func randomScalar() throws -> Data {
        let group = try NativeP256Group()
        let generator = try group.generator()
        for _ in 0..<64 {
            let candidate = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            if (try? group.multiply(generator, by: candidate)) != nil {
                return candidate
            }
        }
        throw Error.invalidScalar("could not generate an ephemeral scalar")
    }

    private static func hmac(key: Data, message: Data) -> Data {
        let authentication = HMAC<SHA256>.authenticationCode(
            for: message,
            using: SymmetricKey(data: key)
        )
        return Data(authentication)
    }

    private static func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(left, right) {
            difference |= a ^ b
        }
        return difference == 0
    }

    private static func lengthPrefixed(_ value: Data) -> Data {
        var length = UInt64(value.count).littleEndian
        let prefix = withUnsafeBytes(of: &length) { Data($0) }
        return prefix + value
    }

    private static func canonicalPasswordBytes(_ password: PasswordInput) throws -> Data {
        switch password {
        case .text(let value):
            let normalized = value.precomposedStringWithCompatibilityMapping
            guard !normalized.isEmpty else {
                throw Error.invalidInput("password must not be empty")
            }
            return Data(normalized.utf8)
        case .bytes(let value):
            guard !value.isEmpty else {
                throw Error.invalidInput("password must not be empty")
            }
            return value
        }
    }

    private static func scryptPasswordMaterial(_ material: Data, salt: Data) throws -> Data {
        let profile = passwordPBKDFProfile
        var output = [UInt8](repeating: 0, count: profile.dkLen)
        let result = material.withUnsafeBytes { materialBytes in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBufferPointer { outputBytes in
                    EVP_PBE_scrypt(
                        materialBytes.bindMemory(to: CChar.self).baseAddress,
                        materialBytes.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltBytes.count,
                        UInt64(profile.n),
                        UInt64(profile.r),
                        UInt64(profile.p),
                        64 * 1024 * 1024,
                        outputBytes.baseAddress,
                        outputBytes.count
                    )
                }
            }
        }
        guard result == 1 else {
            throw Error.invalidInput("could not derive password scalars")
        }
        return Data(output)
    }

    private static func hexData(_ hex: String) throws -> Data {
        guard hex.count.isMultiple(of: 2) else {
            throw Error.invalidLength("point hex is malformed")
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw Error.invalidLength("point hex is malformed")
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}

final class Spake2PlusP256Session {
    enum Role {
        case prover
        case verifier
    }

    struct Result {
        let transcript: Data
        let keys: Spake2PlusP256.Keys
        let confirmation: Data
        let expectedConfirmation: Data
    }

    enum Phase {
        case initial
        case awaitingShare
        case awaitingConfirmation
        case completed
    }

    let role: Role
    private let context: Data
    private let idProver: Data
    private let idVerifier: Data
    private let w0: Data
    private let w1: Data?
    private let L: Data?
    private let x: Data?
    private let y: Data?
    private var phase: Phase = .initial
    private var proverInit: Spake2PlusP256.ProverInit?
    private var verifierPending: Spake2PlusP256.VerifierFinish?

    init(
        role: Role,
        context: Data,
        idProver: Data,
        idVerifier: Data,
        w0: Data,
        w1: Data? = nil,
        L: Data? = nil,
        x: Data? = nil,
        y: Data? = nil
    ) {
        self.role = role
        self.context = context
        self.idProver = idProver
        self.idVerifier = idVerifier
        self.w0 = w0
        self.w1 = w1
        self.L = L
        self.x = x
        self.y = y
    }

    func proverStart() throws -> Data {
        guard role == .prover else {
            throw Spake2PlusP256.Error.invalidState("only the prover starts the exchange")
        }
        guard phase == .initial else {
            throw Spake2PlusP256.Error.invalidState("prover exchange already started")
        }
        let start = try Spake2PlusP256.proverInit(w0: w0, x: x)
        proverInit = start
        phase = .awaitingShare
        return start.shareP
    }

    func verifierRespond(shareP: Data) throws -> (share: Data, confirmation: Data) {
        guard role == .verifier else {
            throw Spake2PlusP256.Error.invalidState("only the verifier responds to a prover share")
        }
        guard phase == .initial else {
            throw Spake2PlusP256.Error.invalidState("verifier response already produced")
        }
        guard let L else {
            throw Spake2PlusP256.Error.invalidInput("verifier registration record L is required")
        }
        let result = try Spake2PlusP256.verifierFinish(
            w0: w0,
            L: L,
            shareP: shareP,
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
            y: y
        )
        verifierPending = result
        phase = .awaitingConfirmation
        return (result.finish.shareV, result.finish.confirmation)
    }

    func proverFinish(shareV: Data, confirmationV: Data) throws -> Result {
        guard role == .prover else {
            throw Spake2PlusP256.Error.invalidState("only the prover finishes with a verifier response")
        }
        guard phase == .awaitingShare, let proverInit else {
            throw Spake2PlusP256.Error.invalidState("prover is not awaiting a verifier share")
        }
        guard let w1 else {
            throw Spake2PlusP256.Error.invalidInput("prover witness w1 is required")
        }
        let finish = try Spake2PlusP256.proverFinish(
            w0: w0,
            w1: w1,
            x: proverInit.x,
            shareV: shareV,
            context: context,
            idProver: idProver,
            idVerifier: idVerifier
        )
        try Spake2PlusP256.assertConfirmation(
            expected: finish.expectedConfirmation,
            received: confirmationV
        )
        phase = .completed
        return Result(
            transcript: finish.transcript,
            keys: finish.keys,
            confirmation: finish.confirmation,
            expectedConfirmation: finish.expectedConfirmation
        )
    }

    func verifierFinish(confirmationP: Data) throws -> Result {
        guard role == .verifier else {
            throw Spake2PlusP256.Error.invalidState("only the verifier finishes with a prover confirmation")
        }
        guard phase == .awaitingConfirmation, let verifierPending else {
            throw Spake2PlusP256.Error.invalidState("verifier is not awaiting a prover confirmation")
        }
        try Spake2PlusP256.assertConfirmation(
            expected: verifierPending.finish.expectedConfirmation,
            received: confirmationP
        )
        phase = .completed
        return Result(
            transcript: verifierPending.finish.transcript,
            keys: verifierPending.finish.keys,
            confirmation: verifierPending.finish.expectedConfirmation,
            expectedConfirmation: verifierPending.finish.confirmation
        )
    }
}
