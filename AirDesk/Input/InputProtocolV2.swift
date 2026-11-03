import Foundation

enum InputProtocolVersion: Int, CaseIterable, Sendable {
    case legacy = 1
    case packedMovement = 12
}

struct InputProtocolOffer: Equatable, Sendable {
    var versions: Set<Int>
    var packedVersions: Set<Int>
    var supportsReliableEdgeChannel: Bool

    static let current = InputProtocolOffer(
        versions: [InputProtocolVersion.legacy.rawValue, InputProtocolVersion.packedMovement.rawValue],
        packedVersions: [PackedMovementFrame.version],
        supportsReliableEdgeChannel: true
    )

    static let legacyOnly = InputProtocolOffer(
        versions: [InputProtocolVersion.legacy.rawValue],
        packedVersions: [],
        supportsReliableEdgeChannel: false
    )
}

struct NegotiatedInputProtocol: Equatable, Sendable {
    var version: InputProtocolVersion
    var packedVersion: Int?
    var usesReliableEdgeChannel: Bool
}

enum InputProtocolError: Error, Equatable, LocalizedError {
    case noCommonVersion
    case noCommonPackedVersion
    case reliableEdgeChannelRequired
    case edgeOnMovementChannel
    case unknownMultiplexedFrame
    case packedFormatNotNegotiated
    case unauthenticatedConnection
    case sessionMismatch
    case generationMismatch(expected: UInt64, received: UInt64)
    case epochRejected(currentEpoch: UInt64, received: UInt64)
    case controllerMismatch
    case invalidCoordinates

    var errorDescription: String? {
        switch self {
        case .noCommonVersion:
            return "No common input protocol version."
        case .noCommonPackedVersion:
            return "No common packed movement version."
        case .reliableEdgeChannelRequired:
            return "The peer does not support the reliable input edge channel."
        case .edgeOnMovementChannel:
            return "Input edges cannot be sent on the movement channel."
        case .unknownMultiplexedFrame:
            return "The multiplexed input frame is not a recognized movement frame or ADFP envelope."
        case .packedFormatNotNegotiated:
            return "The packed movement format was not negotiated."
        case .unauthenticatedConnection:
            return "Input requires an authenticated connection."
        case .sessionMismatch:
            return "Input belongs to a different session."
        case .generationMismatch(let expected, let received):
            return "Input generation \(received) does not match session generation \(expected)."
        case .epochRejected(let currentEpoch, let received):
            return "Input lease epoch \(received) is stale; current epoch is \(currentEpoch)."
        case .controllerMismatch:
            return "Input belongs to a different controller."
        case .invalidCoordinates:
            return "Input coordinates are outside the normalized desktop bounds."
        }
    }
}

enum InputTransportChannel: String, CaseIterable, Sendable {
    case control
    case reliableEdges = "reliable-edges"
    case movement
    case runtime
    case resource
}

enum MultiplexedInputFrame: Equatable, Sendable {
    case packedMovement
    case flatBufferEnvelope
}

enum InputProtocolNegotiator {
    static func negotiate(
        local: InputProtocolOffer,
        remote: InputProtocolOffer
    ) throws -> NegotiatedInputProtocol {
        let common = local.versions.intersection(remote.versions)
        if common.contains(InputProtocolVersion.packedMovement.rawValue),
           local.packedVersions.contains(PackedMovementFrame.version),
           remote.packedVersions.contains(PackedMovementFrame.version) {
            guard local.supportsReliableEdgeChannel, remote.supportsReliableEdgeChannel else {
                throw InputProtocolError.reliableEdgeChannelRequired
            }
            return NegotiatedInputProtocol(
                version: .packedMovement,
                packedVersion: PackedMovementFrame.version,
                usesReliableEdgeChannel: true
            )
        }

        guard common.contains(InputProtocolVersion.legacy.rawValue) else {
            throw InputProtocolError.noCommonVersion
        }
        return NegotiatedInputProtocol(
            version: .legacy,
            packedVersion: nil,
            usesReliableEdgeChannel: false
        )
    }
}

enum InputChannelRouter {
    static func route(_ event: InputEvent) throws -> InputTransportChannel {
        switch event.type {
        case .pointerMove:
            return .movement
        case .pointerDown, .pointerUp, .pointerClick, .pointerCancel,
             .scroll, .keyDown, .keyUp, .textInput, .focusChanged:
            return .reliableEdges
        case .viewportChanged, .sessionStart, .sessionEnd:
            return .control
        }
    }

    static func validate(_ event: InputEvent, on channel: InputTransportChannel) throws {
        if channel == .movement, try route(event) != .movement {
            throw InputProtocolError.edgeOnMovementChannel
        }
    }

    static func classifyMultiplexed(
        _ data: Data,
        negotiated: NegotiatedInputProtocol
    ) throws -> MultiplexedInputFrame {
        guard !data.isEmpty else { throw InputProtocolError.unknownMultiplexedFrame }
        if data[0] == PackedMovementFrame.magic {
            guard negotiated.packedVersion == PackedMovementFrame.version else {
                throw InputProtocolError.packedFormatNotNegotiated
            }
            return .packedMovement
        }
        guard data.count >= 8,
              data[4] == 0x41, data[5] == 0x44, data[6] == 0x45, data[7] == 0x4E else {
            throw InputProtocolError.unknownMultiplexedFrame
        }
        return .flatBufferEnvelope
    }
}

struct InputConnectionContext: Equatable, Sendable {
    var sessionId: String
    var generation: UInt64
    var deviceId: String
    var controllerId: String
    var leaseEpoch: UInt64
    var authenticated: Bool

    init(
        sessionId: String,
        generation: UInt64,
        deviceId: String,
        controllerId: String,
        leaseEpoch: UInt64,
        authenticated: Bool = true
    ) {
        self.sessionId = sessionId
        self.generation = generation
        self.deviceId = deviceId
        self.controllerId = controllerId
        self.leaseEpoch = leaseEpoch
        self.authenticated = authenticated
    }
}

struct ValidatedInputEdge: Equatable, Sendable {
    var event: InputEvent
    var context: InputConnectionContext
}

enum InputContextResolver {
    static func resolve(
        _ event: InputEvent,
        on context: InputConnectionContext
    ) throws -> ValidatedInputEdge {
        guard context.authenticated else {
            throw InputProtocolError.unauthenticatedConnection
        }
        guard event.sessionId == context.sessionId else {
            throw InputProtocolError.sessionMismatch
        }
        if let generation = event.generation {
            let received = UInt64(max(generation, 0))
            guard received == context.generation else {
                throw InputProtocolError.generationMismatch(
                    expected: context.generation,
                    received: received
                )
            }
        }
        return ValidatedInputEdge(event: event, context: context)
    }

    static func resolveMovement(
        _ frame: PackedMovementFrame,
        on context: InputConnectionContext
    ) throws -> PackedMovementFrame {
        guard context.authenticated else {
            throw InputProtocolError.unauthenticatedConnection
        }
        guard UInt16(truncatingIfNeeded: context.leaseEpoch) == frame.leaseEpochLow else {
            throw InputProtocolError.epochRejected(
                currentEpoch: context.leaseEpoch,
                received: UInt64(frame.leaseEpochLow)
            )
        }
        guard (0...1).contains(frame.x), (0...1).contains(frame.y) else {
            throw InputProtocolError.invalidCoordinates
        }
        return frame
    }
}

struct InputLatencyProbe: Equatable, Sendable {
    var id: UInt64
    var sentAt: Date
}

final class InputLatencyProbeTracker {
    private var nextID: UInt64 = 1
    private var pending: [UInt64: Date] = [:]
    private(set) var lastLatency: TimeInterval?

    func begin(now: Date = Date()) -> InputLatencyProbe {
        let probe = InputLatencyProbe(id: nextID, sentAt: now)
        nextID += 1
        pending[probe.id] = now
        return probe
    }

    @discardableResult
    func complete(_ probe: InputLatencyProbe, echoAt: Date = Date()) -> TimeInterval? {
        guard let sentAt = pending.removeValue(forKey: probe.id) else { return nil }
        let latency = max(0, echoAt.timeIntervalSince(sentAt))
        lastLatency = latency
        return latency
    }
}
