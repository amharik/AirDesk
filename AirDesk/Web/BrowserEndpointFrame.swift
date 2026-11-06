import Foundation

enum BrowserEndpointFrameOpcode: UInt8, Equatable, Sendable {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

struct BrowserEndpointFrame: Equatable, Sendable {
    static let maximumControlPayload = 125

    let opcode: BrowserEndpointFrameOpcode
    let payload: Data
    let fin: Bool

    init(opcode: BrowserEndpointFrameOpcode, payload: Data = Data(), fin: Bool = true) {
        self.opcode = opcode
        self.payload = payload
        self.fin = fin
    }

    static func text(_ payload: Data, fin: Bool = true) -> BrowserEndpointFrame {
        BrowserEndpointFrame(opcode: .text, payload: payload, fin: fin)
    }

    static func ping(_ payload: Data = Data()) -> BrowserEndpointFrame {
        BrowserEndpointFrame(opcode: .ping, payload: payload)
    }

    static func pong(_ payload: Data = Data()) -> BrowserEndpointFrame {
        BrowserEndpointFrame(opcode: .pong, payload: payload)
    }

    static func close(code: UInt16 = 1000, reason: String = "") -> BrowserEndpointFrame {
        var payload = Data()
        var networkCode = code.bigEndian
        withUnsafeBytes(of: &networkCode) { payload.append(contentsOf: $0) }
        var reasonData = Data(reason.utf8)
        if reasonData.count > maximumControlPayload - 2 {
            reasonData = reasonData.prefix(maximumControlPayload - 2)
        }
        payload.append(reasonData)
        return BrowserEndpointFrame(opcode: .close, payload: payload)
    }

    func encoded(masked: Bool) -> Data {
        var data = Data()
        var first = opcode.rawValue
        if fin { first |= 0x80 }
        data.append(first)

        let maskBit: UInt8 = masked ? 0x80 : 0
        if payload.count <= 125 {
            data.append(maskBit | UInt8(payload.count))
        } else if payload.count <= 65_535 {
            data.append(maskBit | 126)
            var length = UInt16(payload.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        } else {
            data.append(maskBit | 127)
            var length = UInt64(payload.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        }

        if masked {
            let key = (0..<4).map { _ in UInt8.random(in: 0...255) }
            data.append(contentsOf: key)
            var maskedPayload = Data(capacity: payload.count)
            for (index, byte) in payload.enumerated() {
                maskedPayload.append(byte ^ key[index % 4])
            }
            data.append(maskedPayload)
        } else {
            data.append(payload)
        }
        return data
    }
}

enum BrowserEndpointFrameError: LocalizedError, Equatable {
    case protocolViolation(String)
    case messageTooLarge
    case invalidUTF8
    case unsupportedData

    var errorDescription: String? {
        switch self {
        case .protocolViolation(let reason): return reason
        case .messageTooLarge: return "Browser endpoint WebSocket message exceeded the size limit."
        case .invalidUTF8: return "Browser endpoint WebSocket text was not valid UTF-8."
        case .unsupportedData: return "Browser endpoint WebSocket binary messages are not supported."
        }
    }

    var closeCode: UInt16 {
        switch self {
        case .protocolViolation: return 1002
        case .messageTooLarge: return 1009
        case .invalidUTF8: return 1007
        case .unsupportedData: return 1003
        }
    }
}

enum BrowserEndpointFrameParser {
    static func parse(
        from data: inout Data,
        expectedMasked: Bool,
        maximumPayload: Int
    ) throws -> BrowserEndpointFrame? {
        let start = data.startIndex
        guard data.count >= 2 else { return nil }

        let first = data[start]
        let second = data[start + 1]
        let fin = (first & 0x80) != 0
        guard (first & 0x70) == 0 else {
            throw BrowserEndpointFrameError.protocolViolation("WebSocket extensions are not supported.")
        }
        guard let opcode = BrowserEndpointFrameOpcode(rawValue: first & 0x0F) else {
            throw BrowserEndpointFrameError.protocolViolation("Unsupported WebSocket opcode.")
        }
        let masked = (second & 0x80) != 0
        guard masked == expectedMasked else {
            throw BrowserEndpointFrameError.protocolViolation(
                expectedMasked ? "Client WebSocket frames must be masked."
                    : "Server WebSocket frames must not be masked."
            )
        }

        let shortLength = Int(second & 0x7F)
        var offset = 2
        var payloadLength: Int
        if shortLength <= 125 {
            payloadLength = shortLength
        } else if shortLength == 126 {
            guard data.count >= offset + 2 else { return nil }
            let high = UInt16(data[start + offset])
            let low = UInt16(data[start + offset + 1])
            payloadLength = Int((high << 8) | low)
            offset += 2
        } else {
            guard data.count >= offset + 8 else { return nil }
            var value: UInt64 = 0
            for index in 0..<8 {
                value = (value << 8) | UInt64(data[start + offset + index])
            }
            guard value <= UInt64(Int.max) else {
                throw BrowserEndpointFrameError.messageTooLarge
            }
            payloadLength = Int(value)
            offset += 8
        }

        if opcode == .close || opcode == .ping || opcode == .pong {
            guard fin else {
                throw BrowserEndpointFrameError.protocolViolation("Control frames cannot be fragmented.")
            }
            guard payloadLength <= BrowserEndpointFrame.maximumControlPayload else {
                throw BrowserEndpointFrameError.protocolViolation("Control frame payload is too large.")
            }
        }
        guard payloadLength <= maximumPayload else {
            throw BrowserEndpointFrameError.messageTooLarge
        }

        var maskKey: [UInt8] = []
        if masked {
            guard data.count >= offset + 4 else { return nil }
            maskKey = (0..<4).map { data[start + offset + $0] }
            offset += 4
        }

        let totalLength = offset + payloadLength
        guard data.count >= totalLength else { return nil }

        var payload = Data(data[(start + offset)..<(start + totalLength)])
        if masked {
            for index in 0..<payload.count {
                payload[index] ^= maskKey[index % 4]
            }
        }
        data.removeSubrange(start..<(start + totalLength))

        return BrowserEndpointFrame(opcode: opcode, payload: payload, fin: fin)
    }
}
