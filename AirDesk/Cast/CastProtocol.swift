import Foundation

enum CastProtocol {
    static let controlVersion = 2
    static let inputVersion = 1
    static let maxMessageBytes = 64 * 1024
    static let readyTimeout: TimeInterval = 12
    static let receiverVersion = "1"
}

struct CastProtocolVersions: Codable, Equatable, Sendable {
    var input: Int = CastProtocol.inputVersion
    var control: Int = CastProtocol.controlVersion
}

struct CastReceiverCapabilities: Codable, Equatable, Sendable {
    var pointer: Bool
    var keyboard: Bool
    var textInput: Bool
    var desktopWindows: Bool

    static let desktop = CastReceiverCapabilities(
        pointer: true,
        keyboard: true,
        textInput: true,
        desktopWindows: true
    )
}

struct CastControlMessage: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case sessionStart
        case sessionResume
        case appearance
        case workspace
        case sessionEnd
        case ping

        case ready
        case state
        case viewport
        case ack
        case notice
        case error
        case pong

        static let senderTypes: Set<Kind> = [
            .sessionStart, .sessionResume, .appearance, .workspace, .sessionEnd, .ping
        ]

        static let receiverTypes: Set<Kind> = [
            .ready, .state, .viewport, .ack, .notice, .error, .pong
        ]
    }

    var version: Int = CastProtocol.controlVersion
    var type: Kind
    var sessionId: String
    var generation: Int = 1
    var operationId: String? = nil
    var workspace: String? = nil
    var appearance: String? = nil
    var protocolInfo: CastProtocolVersions? = nil
    var lastAckedInputSeq: Int? = nil
    var receiverVersion: String? = nil
    var width: Double? = nil
    var height: Double? = nil
    var persistence: String? = nil
    var capabilities: CastReceiverCapabilities? = nil
    var lastAcceptedInputSeq: Int? = nil
    var state: String? = nil
    var message: String? = nil
    var code: String? = nil

    private enum CodingKeys: String, CodingKey {
        case version
        case type
        case sessionId
        case generation
        case operationId
        case workspace
        case appearance
        case protocolInfo = "protocol"
        case lastAckedInputSeq
        case receiverVersion
        case width
        case height
        case persistence
        case capabilities
        case lastAcceptedInputSeq
        case state
        case message
        case code
    }

    static func sessionStart(
        sessionId: String,
        generation: Int,
        workspace: String,
        appearance: String,
        operationId: String = UUID().uuidString
    ) -> CastControlMessage {
        CastControlMessage(
            type: .sessionStart,
            sessionId: sessionId,
            generation: generation,
            operationId: operationId,
            workspace: workspace,
            appearance: appearance,
            protocolInfo: CastProtocolVersions()
        )
    }

    static func sessionResume(
        sessionId: String,
        generation: Int,
        lastAckedInputSeq: Int,
        operationId: String = UUID().uuidString
    ) -> CastControlMessage {
        CastControlMessage(
            type: .sessionResume,
            sessionId: sessionId,
            generation: generation,
            operationId: operationId,
            lastAckedInputSeq: lastAckedInputSeq
        )
    }

    static func appearance(
        sessionId: String,
        generation: Int,
        appearance: String,
        operationId: String = UUID().uuidString
    ) -> CastControlMessage {
        CastControlMessage(
            type: .appearance,
            sessionId: sessionId,
            generation: generation,
            operationId: operationId,
            appearance: appearance
        )
    }

    static func workspace(
        sessionId: String,
        generation: Int,
        workspace: String,
        operationId: String = UUID().uuidString
    ) -> CastControlMessage {
        CastControlMessage(
            type: .workspace,
            sessionId: sessionId,
            generation: generation,
            operationId: operationId,
            workspace: workspace
        )
    }

    static func sessionEnd(
        sessionId: String,
        generation: Int,
        operationId: String = UUID().uuidString
    ) -> CastControlMessage {
        CastControlMessage(
            type: .sessionEnd,
            sessionId: sessionId,
            generation: generation,
            operationId: operationId
        )
    }

    static func ping(
        sessionId: String,
        generation: Int,
        operationId: String = UUID().uuidString
    ) -> CastControlMessage {
        CastControlMessage(
            type: .ping,
            sessionId: sessionId,
            generation: generation,
            operationId: operationId
        )
    }

    static func ready(
        sessionId: String,
        generation: Int,
        width: Double,
        height: Double,
        persistence: String,
        lastAcceptedInputSeq: Int
    ) -> CastControlMessage {
        CastControlMessage(
            type: .ready,
            sessionId: sessionId,
            generation: generation,
            receiverVersion: CastProtocol.receiverVersion,
            width: width,
            height: height,
            persistence: persistence,
            capabilities: .desktop,
            lastAcceptedInputSeq: lastAcceptedInputSeq
        )
    }

    static func state(
        sessionId: String,
        generation: Int,
        state: String
    ) -> CastControlMessage {
        CastControlMessage(
            type: .state,
            sessionId: sessionId,
            generation: generation,
            state: state
        )
    }

    static func ack(
        sessionId: String,
        generation: Int,
        lastAcceptedInputSeq: Int
    ) -> CastControlMessage {
        CastControlMessage(
            type: .ack,
            sessionId: sessionId,
            generation: generation,
            lastAcceptedInputSeq: lastAcceptedInputSeq
        )
    }

    static func error(
        sessionId: String,
        generation: Int,
        code: String,
        message: String
    ) -> CastControlMessage {
        CastControlMessage(
            type: .error,
            sessionId: sessionId,
            generation: generation,
            message: message,
            code: code
        )
    }

    func validated() throws -> CastControlMessage {
        guard version == CastProtocol.controlVersion else {
            throw CastProtocolError.unsupportedVersion
        }
        guard !sessionId.isEmpty, sessionId.count <= 64 else {
            throw CastProtocolError.invalidSession
        }
        guard generation >= 0, generation <= Int(Int32.max) else {
            throw CastProtocolError.invalidGeneration
        }
        if let operationId, operationId.isEmpty || operationId.count > 128 {
            throw CastProtocolError.invalidField
        }
        let size = try jsonString().utf8.count
        guard size <= CastProtocol.maxMessageBytes else {
            throw CastProtocolError.messageTooLarge
        }

        switch type {
        case .sessionStart:
            try validateText(workspace, max: 128)
            try validateText(appearance, max: 32)
            guard protocolInfo?.input == CastProtocol.inputVersion,
                  protocolInfo?.control == CastProtocol.controlVersion else {
                throw CastProtocolError.unsupportedVersion
            }
        case .sessionResume:
            guard let lastAckedInputSeq, lastAckedInputSeq >= 0 else {
                throw CastProtocolError.invalidField
            }
        case .appearance:
            try validateText(appearance, max: 32)
        case .workspace:
            try validateText(workspace, max: 128)
        case .sessionEnd, .ping, .pong:
            break
        case .ready:
            try validateText(receiverVersion, max: 64)
            try validateDimension(width)
            try validateDimension(height)
            try validateText(persistence, max: 64)
            guard capabilities != nil, let lastAcceptedInputSeq, lastAcceptedInputSeq >= 0 else {
                throw CastProtocolError.invalidField
            }
        case .state:
            try validateText(state, max: 64)
        case .viewport:
            try validateDimension(width)
            try validateDimension(height)
        case .ack:
            guard let lastAcceptedInputSeq, lastAcceptedInputSeq >= 0 else {
                throw CastProtocolError.invalidField
            }
        case .notice, .error:
            try validateText(message, max: 4000)
            if type == .error {
                try validateText(code, max: 64)
            }
        }

        return self
    }

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CastProtocolError.invalidField
        }
        return string
    }

    static func decode(from data: Data) throws -> CastControlMessage {
        guard data.count <= CastProtocol.maxMessageBytes else {
            throw CastProtocolError.messageTooLarge
        }
        do {
            return try JSONDecoder().decode(CastControlMessage.self, from: data).validated()
        } catch let error as CastProtocolError {
            throw error
        } catch {
            throw CastProtocolError.malformedPayload
        }
    }

    static func decode(from string: String) throws -> CastControlMessage {
        try decode(from: Data(string.utf8))
    }

    private func validateText(_ value: String?, max: Int) throws {
        guard let value, !value.isEmpty, value.count <= max else {
            throw CastProtocolError.invalidField
        }
    }

    private func validateDimension(_ value: Double?) throws {
        guard let value, value.isFinite, value > 0, value <= 20_000 else {
            throw CastProtocolError.invalidField
        }
    }
}

enum CastProtocolError: LocalizedError, Equatable {
    case unsupportedVersion
    case unsupportedType
    case malformedPayload
    case messageTooLarge
    case invalidSession
    case invalidGeneration
    case invalidField
    case sessionMismatch
    case staleGeneration
    case receiverError(String)
    case readyTimeout

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "The Cast receiver does not support this protocol version."
        case .unsupportedType: return "The Cast receiver sent an unsupported message."
        case .malformedPayload: return "The Cast receiver sent a malformed message."
        case .messageTooLarge: return "The Cast message exceeded the size limit."
        case .invalidSession: return "The Cast session identifier is invalid."
        case .invalidGeneration: return "The Cast session generation is invalid."
        case .invalidField: return "A required Cast message field is invalid."
        case .sessionMismatch: return "The Cast message belongs to a different session."
        case .staleGeneration: return "The Cast message belongs to an older session generation."
        case .receiverError(let code): return "The Cast receiver reported an error: \(code)."
        case .readyTimeout: return "The Cast receiver did not report readiness in time."
        }
    }
}
