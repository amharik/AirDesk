import Foundation

struct BridgeMessage: Codable, Equatable, Sendable {
    var version: Int
    var type: String
    var sessionId: String?
    var seq: Int?
    var timestamp: Double?
    var runtime: String?
    var level: String?
    var message: String?
    var width: Double?
    var height: Double?
    var code: String?
    var action: String?

    static let allowedTypes: Set<String> = [
        "ready", "ack", "log", "state", "error", "viewport", "action", "notice"
    ]

    func validated() throws -> BridgeMessage {
        guard version == 1 else { throw BridgeError.unsupportedVersion }
        guard Self.allowedTypes.contains(type) else { throw BridgeError.unsupportedType }
        if let sessionId, sessionId.count > 64 { throw BridgeError.invalidSession }
        if let seq, seq < 0 { throw BridgeError.invalidSequence }
        if let message, message.count > 4000 { throw BridgeError.messageTooLarge }
        if let runtime, runtime.count > 64 { throw BridgeError.invalidField }
        if let level, !["debug", "info", "warn", "error"].contains(level) {
            throw BridgeError.invalidField
        }
        if let width, !width.isFinite { throw BridgeError.invalidField }
        if let height, !height.isFinite { throw BridgeError.invalidField }
        if let width, width < 0 || width > 20_000 { throw BridgeError.invalidField }
        if let height, height < 0 || height > 20_000 { throw BridgeError.invalidField }
        if let action, action.count > 128 { throw BridgeError.invalidField }
        if let code, code.count > 128 { throw BridgeError.invalidField }
        return self
    }
}

enum BridgeError: LocalizedError, Equatable {
    case unsupportedVersion
    case unsupportedType
    case invalidSession
    case invalidSequence
    case messageTooLarge
    case invalidField
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Unsupported bridge protocol version."
        case .unsupportedType: return "Unsupported bridge message type."
        case .invalidSession: return "Invalid bridge session."
        case .invalidSequence: return "Invalid bridge sequence."
        case .messageTooLarge: return "Bridge message exceeded the size limit."
        case .invalidField: return "Invalid bridge field."
        case .malformedPayload: return "Malformed bridge payload."
        }
    }
}
