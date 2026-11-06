import CoreFoundation
import Foundation

enum BrowserEndpointWireErrorCode: String, Equatable, Sendable {
    case unsupportedTransport = "unsupported-transport"
    case invalidLoopbackURL = "invalid-loopback-url"
    case invalidPort = "invalid-port"
    case invalidOrigin = "invalid-origin"
    case invalidToken = "invalid-token"
    case invalidState = "invalid-state"
    case transportFailure = "transport-failure"
    case handshakeRejected = "handshake-rejected"
    case protocolError = "protocol-error"
    case workspaceMismatch = "workspace-mismatch"
    case displaySessionMismatch = "display-session-mismatch"
    case connectionClosed = "connection-closed"
    case remoteAssetRejected = "remote-asset-rejected"
}

struct BrowserEndpointViewport: Equatable, Sendable {
    let width: Double
    let height: Double
}

struct BrowserEndpointDisplayState: Equatable, Sendable {
    let workspaceId: String
    let displaySessionId: String
    let viewport: BrowserEndpointViewport
    let focusTarget: String?
    let generation: Int
}

enum BrowserEndpointMessageKind: String, Equatable, Sendable {
    case register = "display.register"
    case viewport = "display.viewport"
    case focus = "display.focus"
}

struct BrowserEndpointMessage: Equatable, Sendable {
    let kind: BrowserEndpointMessageKind
    let state: BrowserEndpointDisplayState
}

enum BrowserEndpointMessageError: LocalizedError, Equatable {
    case malformed
    case unsupportedType
    case invalidRole
    case invalidAuthority
    case writeAuthority
    case invalidWorkspace
    case invalidDisplaySession
    case invalidViewport
    case invalidFocus
    case invalidGeneration

    var errorDescription: String? {
        switch self {
        case .malformed: return "Malformed browser endpoint message."
        case .unsupportedType: return "Unsupported browser endpoint message type."
        case .invalidRole: return "Browser endpoint role must be display."
        case .invalidAuthority: return "Browser endpoints must not claim authority."
        case .writeAuthority: return "Browser endpoints cannot write workspace state."
        case .invalidWorkspace: return "Invalid browser endpoint workspace identifier."
        case .invalidDisplaySession: return "Invalid browser endpoint display session identifier."
        case .invalidViewport: return "Invalid browser endpoint viewport."
        case .invalidFocus: return "Invalid browser endpoint focus target."
        case .invalidGeneration: return "Invalid browser endpoint generation."
        }
    }

    var wireCode: BrowserEndpointWireErrorCode {
        switch self {
        case .malformed, .unsupportedType, .invalidRole, .invalidAuthority, .writeAuthority,
             .invalidWorkspace, .invalidDisplaySession, .invalidViewport, .invalidFocus,
             .invalidGeneration:
            return .protocolError
        }
    }
}

enum BrowserEndpointProtocolError: LocalizedError, Equatable {
    case invalidIdentifier(String)
    case invalidToken
    case invalidOrigin
    case invalidViewport
    case invalidFocus
    case invalidGeneration
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let name): return "Invalid browser endpoint identifier: \(name)."
        case .invalidToken: return "Invalid browser endpoint session token."
        case .invalidOrigin: return "Browser endpoint origin must be loopback HTTP."
        case .invalidViewport: return "Invalid browser endpoint viewport."
        case .invalidFocus: return "Invalid browser endpoint focus target."
        case .invalidGeneration: return "Invalid browser endpoint generation."
        case .invalidPath: return "Invalid browser endpoint path."
        }
    }
}

struct BrowserEndpointOrigin: Equatable, Sendable {
    let value: String
    let scheme: String
    let port: UInt16

    static func parseLoopback(_ raw: String) throws -> BrowserEndpointOrigin {
        guard !raw.isEmpty, !raw.contains("\\"), !raw.contains(" "), !raw.contains("\t") else {
            throw BrowserEndpointProtocolError.invalidOrigin
        }
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host == "127.0.0.1",
              url.user == nil,
              url.password == nil,
              url.port != nil,
              let port = url.port,
              port > 0,
              port <= 65_535,
              (url.path.isEmpty || url.path == "/"),
              url.query == nil,
              url.fragment == nil else {
            throw BrowserEndpointProtocolError.invalidOrigin
        }
        return BrowserEndpointOrigin(
            value: "\(scheme)://127.0.0.1:\(port)",
            scheme: scheme,
            port: UInt16(port)
        )
    }
}

enum BrowserEndpointValidation {
    static let maximumIdentifierLength = 256
    static let maximumTokenLength = 4096
    static let minimumTokenLength = 16
    static let maximumFocusLength = 512
    static let maximumViewportDimension = 100_000.0

    static func isValidIdentifier(_ value: String) -> Bool {
        guard (1...maximumIdentifierLength).contains(value.utf8.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 46, 95, 58, 45:
                return true
            default:
                return false
            }
        }
    }

    static func isValidToken(_ value: String) -> Bool {
        guard (minimumTokenLength...maximumTokenLength).contains(value.utf8.count) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 46, 95, 126, 45:
                return true
            default:
                return false
            }
        }
    }

    static func isValidPath(_ value: String) -> Bool {
        guard value.hasPrefix("/"), !value.contains("?"), !value.contains("#"),
              !value.contains("\\") else {
            return false
        }
        return !value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    static func isValidViewport(_ viewport: BrowserEndpointViewport) -> Bool {
        viewport.width.isFinite && viewport.height.isFinite &&
            viewport.width >= 0 && viewport.height >= 0 &&
            viewport.width <= maximumViewportDimension &&
            viewport.height <= maximumViewportDimension
    }

    static func isValidFocus(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.utf8.count <= maximumFocusLength
    }

    static func isValidGeneration(_ value: Int) -> Bool {
        value >= 0
    }

    static func constantTimeEquals(_ left: String, _ right: String) -> Bool {
        let leftBytes = Array(left.utf8)
        let rightBytes = Array(right.utf8)
        var difference = leftBytes.count ^ rightBytes.count
        let count = max(leftBytes.count, rightBytes.count)
        for index in 0..<count {
            let leftByte = index < leftBytes.count ? leftBytes[index] : 0
            let rightByte = index < rightBytes.count ? rightBytes[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }
        return difference == 0
    }
}

enum BrowserEndpointMessageCodec {
    static func parse(_ data: Data) throws -> BrowserEndpointMessage {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw BrowserEndpointMessageError.malformed
        }
        guard let dictionary = object as? [String: Any],
              let type = dictionary["type"] as? String else {
            throw BrowserEndpointMessageError.malformed
        }
        guard let kind = BrowserEndpointMessageKind(rawValue: type) else {
            throw BrowserEndpointMessageError.unsupportedType
        }
        guard let role = dictionary["role"] as? String, role == "display" else {
            throw BrowserEndpointMessageError.invalidRole
        }
        guard let authority = dictionary["authority"] as? String, authority == "none" else {
            throw BrowserEndpointMessageError.invalidAuthority
        }
        guard let canWrite = boolean(dictionary["canWriteWorkspace"]), canWrite == false else {
            throw BrowserEndpointMessageError.writeAuthority
        }
        guard let workspaceId = dictionary["workspaceId"] as? String,
              BrowserEndpointValidation.isValidIdentifier(workspaceId) else {
            throw BrowserEndpointMessageError.invalidWorkspace
        }
        guard let displaySessionId = dictionary["displaySessionId"] as? String,
              BrowserEndpointValidation.isValidIdentifier(displaySessionId) else {
            throw BrowserEndpointMessageError.invalidDisplaySession
        }
        guard let viewportObject = dictionary["viewport"] as? [String: Any],
              let width = number(viewportObject["width"]),
              let height = number(viewportObject["height"]) else {
            throw BrowserEndpointMessageError.invalidViewport
        }
        let viewport = BrowserEndpointViewport(width: width, height: height)
        guard BrowserEndpointValidation.isValidViewport(viewport) else {
            throw BrowserEndpointMessageError.invalidViewport
        }
        if kind == .viewport, viewport.width <= 0 || viewport.height <= 0 {
            throw BrowserEndpointMessageError.invalidViewport
        }
        let focusTarget = try focus(dictionary["focusTarget"])
        if kind == .focus, let focusTarget, focusTarget.isEmpty {
            throw BrowserEndpointMessageError.invalidFocus
        }
        guard let generation = integer(dictionary["generation"]),
              BrowserEndpointValidation.isValidGeneration(generation) else {
            throw BrowserEndpointMessageError.invalidGeneration
        }
        return BrowserEndpointMessage(
            kind: kind,
            state: BrowserEndpointDisplayState(
                workspaceId: workspaceId,
                displaySessionId: displaySessionId,
                viewport: viewport,
                focusTarget: focusTarget,
                generation: generation
            )
        )
    }

    static func registered(_ registration: BrowserEndpointRegistration) -> Data {
        encode([
            "type": "display.registered",
            "role": "display",
            "authority": "none",
            "workspaceId": registration.workspaceId,
            "displaySessionId": registration.displaySessionId,
            "generation": registration.generation,
            "canWriteWorkspace": false
        ])
    }

    static func error(code: BrowserEndpointWireErrorCode, message: String) -> Data {
        encode([
            "type": "display.error",
            "code": code.rawValue,
            "message": String(message.prefix(500))
        ])
    }

    private static func encode(_ dictionary: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]))
            ?? Data()
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite else { return nil }
        return double
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let double = number(value),
              double.rounded(.towardZero) == double,
              double >= 0,
              double <= Double(Int.max) else {
            return nil
        }
        return Int(double)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private static func focus(_ value: Any?) throws -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String,
              BrowserEndpointValidation.isValidFocus(string) else {
            throw BrowserEndpointMessageError.invalidFocus
        }
        return string
    }
}
