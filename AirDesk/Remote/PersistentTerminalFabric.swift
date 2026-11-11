import FlatBuffers
import Foundation

enum TerminalFabricFrameType: UInt32, Sendable {
    case attach = 0
    case attached = 1
    case data = 2
    case resize = 3
    case detach = 4
    case exit = 5
    case error = 6
}

struct TerminalFabricFrame: Equatable, Sendable {
    var frameType: TerminalFabricFrameType
    var sessionId: String
    var clientId: String? = nil
    var leaseId: String? = nil
    var sequence: UInt64 = 0
    var replayFromSequence: UInt64 = 0
    var oldestSequence: UInt64 = 0
    var data: Data = Data()
    var columns: UInt32 = 80
    var rows: UInt32 = 24
    var exitCode: Int32 = 0
    var message: String? = nil
    var truncated = false

    static func attach(
        sessionId: String,
        clientId: String,
        leaseId: String,
        afterSequence: UInt64
    ) -> TerminalFabricFrame {
        TerminalFabricFrame(
            frameType: .attach,
            sessionId: sessionId,
            clientId: clientId,
            leaseId: leaseId,
            replayFromSequence: afterSequence
        )
    }

    static func request(
        _ frameType: TerminalFabricFrameType,
        sessionId: String,
        clientId: String,
        leaseId: String
    ) -> TerminalFabricFrame {
        TerminalFabricFrame(
            frameType: frameType,
            sessionId: sessionId,
            clientId: clientId,
            leaseId: leaseId
        )
    }
}

enum TerminalFabricError: Error, Equatable, LocalizedError {
    case empty
    case oversized
    case truncated
    case wrongFileIdentifier
    case wrongVersion
    case wrongPayload
    case unsupportedType(UInt32)
    case missingSession

    var errorDescription: String? {
        switch self {
        case .empty: return "Terminal frame is empty."
        case .oversized: return "Terminal frame exceeds the 1 MiB limit."
        case .truncated: return "Terminal frame is truncated."
        case .wrongFileIdentifier: return "Terminal frame file identifier must be ADEN."
        case .wrongVersion: return "Unsupported terminal frame version."
        case .wrongPayload: return "ADFP envelope is not a terminal payload."
        case .unsupportedType(let value): return "Unsupported terminal frame type \(value)."
        case .missingSession: return "Terminal frame is missing a session id."
        }
    }
}

enum TerminalFabricCodec {
    static let version: UInt32 = 1
    static let maxFrameBytes = 1024 * 1_024
    static let fileIdentifier: [UInt8] = [0x41, 0x44, 0x45, 0x4E]

    static func encode(_ frame: TerminalFabricFrame) throws -> Data {
        guard !frame.sessionId.isEmpty else { throw TerminalFabricError.missingSession }
        var builder = FlatBufferBuilder(initialSize: 1024)
        let sessionId = builder.create(string: frame.sessionId)
        let clientId = frame.clientId.map { builder.create(string: $0) } ?? Offset()
        let lease: Offset
        if let value = frame.leaseId, !value.isEmpty {
            let leaseId = builder.create(string: value)
            lease = AirDesk_Protocol__CapabilityLease.createCapabilityLease(
                &builder,
                leaseIdOffset: leaseId,
                sessionIdOffset: sessionId
            )
        } else {
            lease = Offset()
        }
        let data = frame.data.isEmpty ? Offset() : builder.createVector(bytes: [UInt8](frame.data))
        let message = frame.message.map { builder.create(string: $0) } ?? Offset()
        let terminal = AirDesk_Protocol__TerminalMessage.createTerminalMessage(
            &builder,
            version: version,
            type: AirDesk_Protocol__TerminalMessageType(rawValue: frame.frameType.rawValue) ?? .attach,
            sessionIdOffset: sessionId,
            clientIdOffset: clientId,
            leaseOffset: lease,
            sequence: frame.sequence,
            replayFromSequence: frame.replayFromSequence,
            oldestSequence: frame.oldestSequence,
            dataVectorOffset: data,
            columns: frame.columns,
            rows: frame.rows,
            exitCode: frame.exitCode,
            messageOffset: message,
            truncated: frame.truncated
        )
        let envelope = AirDesk_Protocol__Envelope.createEnvelope(
            &builder,
            version: version,
            fabricPayloadType: .terminalmessage,
            fabricPayloadOffset: terminal
        )
        AirDesk_Protocol__Envelope.finish(&builder, end: envelope)
        let encoded = Data(builder.data)
        guard encoded.count <= maxFrameBytes else { throw TerminalFabricError.oversized }
        return encoded
    }

    static func decode(_ data: Data) throws -> TerminalFabricFrame {
        try validate(data)
        var buffer = ByteBuffer(data: data)
        let envelope: AirDesk_Protocol__Envelope = getRoot(byteBuffer: &buffer)
        guard envelope.version == version else { throw TerminalFabricError.wrongVersion }
        guard envelope.fabricPayloadType == .terminalmessage,
              let terminal = envelope.fabricPayload(type: AirDesk_Protocol__TerminalMessage.self)
        else {
            throw TerminalFabricError.wrongPayload
        }
        guard terminal.version == version else { throw TerminalFabricError.wrongVersion }
        guard let sessionId = terminal.sessionId, !sessionId.isEmpty else {
            throw TerminalFabricError.missingSession
        }
        guard let frameType = TerminalFabricFrameType(rawValue: terminal.type.rawValue) else {
            throw TerminalFabricError.unsupportedType(terminal.type.rawValue)
        }
        return TerminalFabricFrame(
            frameType: frameType,
            sessionId: sessionId,
            clientId: terminal.clientId,
            leaseId: terminal.lease?.leaseId,
            sequence: terminal.sequence,
            replayFromSequence: terminal.replayFromSequence,
            oldestSequence: terminal.oldestSequence,
            data: Data(terminal.data),
            columns: terminal.columns,
            rows: terminal.rows,
            exitCode: terminal.exitCode,
            message: terminal.message,
            truncated: terminal.truncated
        )
    }

    static func encodeLengthPrefixed(_ frame: TerminalFabricFrame) throws -> Data {
        let payload = try encode(frame)
        var length = UInt32(payload.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(payload)
        return data
    }

    static func takeLengthPrefixedFrame(from buffer: inout Data) throws -> TerminalFabricFrame? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= UInt32(maxFrameBytes) else {
            throw length == 0 ? TerminalFabricError.empty : TerminalFabricError.oversized
        }
        guard buffer.count >= 4 + Int(length) else { return nil }
        let start = buffer.startIndex + 4
        let end = start + Int(length)
        let payload = buffer.subdata(in: start..<end)
        buffer.removeFirst(4 + Int(length))
        return try decode(payload)
    }

    private static func validate(_ data: Data) throws {
        guard !data.isEmpty else { throw TerminalFabricError.empty }
        guard data.count <= maxFrameBytes else { throw TerminalFabricError.oversized }
        guard data.count >= 8 else { throw TerminalFabricError.truncated }
        let bytes = [UInt8](data.prefix(8))
        guard Array(bytes[4..<8]) == fileIdentifier else {
            throw TerminalFabricError.wrongFileIdentifier
        }
    }
}

struct PersistentTerminalReplayState: Equatable {
    private(set) var lastSequence: UInt64 = 0
    private(set) var oldestSequence: UInt64 = 0
    private(set) var truncated = false

    mutating func accept(_ frame: TerminalFabricFrame) -> Bool {
        switch frame.frameType {
        case .attached:
            oldestSequence = frame.oldestSequence
            truncated = frame.truncated
            return true
        case .data:
            guard frame.sequence > lastSequence else { return false }
            lastSequence = frame.sequence
            return true
        case .exit, .error:
            return true
        case .attach, .resize, .detach:
            return true
        }
    }

    func attachRequest(sessionId: String, clientId: String, leaseId: String) -> TerminalFabricFrame {
        TerminalFabricFrame.attach(
            sessionId: sessionId,
            clientId: clientId,
            leaseId: leaseId,
            afterSequence: lastSequence
        )
    }
}
