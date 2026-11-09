import Foundation

struct IrohFabricInputPacket: Sendable, Equatable {
    let channel: IrohFabricChannel
    let payload: Data
}

enum IrohFabricInputCodec {
    static func encode(
        _ event: InputEvent,
        header: ADFPHeader? = nil,
        now: Date = Date()
    ) throws -> IrohFabricInputPacket {
        let channel = try InputChannelRouter.route(event)
        switch channel {
        case .movement:
            guard let x = event.x, let y = event.y else {
                throw InputEventError.invalidCoordinates
            }
            let frame = PackedMovementFrame(
                leaseEpochLow: UInt16(truncatingIfNeeded: event.generation ?? 0),
                seq: UInt32(clamping: event.seq),
                x: Float(x),
                y: Float(y)
            )
            return IrohFabricInputPacket(channel: .movement, payload: try frame.encoded())
        case .reliableEdges:
            return IrohFabricInputPacket(
                channel: .inputEdges,
                payload: try encodeEnvelope(event, header: header, now: now)
            )
        case .control:
            return IrohFabricInputPacket(
                channel: .control,
                payload: try encodeEnvelope(event, header: header, now: now)
            )
        case .runtime:
            return IrohFabricInputPacket(
                channel: .runtime,
                payload: try encodeEnvelope(event, header: header, now: now)
            )
        case .resource:
            return IrohFabricInputPacket(
                channel: .resource,
                payload: try encodeEnvelope(event, header: header, now: now)
            )
        }
    }

    static func decodeReliable(_ message: IrohFabricMessage, now: Date = Date()) throws -> InputEvent? {
        guard case .reliable(let channel, let payload) = message else { return nil }
        guard channel == .inputEdges || channel == .control else { return nil }
        let envelope = try ADFPEnvelopeCodec.decode(payload, now: now)
        guard case .input(let event) = envelope.payload else { return nil }
        return try event.validated()
    }

    private static func encodeEnvelope(
        _ event: InputEvent,
        header: ADFPHeader?,
        now: Date
    ) throws -> Data {
        guard let header else { throw ADFPEnvelopeError.headerMissing }
        return try ADFPEnvelopeCodec.encodeInput(event, header: header, now: now)
    }

    static func decodeMovement(
        _ message: IrohFabricMessage,
        sessionId: String,
        generation: Int
    ) throws -> InputEvent? {
        guard case .movement(let payload) = message else { return nil }
        let frame = try PackedMovementFrame.decode(payload)
        return InputEvent.make(
            .pointerMove,
            sessionId: sessionId,
            generation: generation,
            seq: Int(frame.seq),
            x: Double(frame.x),
            y: Double(frame.y)
        )
    }
}
