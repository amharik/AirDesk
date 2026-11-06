import Foundation

struct IrohFabricInputPacket: Sendable, Equatable {
    let channel: IrohFabricChannel
    let payload: Data
}

enum IrohFabricInputCodec {
    static func encode(_ event: InputEvent) throws -> IrohFabricInputPacket {
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
            return IrohFabricInputPacket(channel: .inputEdges, payload: try JSONEncoder().encode(event))
        case .control:
            return IrohFabricInputPacket(channel: .control, payload: try JSONEncoder().encode(event))
        case .runtime:
            return IrohFabricInputPacket(channel: .runtime, payload: try JSONEncoder().encode(event))
        case .resource:
            return IrohFabricInputPacket(channel: .resource, payload: try JSONEncoder().encode(event))
        }
    }

    static func decodeReliable(_ message: IrohFabricMessage) throws -> InputEvent? {
        guard case .reliable(let channel, let payload) = message else { return nil }
        guard channel == .inputEdges || channel == .control else { return nil }
        let event = try JSONDecoder().decode(InputEvent.self, from: payload)
        return try event.validated()
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
