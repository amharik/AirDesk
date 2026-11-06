import Foundation

enum IrohFabricChannel: UInt8, CaseIterable, Sendable {
    case control = 0
    case movement = 1
    case runtime = 2
    case resource = 3
    case display = 4
    case inputEdges = 0x81

    var isReliable: Bool { self != .movement }

    static func reliable(rawValue: UInt8) -> IrohFabricChannel? {
        guard let channel = IrohFabricChannel(rawValue: rawValue), channel.isReliable else {
            return nil
        }
        return channel
    }
}

enum IrohFabricMessage: Sendable {
    case reliable(channel: IrohFabricChannel, payload: Data)
    case movement(Data)
    case invalid(String)
}

struct IrohFabricFrame: Sendable, Equatable {
    static let maximumReliablePayload = 1_048_576
    static let movementPayloadSize = 16

    let channel: IrohFabricChannel
    let payload: Data

    init(channel: IrohFabricChannel, payload: Data) throws {
        guard channel.isReliable else {
            throw IrohFabricError.movementIsDatagramOnly
        }
        guard payload.count <= Self.maximumReliablePayload else {
            throw IrohFabricError.frameTooLarge
        }
        self.channel = channel
        self.payload = payload
    }

    init(movement payload: Data) throws {
        guard payload.count == Self.movementPayloadSize else {
            throw IrohFabricError.invalidMovementPayload
        }
        self.channel = .movement
        self.payload = payload
    }

    var encoded: Data {
        var data = Data([channel.rawValue])
        var length = UInt32(payload.count).bigEndian
        data.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
        data.append(payload)
        return data
    }
}

extension Data {
    func uint32BigEndian(at offset: Int = 0) -> UInt32 {
        let start = startIndex.advanced(by: offset)
        let end = start.advanced(by: MemoryLayout<UInt32>.size)
        return self[start..<end].reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

enum IrohFabricError: LocalizedError, Equatable {
    case invalidALPN
    case invalidIdentity
    case invalidRelayURLs
    case relayRequired
    case notStarted
    case invalidTicket
    case frameTooLarge
    case invalidMovementPayload
    case movementIsDatagramOnly
    case endpointClosed

    var errorDescription: String? {
        switch self {
        case .invalidALPN: return "Iroh ALPN must contain between 1 and 255 bytes."
        case .invalidIdentity: return "Iroh identity must be a 32-byte Ed25519 secret key."
        case .invalidRelayURLs: return "At least one HTTPS relay URL is required when relay support is enabled."
        case .relayRequired: return "This peer is reachable only through a relay, but relay use is disabled."
        case .notStarted: return "The Iroh transport has not been started."
        case .invalidTicket: return "The endpoint ticket is invalid."
        case .frameTooLarge: return "The reliable frame exceeds the 1 MiB limit."
        case .invalidMovementPayload: return "Movement datagrams must be exactly 16 bytes."
        case .movementIsDatagramOnly: return "Movement must be sent as a datagram, not a reliable stream."
        case .endpointClosed: return "The Iroh endpoint is closed."
        }
    }
}
