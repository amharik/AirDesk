import CryptoKit
import XCTest
@testable import AirDesk

final class PairingKeyScheduleTests: XCTestCase {
    private let binding = PairingChannelBinding(
        kind: .certificateSHA256,
        value: String(repeating: "ab", count: 32)
    )
    private let transcriptHashHex = "b11a14c0c9b48e68bf8a5f63844ad252b4965aca7fd7e34307528506325a946d"

    func testMatchesBrowserSessionKeyFixture() throws {
        let keys = try PairingKeySchedule.derive(
            pakeSharedSecret: Data(repeating: 0x0b, count: 32),
            transcriptHash: try XCTUnwrap(PairingEncoding.data(hex: transcriptHashHex)),
            channelBinding: binding
        )

        XCTAssertEqual(
            PairingEncoding.hexString(keys.initiatorToResponder.bytes),
            "a0885c05c54fe82f5dc06913e8431765aa514be7782c7217f9e512cf78f559c6"
        )
        XCTAssertEqual(
            PairingEncoding.hexString(keys.responderToInitiator.bytes),
            "13a3ca8258829d32d6f564ae05ca40e9c619d007a31e4f9b8239743c29deaed0"
        )
        XCTAssertEqual(
            PairingEncoding.hexString(keys.transport.bytes),
            "4f355ecc94dc6560a67e159ff092ec71917e7ba0cfdc82916789761edc8220d6"
        )
    }

    func testDerivesWorkspaceSyncKeyFromPairingTransport() throws {
        let keys = try PairingKeySchedule.derive(
            pakeSharedSecret: Data(repeating: 0x0b, count: 32),
            transcriptHash: try XCTUnwrap(PairingEncoding.data(hex: transcriptHashHex)),
            channelBinding: binding
        )
        let key = try WorkspaceSyncCrypto.deriveKey(
            secret: keys.transport.bytes,
            workspaceId: "ws-1"
        )

        XCTAssertEqual(
            PairingEncoding.hexString(key.withUnsafeBytes { Data($0) }),
            "23f0e90a547805a5eeb5addbd546d832a2d2154e47ae99a4d56f2baaf1618271"
        )
    }

    func testBindsKeysToSecretTranscriptAndChannelBinding() throws {
        let transcript = try XCTUnwrap(PairingEncoding.data(hex: transcriptHashHex))
        let changedBinding = try PairingKeySchedule.derive(
            pakeSharedSecret: Data(repeating: 0x0b, count: 32),
            transcriptHash: transcript,
            channelBinding: PairingChannelBinding(
                kind: .certificateSHA256,
                value: String(repeating: "cd", count: 32)
            )
        )
        let changedSecret = try PairingKeySchedule.derive(
            pakeSharedSecret: Data(repeating: 0x0c, count: 32),
            transcriptHash: transcript,
            channelBinding: binding
        )
        let changedTranscript = try PairingKeySchedule.derive(
            pakeSharedSecret: Data(repeating: 0x0b, count: 32),
            transcriptHash: Data(repeating: 0x0d, count: 32),
            channelBinding: binding
        )

        XCTAssertNotEqual(changedBinding.transport, changedSecret.transport)
        XCTAssertNotEqual(changedBinding.transport, changedTranscript.transport)
        XCTAssertNotEqual(changedSecret.transport, changedTranscript.transport)
    }

    func testRejectsInvalidInputs() throws {
        let transcript = try XCTUnwrap(PairingEncoding.data(hex: transcriptHashHex))
        XCTAssertThrowsError(try PairingKeySchedule.derive(
            pakeSharedSecret: Data(repeating: 0x0b, count: 15),
            transcriptHash: transcript,
            channelBinding: binding
        )) { XCTAssertEqual($0 as? PairingKeySchedule.Error, .invalidSharedSecretLength) }

        XCTAssertThrowsError(try PairingKeySchedule.derive(
            pakeSharedSecret: Data(repeating: 0x0b, count: 32),
            transcriptHash: Data(repeating: 0, count: 31),
            channelBinding: binding
        )) { XCTAssertEqual($0 as? PairingKeySchedule.Error, .invalidTranscriptHashLength) }

        XCTAssertThrowsError(try PairingKeySchedule.derive(
            pakeSharedSecret: Data(repeating: 0x0b, count: 32),
            transcriptHash: transcript,
            channelBinding: PairingChannelBinding(kind: .tlsExporter, value: "")
        )) { XCTAssertEqual($0 as? PairingKeySchedule.Error, .invalidChannelBinding) }
    }
}
