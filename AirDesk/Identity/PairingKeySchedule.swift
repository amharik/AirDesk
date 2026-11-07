import CryptoKit
import Foundation

enum PairingKeySchedule {
    static let version = 1
    static let domain = "AD-PAIR-1-KS"
    static let keyBytes = 32

    enum Purpose: String, CaseIterable {
        case initiatorToResponder = "i2r"
        case responderToInitiator = "r2i"
        case transport
    }

    struct Key: Equatable {
        let purpose: Purpose
        let bytes: Data
    }

    struct Keys: Equatable {
        let initiatorToResponder: Key
        let responderToInitiator: Key
        let transport: Key
    }

    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidSharedSecretLength
        case invalidTranscriptHashLength
        case invalidChannelBinding

        var errorDescription: String? {
            switch self {
            case .invalidSharedSecretLength:
                return "PAKE shared secret length out of range."
            case .invalidTranscriptHashLength:
                return "AD-PAIR-1 transcript hash must be 32 bytes."
            case .invalidChannelBinding:
                return "AD-PAIR-1 requires a non-empty channel binding."
            }
        }
    }

    static func derive(
        pakeSharedSecret: Data,
        transcriptHash: Data,
        channelBinding: PairingChannelBinding
    ) throws -> Keys {
        guard (16...1024).contains(pakeSharedSecret.count) else {
            throw Error.invalidSharedSecretLength
        }
        guard transcriptHash.count == 32 else {
            throw Error.invalidTranscriptHashLength
        }
        guard !channelBinding.value.isEmpty else {
            throw Error.invalidChannelBinding
        }

        let material = SymmetricKey(data: pakeSharedSecret)
        let transcriptHex = hexString(transcriptHash)
        let bindingKind = keyScheduleName(for: channelBinding.kind)
        var derived: [Purpose: Key] = [:]
        for purpose in Purpose.allCases {
            let key = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: material,
                salt: transcriptHash,
                info: keyInfo(
                    label: purpose.rawValue,
                    bindingKind: bindingKind,
                    bindingValue: channelBinding.value,
                    transcriptHex: transcriptHex
                ),
                outputByteCount: keyBytes
            )
            derived[purpose] = Key(
                purpose: purpose,
                bytes: key.withUnsafeBytes { Data($0) }
            )
        }

        guard let initiatorToResponder = derived[.initiatorToResponder],
              let responderToInitiator = derived[.responderToInitiator],
              let transport = derived[.transport] else {
            throw Error.invalidChannelBinding
        }
        return Keys(
            initiatorToResponder: initiatorToResponder,
            responderToInitiator: responderToInitiator,
            transport: transport
        )
    }

    private static func keyScheduleName(for kind: PairingChannelBindingKind) -> String {
        switch kind {
        case .tlsExporter:
            return "exporter"
        case .certificateSHA256:
            return "certificate-hash"
        }
    }

    private static func keyInfo(
        label: String,
        bindingKind: String,
        bindingValue: String,
        transcriptHex: String
    ) -> Data {
        let json = """
        {"domain":"\(domain)","version":\(version),"label":"\(jsonEscape(label))","channelBinding":{"kind":"\(jsonEscape(bindingKind))","value":"\(jsonEscape(bindingValue))"},"transcriptHash":"\(transcriptHex)"}
        """
        return Data(json.utf8)
    }

    private static func jsonEscape(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if scalar.value < 0x20 {
                    escaped += String(format: "\\u%04x", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
