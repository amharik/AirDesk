import FlatBuffers
import Foundation

enum ADFPEnvelopeError: Error, Equatable, LocalizedError {
    case empty
    case oversized
    case truncated
    case wrongFileIdentifier
    case wrongVersion
    case headerMissing
    case headerInvalid(String)
    case headerExpired
    case unsupportedPayload
    case unsupportedEvent

    var errorDescription: String? {
        switch self {
        case .empty: return "ADFP envelope is empty."
        case .oversized: return "ADFP envelope exceeds the 1 MiB limit."
        case .truncated: return "ADFP envelope is truncated."
        case .wrongFileIdentifier: return "ADFP envelope file identifier must be ADEN."
        case .wrongVersion: return "Unsupported ADFP envelope version."
        case .headerMissing: return "ADFP envelope is missing a ControlHeader."
        case .headerInvalid(let field): return "ADFP header field is invalid: \(field)."
        case .headerExpired: return "ADFP envelope header has expired."
        case .unsupportedPayload: return "Unsupported ADFP payload."
        case .unsupportedEvent: return "Unsupported input event for ADFP envelope v1."
        }
    }
}

struct ADFPHeader: Equatable {
    var messageId: String
    var senderDeviceId: String
    var senderRole: AirDesk_Protocol__SenderRole
    var correlationId: String?
    var idempotencyKey: String?
    var expiresAtEpochMillis: UInt64
    var cancellationId: String?
}

struct ADFPControlMessage: Equatable {
    var version: UInt32
    var type: AirDesk_Protocol__ControlType
    var sessionId: String
    var generation: UInt32
    var seq: UInt32
    var timestamp: UInt64
    var appearance: String?
    var message: String?
    var action: String?
    var width: Float32
    var height: Float32
    var code: String?
}

enum ADFPPayload: Equatable {
    case input(InputEvent)
    case control(ADFPControlMessage)
}

struct ADFPDecodedEnvelope: Equatable {
    var header: ADFPHeader
    var payload: ADFPPayload
}

enum ADFPEnvelopeCodec {
    static let fileIdentifier = "ADEN"
    static let version: UInt32 = 1
    static let maxEnvelopeBytes = 1024 * 1024
    static let maxHeaderStringBytes = 128

    static func encodeInput(
        _ event: InputEvent,
        header: ADFPHeader,
        now: Date = Date()
    ) throws -> Data {
        let event = try event.validated()
        try validate(header, now: now)

        var builder = FlatBufferBuilder(initialSize: 1024)
        let sessionId = builder.create(string: event.sessionId)
        let key = event.key.map { builder.create(string: $0) } ?? Offset()
        let code = event.code.map { builder.create(string: $0) } ?? Offset()
        let text = event.text.map { builder.create(string: $0) } ?? Offset()
        let target = event.target.map { builder.create(string: $0) } ?? Offset()
        let modifiers = event.modifiers ?? []
        let modifiersOffset = modifiers.isEmpty ? Offset() : builder.createVector(ofStrings: modifiers)
        let input = AirDesk_Protocol__InputEvent.createInputEvent(
            &builder,
            version: UInt32(clamping: event.version),
            type: try flatBufferType(for: event.type),
            sessionIdOffset: sessionId,
            generation: UInt32(clamping: event.generation ?? 0),
            seq: UInt32(clamping: event.seq),
            timestamp: UInt64(clamping: UInt64(max(0, event.timestamp.rounded()))),
            x: Float32(event.x ?? 0),
            y: Float32(event.y ?? 0),
            dx: Float32(event.dx ?? 0),
            dy: Float32(event.dy ?? 0),
            button: UInt8(clamping: event.button ?? 0),
            clickCount: UInt8(clamping: event.clickCount ?? 1),
            keyOffset: key,
            codeOffset: code,
            modifiersVectorOffset: modifiersOffset,
            textOffset: text,
            width: Float32(event.width ?? 0),
            height: Float32(event.height ?? 0),
            targetOffset: target
        )
        return try finish(builder: &builder, payloadType: .inputevent, payload: input, header: header)
    }

    static func encodeControl(
        _ message: ADFPControlMessage,
        header: ADFPHeader,
        now: Date = Date()
    ) throws -> Data {
        try validate(header, now: now)

        var builder = FlatBufferBuilder(initialSize: 1024)
        let sessionId = builder.create(string: message.sessionId)
        let appearance = message.appearance.map { builder.create(string: $0) } ?? Offset()
        let text = message.message.map { builder.create(string: $0) } ?? Offset()
        let action = message.action.map { builder.create(string: $0) } ?? Offset()
        let code = message.code.map { builder.create(string: $0) } ?? Offset()
        let control = AirDesk_Protocol__ControlMessage.createControlMessage(
            &builder,
            version: message.version,
            type: message.type,
            sessionIdOffset: sessionId,
            generation: message.generation,
            seq: message.seq,
            timestamp: message.timestamp,
            appearanceOffset: appearance,
            messageOffset: text,
            actionOffset: action,
            width: message.width,
            height: message.height,
            codeOffset: code
        )
        return try finish(builder: &builder, payloadType: .controlmessage, payload: control, header: header)
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> ADFPDecodedEnvelope {
        try validateEnvelope(data)
        var buffer = ByteBuffer(data: data)
        let envelope: AirDesk_Protocol__Envelope = getRoot(byteBuffer: &buffer)

        guard envelope.version == version else { throw ADFPEnvelopeError.wrongVersion }
        guard let rawHeader = envelope.header else { throw ADFPEnvelopeError.headerMissing }
        let header = try readHeader(rawHeader, now: now)

        switch envelope.payloadType {
        case .inputevent:
            guard let input = envelope.payload(type: AirDesk_Protocol__InputEvent.self) else {
                throw ADFPEnvelopeError.unsupportedPayload
            }
            return ADFPDecodedEnvelope(header: header, payload: .input(try readInput(input)))
        case .controlmessage:
            guard let control = envelope.payload(type: AirDesk_Protocol__ControlMessage.self) else {
                throw ADFPEnvelopeError.unsupportedPayload
            }
            return ADFPDecodedEnvelope(header: header, payload: .control(readControl(control)))
        default:
            throw ADFPEnvelopeError.unsupportedPayload
        }
    }

    private static func finish(
        builder: inout FlatBufferBuilder,
        payloadType: AirDesk_Protocol__MessagePayload,
        payload: Offset,
        header: ADFPHeader
    ) throws -> Data {
        let headerOffset = buildHeader(&builder, header: header)
        let envelope = AirDesk_Protocol__Envelope.createEnvelope(
            &builder,
            version: version,
            payloadType: payloadType,
            payloadOffset: payload,
            headerOffset: headerOffset
        )
        AirDesk_Protocol__Envelope.finish(&builder, end: envelope)
        let data = Data(builder.data)
        guard data.count <= maxEnvelopeBytes else { throw ADFPEnvelopeError.oversized }
        return data
    }

    private static func buildHeader(_ builder: inout FlatBufferBuilder, header: ADFPHeader) -> Offset {
        let messageId = builder.create(string: header.messageId)
        let senderDeviceId = builder.create(string: header.senderDeviceId)
        let correlationId = header.correlationId.map { builder.create(string: $0) } ?? Offset()
        let idempotencyKey = header.idempotencyKey.map { builder.create(string: $0) } ?? Offset()
        let cancellationId = header.cancellationId.map { builder.create(string: $0) } ?? Offset()
        return AirDesk_Protocol__ControlHeader.createControlHeader(
            &builder,
            messageIdOffset: messageId,
            senderDeviceIdOffset: senderDeviceId,
            senderRole: header.senderRole,
            correlationIdOffset: correlationId,
            idempotencyKeyOffset: idempotencyKey,
            expiresAt: header.expiresAtEpochMillis,
            cancellationIdOffset: cancellationId
        )
    }

    private static func validate(_ header: ADFPHeader, now: Date) throws {
        try validateString(header.messageId, field: "messageId", required: true)
        try validateString(header.senderDeviceId, field: "senderDeviceId", required: true)
        try validateString(header.correlationId, field: "correlationId", required: false)
        try validateString(header.idempotencyKey, field: "idempotencyKey", required: false)
        try validateString(header.cancellationId, field: "cancellationId", required: false)
        guard header.senderRole != .unspecified else {
            throw ADFPEnvelopeError.headerInvalid("senderRole")
        }
        if header.expiresAtEpochMillis != 0 {
            let nowMillis = UInt64(max(0, now.timeIntervalSince1970 * 1000))
            guard header.expiresAtEpochMillis > nowMillis else { throw ADFPEnvelopeError.headerExpired }
        }
    }

    private static func validateString(_ value: String?, field: String, required: Bool) throws {
        if required, (value ?? "").isEmpty {
            throw ADFPEnvelopeError.headerInvalid(field)
        }
        if let value, value.utf8.count > maxHeaderStringBytes {
            throw ADFPEnvelopeError.headerInvalid(field)
        }
    }

    private static func readHeader(
        _ header: AirDesk_Protocol__ControlHeader,
        now: Date
    ) throws -> ADFPHeader {
        let decoded = ADFPHeader(
            messageId: header.messageId ?? "",
            senderDeviceId: header.senderDeviceId ?? "",
            senderRole: header.senderRole,
            correlationId: header.correlationId,
            idempotencyKey: header.idempotencyKey,
            expiresAtEpochMillis: header.expiresAt,
            cancellationId: header.cancellationId
        )
        try validate(decoded, now: now)
        return decoded
    }

    private static func readInput(_ input: AirDesk_Protocol__InputEvent) throws -> InputEvent {
        guard let sessionId = input.sessionId, !sessionId.isEmpty else {
            throw ADFPEnvelopeError.unsupportedPayload
        }
        var modifiers: [String] = []
        for modifier in input.modifiers {
            if let modifier {
                modifiers.append(modifier)
            }
        }
        let event = InputEvent(
            version: Int(input.version),
            type: try inputKind(for: input.type),
            sessionId: sessionId,
            generation: Int(input.generation),
            seq: Int(input.seq),
            timestamp: Double(input.timestamp),
            x: Double(input.x),
            y: Double(input.y),
            dx: Double(input.dx),
            dy: Double(input.dy),
            button: Int(input.button),
            clickCount: Int(input.clickCount),
            key: input.key,
            code: input.code,
            modifiers: modifiers,
            text: input.text,
            width: Double(input.width),
            height: Double(input.height),
            target: input.target
        )
        return try event.validated()
    }

    private static func readControl(_ control: AirDesk_Protocol__ControlMessage) -> ADFPControlMessage {
        ADFPControlMessage(
            version: control.version,
            type: control.type,
            sessionId: control.sessionId ?? "",
            generation: control.generation,
            seq: control.seq,
            timestamp: control.timestamp,
            appearance: control.appearance,
            message: control.message,
            action: control.action,
            width: control.width,
            height: control.height,
            code: control.code
        )
    }

    private static func validateEnvelope(_ data: Data) throws {
        guard !data.isEmpty else { throw ADFPEnvelopeError.empty }
        guard data.count <= maxEnvelopeBytes else { throw ADFPEnvelopeError.oversized }
        guard data.count >= 8 else { throw ADFPEnvelopeError.truncated }
        let bytes = [UInt8](data)
        guard bytes[4] == 0x41, bytes[5] == 0x44, bytes[6] == 0x45, bytes[7] == 0x4E else {
            throw ADFPEnvelopeError.wrongFileIdentifier
        }
        let root = Int(readUInt32(bytes, at: 0))
        guard root >= 8, root + 4 <= bytes.count else { throw ADFPEnvelopeError.truncated }
        let vtableStart = root - Int(readUInt32(bytes, at: root))
        guard vtableStart >= 0, vtableStart + 4 <= bytes.count else {
            throw ADFPEnvelopeError.truncated
        }
        let vtableSize = Int(readUInt16(bytes, at: vtableStart))
        guard vtableSize >= 4, vtableStart + vtableSize <= bytes.count else {
            throw ADFPEnvelopeError.truncated
        }
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func flatBufferType(for kind: InputEvent.Kind) throws -> AirDesk_Protocol__EventType {
        switch kind {
        case .pointerMove: return .pointerMove
        case .pointerDown: return .pointerDown
        case .pointerUp: return .pointerUp
        case .pointerClick: return .pointerClick
        case .pointerCancel: return .pointerCancel
        case .scroll: return .scroll
        case .keyDown: return .keyDown
        case .keyUp: return .keyUp
        case .textInput: return .textInput
        case .focusChanged: return .focusChanged
        case .viewportChanged: return .viewportChanged
        case .sessionStart, .sessionEnd: throw ADFPEnvelopeError.unsupportedEvent
        }
    }

    private static func inputKind(for type: AirDesk_Protocol__EventType) throws -> InputEvent.Kind {
        switch type {
        case .pointerMove: return .pointerMove
        case .pointerDown: return .pointerDown
        case .pointerUp: return .pointerUp
        case .pointerClick: return .pointerClick
        case .pointerCancel: return .pointerCancel
        case .scroll: return .scroll
        case .keyDown: return .keyDown
        case .keyUp: return .keyUp
        case .textInput: return .textInput
        case .focusChanged: return .focusChanged
        case .viewportChanged: return .viewportChanged
        }
    }
}
