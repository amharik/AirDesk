import Foundation

struct AdPairWireMessage: Codable, Equatable {
    enum Kind: String, Codable {
        case response
        case share
        case verifierResponse = "verifier-response"
        case initiatorFinish = "initiator-finish"
        case responderFinish = "responder-finish"
    }

    static let protocolName = "adpair-wire"
    static let version = 1

    let protocolName: String
    let version: Int
    let kind: Kind
    let response: Data?
    let share: Data?
    let confirmation: Data?
    let signature: Data?

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case version
        case kind
        case response
        case share
        case confirmation
        case signature
    }

    private init(
        kind: Kind,
        response: Data? = nil,
        share: Data? = nil,
        confirmation: Data? = nil,
        signature: Data? = nil
    ) {
        self.protocolName = Self.protocolName
        self.version = Self.version
        self.kind = kind
        self.response = response
        self.share = share
        self.confirmation = confirmation
        self.signature = signature
    }

    static func response(_ data: Data) throws -> AdPairWireMessage {
        try validatePayload(data, name: "response")
        return AdPairWireMessage(kind: .response, response: data)
    }

    static func share(_ share: Data) throws -> AdPairWireMessage {
        try validatePayload(share, name: "share")
        return AdPairWireMessage(kind: .share, share: share)
    }

    static func verifierResponse(
        share: Data,
        confirmation: Data,
        signature: Data
    ) throws -> AdPairWireMessage {
        try validatePayload(share, name: "share")
        try validatePayload(confirmation, name: "confirmation")
        try validatePayload(signature, name: "signature")
        return AdPairWireMessage(
            kind: .verifierResponse,
            share: share,
            confirmation: confirmation,
            signature: signature
        )
    }

    static func initiatorFinish(
        confirmation: Data,
        signature: Data
    ) throws -> AdPairWireMessage {
        try validatePayload(confirmation, name: "confirmation")
        try validatePayload(signature, name: "signature")
        return AdPairWireMessage(
            kind: .initiatorFinish,
            confirmation: confirmation,
            signature: signature
        )
    }

    static func responderFinish(
        confirmation: Data,
        signature: Data
    ) throws -> AdPairWireMessage {
        try validatePayload(confirmation, name: "confirmation")
        try validatePayload(signature, name: "signature")
        return AdPairWireMessage(
            kind: .responderFinish,
            confirmation: confirmation,
            signature: signature
        )
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> AdPairWireMessage {
        let message: AdPairWireMessage
        do {
            message = try JSONDecoder().decode(AdPairWireMessage.self, from: data)
        } catch {
            throw AdPairWireError.malformed
        }
        guard message.protocolName == Self.protocolName else {
            throw AdPairWireError.unsupportedProtocol
        }
        guard message.version == Self.version else {
            throw AdPairWireError.unsupportedVersion
        }
        try message.validate()
        return message
    }

    private func validate() throws {
        switch kind {
        case .response:
            guard response != nil, share == nil, confirmation == nil, signature == nil else {
                throw AdPairWireError.invalidPayload(kind.rawValue)
            }
            try Self.validatePayload(response, name: "response")
        case .share:
            guard response == nil, share != nil, confirmation == nil, signature == nil else {
                throw AdPairWireError.invalidPayload(kind.rawValue)
            }
            try Self.validatePayload(share, name: "share")
        case .verifierResponse:
            guard response == nil,
                  share != nil,
                  confirmation != nil,
                  signature != nil else {
                throw AdPairWireError.invalidPayload(kind.rawValue)
            }
            try Self.validatePayload(share, name: "share")
            try Self.validatePayload(confirmation, name: "confirmation")
            try Self.validatePayload(signature, name: "signature")
        case .initiatorFinish, .responderFinish:
            guard response == nil,
                  share == nil,
                  confirmation != nil,
                  signature != nil else {
                throw AdPairWireError.invalidPayload(kind.rawValue)
            }
            try Self.validatePayload(confirmation, name: "confirmation")
            try Self.validatePayload(signature, name: "signature")
        }
    }

    private static func validatePayload(_ data: Data?, name: String) throws {
        guard let data, !data.isEmpty, data.count <= 1_048_576 else {
            throw AdPairWireError.invalidPayload(name)
        }
    }
}

enum AdPairWireError: Swift.Error, Equatable, LocalizedError {
    case malformed
    case unsupportedProtocol
    case unsupportedVersion
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .malformed: return "Pairing message is malformed."
        case .unsupportedProtocol: return "Unsupported pairing message protocol."
        case .unsupportedVersion: return "Unsupported pairing message version."
        case .invalidPayload(let name): return "Invalid pairing message payload: \(name)."
        }
    }
}
