import XCTest
@testable import AirDesk

final class Spake2PlusP256Tests: XCTestCase {
    private let context = Data("SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256 Test Vectors".utf8)
    private let idProver = Data("client".utf8)
    private let idVerifier = Data("server".utf8)
    private let w0 = "bb8e1bbcf3c48f62c08db243652ae55d3e5586053fca77102994f23ad95491b3"
    private let w1 = "7e945f34d78785b8a3ef44d0df5a1a97d6b3b460409a345ca7830387a74b1dba"
    private let registration = "04eb7c9db3d9a9eb1f8adab81b5794c1f13ae3e225efbe91ea487425854c7fc00f00bfedcbd09b2400142d40a14f2064ef31dfaa903b91d1faea7093d835966efd"
    private let x = "d1232c8e8693d02368976c174e2088851b8365d0d79a9eee709c6a05a2fad539"
    private let shareP = "04ef3bd051bf78a2234ec0df197f7828060fe9856503579bb1733009042c15c0c1de127727f418b5966afadfdd95a6e4591d171056b333dab97a79c7193e341727"
    private let y = "717a72348a182085109c8d3917d6c43d59b224dc6a7fc4f0483232fa6516d8b3"
    private let shareV = "04c0f65da0d11927bdf5d560c69e1d7d939a05b0e88291887d679fcadea75810fb5cc1ca7494db39e82ff2f50665255d76173e09986ab46742c798a9a68437b048"
    private let z = "04bbfce7dd7f277819c8da21544afb7964705569bdf12fb92aa388059408d50091a0c5f1d3127f56813b5337f9e4e67e2ca633117a4fbd559946ab474356c41839"
    private let v = "0458bf27c6bca011c9ce1930e8984a797a3419797b936629a5a937cf2f11c8b9514b82b993da8a46e664f23db7c01edc87faa530db01c2ee405230b18997f16b68"
    private let transcript = "38000000000000005350414b45322b2d503235362d5348413235362d484b44462d5348413235362d484d41432d534841323536205465737420566563746f72730600000000000000636c69656e740600000000000000736572766572410000000000000004886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f5ff355163e43ce224e0b0e65ff02ac8e5c7be09419c785e0ca547d55a12e2d20410000000000000004d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b4907d60aa6bfade45008a636337f5168c64d9bd36034808cd564490b1e656edbe7410000000000000004ef3bd051bf78a2234ec0df197f7828060fe9856503579bb1733009042c15c0c1de127727f418b5966afadfdd95a6e4591d171056b333dab97a79c7193e341727410000000000000004c0f65da0d11927bdf5d560c69e1d7d939a05b0e88291887d679fcadea75810fb5cc1ca7494db39e82ff2f50665255d76173e09986ab46742c798a9a68437b048410000000000000004bbfce7dd7f277819c8da21544afb7964705569bdf12fb92aa388059408d50091a0c5f1d3127f56813b5337f9e4e67e2ca633117a4fbd559946ab474356c4183941000000000000000458bf27c6bca011c9ce1930e8984a797a3419797b936629a5a937cf2f11c8b9514b82b993da8a46e664f23db7c01edc87faa530db01c2ee405230b18997f16b682000000000000000bb8e1bbcf3c48f62c08db243652ae55d3e5586053fca77102994f23ad95491b3"
    private let kMain = "4c59e1ccf2cfb961aa31bd9434478a1089b56cd11542f53d3576fb6c2a438a29"
    private let kConfirmP = "871ae3f7b78445e34438fb284504240239031c39d80ac23eb5ab9be5ad6db58a"
    private let kConfirmV = "ccd53c7c1fa37b64a462b40db8be101cedcf838950162902054e644b400f1680"
    private let confirmP = "926cc713504b9b4d76c9162ded04b5493e89109f6d89462cd33adc46fda27527"
    private let confirmV = "9747bcc4f8fe9f63defee53ac9b07876d907d55047e6ff2def2e7529089d3e68"
    private let kShared = "0c5f8ccd1413423a54f6c1fb26ff01534a87f893779c6e68666d772bfd91f3e7"

    func testRegistrationRecord() throws {
        XCTAssertEqual(
            try Spake2PlusP256.registrationRecord(w1: data(w1)),
            try data(registration)
        )
    }

    func testCanonicalPasswordMaterialMatchesBrowserVector() throws {
        let material = try Spake2PlusP256.canonicalPasswordMaterial(
            password: .text("123456"),
            idProver: Data("client".utf8),
            idVerifier: Data("server".utf8)
        )
        XCTAssertEqual(
            material,
            try data(
                "0600000000000000313233343536" +
                    "0600000000000000636c69656e74" +
                    "0600000000000000736572766572"
            )
        )
    }

    func testPasswordRegistrationMatchesCrossPlatformVector() throws {
        let salt = try data("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        let registration = try Spake2PlusP256.createPasswordRegistration(
            password: .text("correct horse battery staple"),
            salt: salt,
            idProver: Data("client".utf8),
            idVerifier: Data("server".utf8)
        )

        XCTAssertEqual(
            registration.w0,
            try data("b0ed4ba1a99c347e760babddd3847a9bbec14679eff683f533b4b30c6f51d942")
        )
        XCTAssertEqual(
            registration.w1,
            try data("2617ed2ba8d280416fdf1a179ec1a6a103cf1309867dfeb90153bf88c7b26acd")
        )
        XCTAssertEqual(registration.salt, salt)
        XCTAssertEqual(
            registration.L,
            try Spake2PlusP256.registrationRecord(w1: registration.w1)
        )
        XCTAssertEqual(
            registration.profile,
            Spake2PlusP256.PasswordPBKDFProfile(
                name: "scrypt",
                n: 32768,
                r: 8,
                p: 1,
                dkLen: 80
            )
        )
        XCTAssertEqual(Spake2PlusP256.createPasswordSalt().count, 32)
    }

    func testPasswordRegistrationBindsPasswordSaltAndIdentities() throws {
        let salt = try data("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        let baseline = try Spake2PlusP256.derivePasswordScalars(
            password: .text("correct horse battery staple"),
            salt: salt,
            idProver: Data("client".utf8),
            idVerifier: Data("server".utf8)
        )
        let changedPassword = try Spake2PlusP256.derivePasswordScalars(
            password: .text("correct horse battery staple!"),
            salt: salt,
            idProver: Data("client".utf8),
            idVerifier: Data("server".utf8)
        )
        let changedSalt = try Spake2PlusP256.derivePasswordScalars(
            password: .text("correct horse battery staple"),
            salt: Data(repeating: 7, count: 32),
            idProver: Data("client".utf8),
            idVerifier: Data("server".utf8)
        )
        let changedIdentity = try Spake2PlusP256.derivePasswordScalars(
            password: .text("correct horse battery staple"),
            salt: salt,
            idProver: Data("client".utf8),
            idVerifier: Data("server-2".utf8)
        )

        XCTAssertNotEqual(changedPassword.w0, baseline.w0)
        XCTAssertNotEqual(changedSalt.w1, baseline.w1)
        XCTAssertNotEqual(changedIdentity.w0, baseline.w0)
    }

    func testPasswordRegistrationRejectsInvalidInput() {
        let salt = Data(repeating: 0, count: 32)
        XCTAssertThrowsError(
            try Spake2PlusP256.derivePasswordScalars(password: .text(""), salt: salt)
        ) { XCTAssertEqual(($0 as? Spake2PlusP256.Error)?.code, "invalid-input") }
        XCTAssertThrowsError(
            try Spake2PlusP256.derivePasswordScalars(password: .bytes(Data()), salt: salt)
        ) { XCTAssertEqual(($0 as? Spake2PlusP256.Error)?.code, "invalid-input") }
        XCTAssertThrowsError(
            try Spake2PlusP256.derivePasswordScalars(
                password: .text("short"),
                salt: Data(repeating: 0, count: 15)
            )
        ) { XCTAssertEqual(($0 as? Spake2PlusP256.Error)?.code, "invalid-length") }
        XCTAssertThrowsError(
            try Spake2PlusP256.derivePasswordScalars(
                password: .text("short"),
                salt: Data(repeating: 0, count: 65)
            )
        ) { XCTAssertEqual(($0 as? Spake2PlusP256.Error)?.code, "invalid-length") }
    }

    func testPasswordRegistrationDrivesInteractiveSession() throws {
        let registration = try Spake2PlusP256.createPasswordRegistration(
            password: .text("123456"),
            salt: Data(repeating: 9, count: 32),
            idProver: idProver,
            idVerifier: idVerifier
        )
        let prover = Spake2PlusP256Session(
            role: .prover,
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
            w0: registration.w0,
            w1: registration.w1
        )
        let verifier = Spake2PlusP256Session(
            role: .verifier,
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
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

    func testProverInit() throws {
        let start = try Spake2PlusP256.proverInit(w0: data(w0), x: data(x))
        XCTAssertEqual(start.shareP, try data(shareP))
    }

    func testReproducesRFC9383Vector() throws {
        let prover = try Spake2PlusP256.proverFinish(
            w0: data(w0),
            w1: data(w1),
            x: data(x),
            shareV: data(shareV),
            context: context,
            idProver: idProver,
            idVerifier: idVerifier
        )
        let verifier = try Spake2PlusP256.verifierFinish(
            w0: data(w0),
            L: data(registration),
            shareP: data(shareP),
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
            y: data(y)
        ).finish

        XCTAssertEqual(prover.shareP, try data(shareP))
        XCTAssertEqual(prover.shareV, try data(shareV))
        XCTAssertEqual(prover.z, try data(z))
        XCTAssertEqual(prover.v, try data(v))
        XCTAssertEqual(prover.transcript, try data(transcript))
        XCTAssertEqual(verifier.transcript, prover.transcript)
        XCTAssertEqual(prover.keys.kMain, try data(kMain))
        XCTAssertEqual(prover.keys.kConfirmP, try data(kConfirmP))
        XCTAssertEqual(prover.keys.kConfirmV, try data(kConfirmV))
        XCTAssertEqual(prover.keys.kShared, try data(kShared))
        XCTAssertEqual(prover.confirmation, try data(confirmP))
        XCTAssertEqual(prover.expectedConfirmation, try data(confirmV))
        XCTAssertEqual(verifier.confirmation, try data(confirmV))
        XCTAssertEqual(verifier.expectedConfirmation, try data(confirmP))
    }

    func testSessionAcceptsMatchingConfirmations() throws {
        let prover = Spake2PlusP256Session(
            role: .prover,
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
            w0: try data(w0),
            w1: try data(w1),
            x: try data(x)
        )
        let verifier = Spake2PlusP256Session(
            role: .verifier,
            context: context,
            idProver: idProver,
            idVerifier: idVerifier,
            w0: try data(w0),
            L: try data(registration),
            y: try data(y)
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
        XCTAssertEqual(proverResult.keys.kShared, try data(kShared))
    }

    func testRejectsTamperedConfirmationAndInvalidPoints() throws {
        let prover = try Spake2PlusP256.proverFinish(
            w0: data(w0),
            w1: data(w1),
            x: data(x),
            shareV: data(shareV),
            context: context,
            idProver: idProver,
            idVerifier: idVerifier
        )
        var tampered = try data(confirmV)
        tampered[0] ^= 1
        XCTAssertThrowsError(
            try Spake2PlusP256.assertConfirmation(
                expected: prover.expectedConfirmation,
                received: tampered
            )
        ) { XCTAssertEqual(($0 as? Spake2PlusP256.Error)?.code, "confirmation-mismatch") }

        var offCurve = Data(repeating: 0, count: 65)
        offCurve[0] = 0x04
        XCTAssertThrowsError(
            try Spake2PlusP256.proverFinish(
                w0: data(w0),
                w1: data(w1),
                x: data(x),
                shareV: offCurve,
                context: context,
                idProver: idProver,
                idVerifier: idVerifier
            )
        ) { XCTAssertEqual(($0 as? Spake2PlusP256.Error)?.code, "invalid-point") }
    }

    private func data(_ hex: String) throws -> Data {
        guard hex.count.isMultiple(of: 2) else {
            throw Spake2PlusP256.Error.invalidLength("test vector is malformed")
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw Spake2PlusP256.Error.invalidLength("test vector is malformed")
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
