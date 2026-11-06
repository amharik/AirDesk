import CryptoKit
import Foundation

struct BrowserEndpointHTTPRequest: Equatable, Sendable {
    let method: String
    let target: String
    let version: String
    let headers: [String: [String]]

    func values(for name: String) -> [String] {
        headers[name.lowercased()] ?? []
    }

    func singleValue(for name: String) -> String? {
        let values = values(for: name)
        guard values.count == 1 else { return nil }
        return values[0]
    }
}

enum BrowserEndpointHTTPRequestError: LocalizedError, Equatable {
    case malformed
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .malformed: return "Malformed browser endpoint HTTP request."
        case .tooLarge: return "Browser endpoint HTTP request headers are too large."
        }
    }
}

enum BrowserEndpointHTTPRequestParser {
    static let maximumHeaderBytes = 16 * 1024

    static func parse(_ data: Data) throws -> BrowserEndpointHTTPRequest {
        guard data.count <= maximumHeaderBytes else {
            throw BrowserEndpointHTTPRequestError.tooLarge
        }
        guard let text = String(data: data, encoding: .utf8),
              !text.contains("\0") else {
            throw BrowserEndpointHTTPRequestError.malformed
        }

        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw BrowserEndpointHTTPRequestError.malformed
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              !parts[2].isEmpty else {
            throw BrowserEndpointHTTPRequestError.malformed
        }

        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            guard line.first != " ", line.first != "\t" else {
                throw BrowserEndpointHTTPRequestError.malformed
            }
            guard let colon = line.firstIndex(of: ":") else {
                throw BrowserEndpointHTTPRequestError.malformed
            }
            let name = String(line[..<colon]).lowercased()
            guard isValidHeaderName(name) else {
                throw BrowserEndpointHTTPRequestError.malformed
            }
            var value = String(line[line.index(after: colon)...])
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.unicodeScalars.contains(where: { scalar in
                scalar.value < 0x20 && scalar.value != 0x09
            }) else {
                throw BrowserEndpointHTTPRequestError.malformed
            }
            headers[name, default: []].append(value)
        }

        return BrowserEndpointHTTPRequest(
            method: String(parts[0]),
            target: String(parts[1]),
            version: String(parts[2]),
            headers: headers
        )
    }

    private static func isValidHeaderName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 33, 35...39, 42, 43, 45, 46, 48...57, 65...90, 94...122, 124, 126:
                return true
            default:
                return false
            }
        }
    }
}

enum BrowserEndpointHandshakeError: LocalizedError, Equatable {
    case malformedRequest
    case requestTooLarge
    case invalidMethod
    case invalidHTTPVersion
    case missingHost
    case invalidPath
    case missingUpgrade
    case invalidUpgrade
    case missingConnection
    case invalidConnection
    case unsupportedVersion
    case missingKey
    case invalidKey
    case missingToken
    case duplicateToken
    case invalidToken
    case tokenExpired
    case missingOrigin
    case duplicateOrigin
    case invalidOrigin
    case originMismatch

    var errorDescription: String? {
        switch self {
        case .malformedRequest: return "Malformed browser endpoint request."
        case .requestTooLarge: return "Browser endpoint request headers are too large."
        case .invalidMethod: return "Browser endpoint requires GET."
        case .invalidHTTPVersion: return "Browser endpoint requires HTTP/1.1."
        case .missingHost: return "Browser endpoint request is missing Host."
        case .invalidPath: return "Browser endpoint path is not supported."
        case .missingUpgrade: return "Browser endpoint requires a WebSocket upgrade."
        case .invalidUpgrade: return "Browser endpoint requires a WebSocket upgrade."
        case .missingConnection: return "Browser endpoint requires Connection: Upgrade."
        case .invalidConnection: return "Browser endpoint requires Connection: Upgrade."
        case .unsupportedVersion: return "Browser endpoint requires WebSocket version 13."
        case .missingKey: return "Browser endpoint request is missing Sec-WebSocket-Key."
        case .invalidKey: return "Browser endpoint Sec-WebSocket-Key is invalid."
        case .missingToken: return "Browser endpoint request is missing a session token."
        case .duplicateToken: return "Browser endpoint request has duplicate session tokens."
        case .invalidToken: return "Browser endpoint session token is invalid."
        case .tokenExpired: return "Browser endpoint session token has expired."
        case .missingOrigin: return "Browser endpoint request is missing Origin."
        case .duplicateOrigin: return "Browser endpoint request has duplicate Origin headers."
        case .invalidOrigin: return "Browser endpoint origin must be loopback HTTP."
        case .originMismatch: return "Browser endpoint origin is not allowed."
        }
    }

    var statusCode: Int {
        switch self {
        case .requestTooLarge: return 431
        case .invalidMethod: return 405
        case .invalidPath: return 404
        case .missingToken, .invalidToken, .tokenExpired: return 401
        case .missingOrigin, .duplicateOrigin, .invalidOrigin, .originMismatch: return 403
        case .unsupportedVersion: return 426
        case .malformedRequest, .invalidHTTPVersion, .missingHost, .missingUpgrade,
             .invalidUpgrade, .missingConnection, .invalidConnection, .missingKey,
             .invalidKey, .duplicateToken:
            return 400
        }
    }

    var responseHeaders: [String: String] {
        switch self {
        case .invalidMethod:
            return ["Allow": "GET"]
        case .unsupportedVersion:
            return ["Sec-WebSocket-Version": "13"]
        default:
            return [:]
        }
    }

    var responseData: Data {
        let reason: String
        switch statusCode {
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 426: reason = "Upgrade Required"
        case 431: reason = "Request Header Fields Too Large"
        default: reason = "Bad Request"
        }

        var headers = [
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Type: text/plain; charset=utf-8",
            "Connection: close"
        ]
        for (name, value) in responseHeaders.sorted(by: { $0.key < $1.key }) {
            headers.append("\(name): \(value)")
        }
        let body = Data((errorDescription ?? "Browser endpoint request rejected.").utf8)
        headers.append("Content-Length: \(body.count)")
        headers.append("")
        headers.append("")

        var data = Data(headers.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }
}

struct BrowserEndpointHandshakePolicy: Equatable, Sendable {
    let path: String
    let token: String
    let tokenExpiresAt: Date
    let allowedOrigin: BrowserEndpointOrigin
}

struct BrowserEndpointHandshake: Equatable, Sendable {
    let token: String
    let origin: BrowserEndpointOrigin
    let key: String

    static func validate(
        _ request: BrowserEndpointHTTPRequest,
        policy: BrowserEndpointHandshakePolicy,
        now: Date = Date()
    ) throws -> BrowserEndpointHandshake {
        guard request.method == "GET" else {
            throw BrowserEndpointHandshakeError.invalidMethod
        }
        guard request.version == "HTTP/1.1" else {
            throw BrowserEndpointHandshakeError.invalidHTTPVersion
        }
        guard let host = request.singleValue(for: "host"),
              !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw BrowserEndpointHandshakeError.missingHost
        }

        let target = try parseTarget(request.target)
        guard target.path == policy.path else {
            throw BrowserEndpointHandshakeError.invalidPath
        }

        let upgrades = commaSeparatedValues(request.values(for: "upgrade"))
        guard !upgrades.isEmpty else {
            throw BrowserEndpointHandshakeError.missingUpgrade
        }
        guard upgrades.contains("websocket") else {
            throw BrowserEndpointHandshakeError.invalidUpgrade
        }

        let connections = commaSeparatedValues(request.values(for: "connection"))
        guard !connections.isEmpty else {
            throw BrowserEndpointHandshakeError.missingConnection
        }
        guard connections.contains("upgrade") else {
            throw BrowserEndpointHandshakeError.invalidConnection
        }

        let versionValues = request.values(for: "sec-websocket-version")
        guard versionValues.count == 1 else {
            throw BrowserEndpointHandshakeError.unsupportedVersion
        }
        guard versionValues[0].trimmingCharacters(in: .whitespaces) == "13" else {
            throw BrowserEndpointHandshakeError.unsupportedVersion
        }

        let keyValues = request.values(for: "sec-websocket-key")
        guard !keyValues.isEmpty else {
            throw BrowserEndpointHandshakeError.missingKey
        }
        guard keyValues.count == 1 else {
            throw BrowserEndpointHandshakeError.invalidKey
        }
        let key = keyValues[0].trimmingCharacters(in: .whitespaces)
        guard let decodedKey = Data(base64Encoded: key, options: []),
              decodedKey.count == 16 else {
            throw BrowserEndpointHandshakeError.invalidKey
        }

        let tokenValues = target.query.filter { $0.name == "token" }.map(\.value)
        guard !tokenValues.isEmpty else {
            throw BrowserEndpointHandshakeError.missingToken
        }
        guard tokenValues.count == 1 else {
            throw BrowserEndpointHandshakeError.duplicateToken
        }
        let token = tokenValues[0]
        guard BrowserEndpointValidation.isValidToken(token),
              BrowserEndpointValidation.constantTimeEquals(token, policy.token) else {
            throw BrowserEndpointHandshakeError.invalidToken
        }
        guard now < policy.tokenExpiresAt else {
            throw BrowserEndpointHandshakeError.tokenExpired
        }

        let originValues = request.values(for: "origin")
        guard !originValues.isEmpty else {
            throw BrowserEndpointHandshakeError.missingOrigin
        }
        guard originValues.count == 1 else {
            throw BrowserEndpointHandshakeError.duplicateOrigin
        }
        let origin: BrowserEndpointOrigin
        do {
            origin = try BrowserEndpointOrigin.parseLoopback(
                originValues[0].trimmingCharacters(in: .whitespaces)
            )
        } catch {
            throw BrowserEndpointHandshakeError.invalidOrigin
        }
        guard origin == policy.allowedOrigin else {
            throw BrowserEndpointHandshakeError.originMismatch
        }

        return BrowserEndpointHandshake(token: token, origin: origin, key: key)
    }

    func acceptResponseData() -> Data {
        let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + guid).utf8))
        let accept = Data(digest).base64EncodedString()
        let response = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(accept)",
            "Cache-Control: no-store",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(response.utf8)
    }

    private static func commaSeparatedValues(_ values: [String]) -> Set<String> {
        var result = Set<String>()
        for value in values {
            for part in value.split(separator: ",") {
                let token = part.trimmingCharacters(in: .whitespaces).lowercased()
                if !token.isEmpty {
                    result.insert(token)
                }
            }
        }
        return result
    }

    private struct Target {
        let path: String
        let query: [(name: String, value: String)]
    }

    private static func parseTarget(_ target: String) throws -> Target {
        guard target.hasPrefix("/"),
              !target.contains("#"),
              !target.contains("\\"),
              !target.unicodeScalars.contains(where: { $0.value < 0x20 }) else {
            throw BrowserEndpointHandshakeError.malformedRequest
        }

        let pieces = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawPath = pieces.first else {
            throw BrowserEndpointHandshakeError.malformedRequest
        }
        let path = String(rawPath)
        guard !path.isEmpty else {
            throw BrowserEndpointHandshakeError.malformedRequest
        }

        var query: [(name: String, value: String)] = []
        if pieces.count == 2, !pieces[1].isEmpty {
            for component in pieces[1].split(separator: "&", omittingEmptySubsequences: false) {
                if component.isEmpty { continue }
                let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let rawName = pair.first,
                      let name = String(rawName).removingPercentEncoding,
                      !name.isEmpty else {
                    throw BrowserEndpointHandshakeError.malformedRequest
                }
                let rawValue = pair.count == 2 ? String(pair[1]) : ""
                guard let value = rawValue.removingPercentEncoding else {
                    throw BrowserEndpointHandshakeError.malformedRequest
                }
                query.append((name: name, value: value))
            }
        }

        return Target(path: path, query: query)
    }
}
