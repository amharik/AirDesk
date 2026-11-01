import Foundation
import OSLog
import WebKit

struct TerminalBridgeMessage: Codable, Equatable, Sendable {
    var version: Int
    var sessionId: String?
    var action: String
    var data: String?
    var columns: Int?
    var rows: Int?

    static let allowedActions: Set<String> = ["start", "write", "resize", "stop"]
    static let maximumDataLength = 131_072

    func validated() throws -> TerminalBridgeMessage {
        guard version == 1 else { throw TerminalBridgeError.unsupportedVersion }
        guard Self.allowedActions.contains(action) else { throw TerminalBridgeError.unsupportedAction }
        if let sessionId, sessionId.count > 64 { throw TerminalBridgeError.invalidSession }

        switch action {
        case "write":
            guard let data, !data.isEmpty else { throw TerminalBridgeError.invalidField }
            guard data.count <= Self.maximumDataLength else { throw TerminalBridgeError.payloadTooLarge }
            guard Data(base64Encoded: data) != nil else { throw TerminalBridgeError.invalidField }
        case "resize":
            guard let columns, (1...1_000).contains(columns) else { throw TerminalBridgeError.invalidField }
            guard let rows, (1...1_000).contains(rows) else { throw TerminalBridgeError.invalidField }
        default:
            break
        }

        return self
    }
}

enum TerminalBridgeError: LocalizedError, Equatable {
    case unsupportedVersion
    case unsupportedAction
    case invalidSession
    case invalidField
    case payloadTooLarge
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Unsupported terminal bridge version."
        case .unsupportedAction: return "Unsupported terminal bridge action."
        case .invalidSession: return "Invalid terminal bridge session."
        case .invalidField: return "Invalid terminal bridge field."
        case .payloadTooLarge: return "Terminal input exceeded the size limit."
        case .malformedPayload: return "Malformed terminal bridge payload."
        }
    }
}

@MainActor
final class TerminalBridge: NSObject, WKScriptMessageHandler {
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "TerminalBridge")
    var sessionId = ""
    var onMessage: ((TerminalBridgeMessage) -> Void)?
    var onDecodeFailure: ((Error) -> Void)?

    static let handlerName = "airdeskTerminal"

    func receive(_ body: Any) {
        do {
            let data: Data
            if let dictionary = body as? [String: Any] {
                data = try JSONSerialization.data(withJSONObject: dictionary)
            } else if let string = body as? String {
                data = Data(string.utf8)
            } else {
                throw TerminalBridgeError.malformedPayload
            }

            let decoded = try JSONDecoder().decode(TerminalBridgeMessage.self, from: data)
            let message = try decoded.validated()
            if let messageSession = message.sessionId, !sessionId.isEmpty, messageSession != sessionId {
                throw TerminalBridgeError.invalidSession
            }
            onMessage?(message)
        } catch {
            logger.error("Rejected terminal message: \(String(describing: error), privacy: .public)")
            onDecodeFailure?(error)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName else { return }
        receive(message.body)
    }
}
