import Foundation

enum PackedPointerFrameError: Error, Equatable {
    case invalidLength
    case invalidMagic
    case unsupportedVersion
    case unsupportedFlags
    case unsupportedEvent
    case invalidCoordinates
    case invalidButton
    case invalidClickCount
    case invalidDelta
    case invalidTimestamp
    case invalidSession
}

struct PackedPointerFrame: Equatable {
    static let version: UInt8 = 1
    static let headerBytes = 32
    static let pointerBytes = 44
    static let scrollBytes = 40

    let kind: AirDesk_Protocol__EventType
    let generation: UInt32
    let seq: UInt32
    let timestamp: UInt64
    let sessionTag: UInt64
    var x: Float?
    var y: Float?
    var button: UInt8?
    var clickCount: UInt8?
    var dx: Float?
    var dy: Float?

    init(
        kind: AirDesk_Protocol__EventType,
        generation: UInt32,
        seq: UInt32,
        timestamp: UInt64,
        sessionTag: UInt64,
        x: Float? = nil,
        y: Float? = nil,
        button: UInt8? = nil,
        clickCount: UInt8? = nil,
        dx: Float? = nil,
        dy: Float? = nil
    ) {
        self.kind = kind
        self.generation = generation
        self.seq = seq
        self.timestamp = timestamp
        self.sessionTag = sessionTag
        self.x = x
        self.y = y
        self.button = button
        self.clickCount = clickCount
        self.dx = dx
        self.dy = dy
    }

    static func sessionTag(for sessionId: String) throws -> UInt64 {
        guard !sessionId.isEmpty, sessionId.utf8.count <= 64 else {
            throw PackedPointerFrameError.invalidSession
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in sessionId.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    func encoded() throws -> Data {
        let rawKind = kind.rawValue
        guard rawKind <= 5 else {
            throw PackedPointerFrameError.unsupportedEvent
        }
        guard timestamp > 0 else { throw PackedPointerFrameError.invalidTimestamp }

        let length: Int
        switch rawKind {
        case 0...3: length = Self.pointerBytes
        case 5: length = Self.scrollBytes
        default: length = Self.headerBytes
        }

        var data = Data(capacity: length)
        data.append(0x41)
        data.append(0x44)
        data.append(Self.version)
        data.append(rawKind)
        data.append(contentsOf: [0, 0, 0, 0])
        append(generation, to: &data)
        append(seq, to: &data)
        append(timestamp, to: &data)
        append(sessionTag, to: &data)

        if (0...3).contains(Int(rawKind)) {
            let x = try normalized(x)
            let y = try normalized(y)
            guard let button, button <= 4 else { throw PackedPointerFrameError.invalidButton }
            guard let clickCount, clickCount >= 1, clickCount <= 3 else {
                throw PackedPointerFrameError.invalidClickCount
            }
            append(x.bitPattern, to: &data)
            append(y.bitPattern, to: &data)
            data.append(button)
            data.append(clickCount)
            append(UInt16(0), to: &data)
        } else if rawKind == 5 {
            guard let dx, let dy, dx.isFinite, dy.isFinite,
                  abs(dx) <= 20_000, abs(dy) <= 20_000 else {
                throw PackedPointerFrameError.invalidDelta
            }
            append(dx.bitPattern, to: &data)
            append(dy.bitPattern, to: &data)
        }

        return data
    }

    static func decode(_ data: Data) throws -> PackedPointerFrame {
        guard data.count >= headerBytes else { throw PackedPointerFrameError.invalidLength }
        guard data[0] == 0x41, data[1] == 0x44 else { throw PackedPointerFrameError.invalidMagic }
        guard data[2] == version else { throw PackedPointerFrameError.unsupportedVersion }
        guard data[4] == 0, data[5] == 0, data[6] == 0, data[7] == 0 else {
            throw PackedPointerFrameError.unsupportedFlags
        }
        guard let kind = AirDesk_Protocol__EventType(rawValue: data[3]),
              data[3] <= 5 else {
            throw PackedPointerFrameError.unsupportedEvent
        }

        let generation = readUInt32(data, 8)
        let seq = readUInt32(data, 12)
        let timestamp = readUInt64(data, 16)
        let sessionTag = readUInt64(data, 24)
        guard timestamp > 0 else { throw PackedPointerFrameError.invalidTimestamp }

        var frame = PackedPointerFrame(
            kind: kind,
            generation: generation,
            seq: seq,
            timestamp: timestamp,
            sessionTag: sessionTag
        )

        switch data[3] {
        case 0...3:
            guard data.count == pointerBytes else { throw PackedPointerFrameError.invalidLength }
            let x = Float(bitPattern: readUInt32(data, 32))
            let y = Float(bitPattern: readUInt32(data, 36))
            guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
                throw PackedPointerFrameError.invalidCoordinates
            }
            guard data[40] <= 4 else { throw PackedPointerFrameError.invalidButton }
            guard data[41] >= 1, data[41] <= 3, readUInt16(data, 42) == 0 else {
                throw PackedPointerFrameError.invalidClickCount
            }
            frame.x = x
            frame.y = y
            frame.button = data[40]
            frame.clickCount = data[41]
        case 5:
            guard data.count == scrollBytes else { throw PackedPointerFrameError.invalidLength }
            let dx = Float(bitPattern: readUInt32(data, 32))
            let dy = Float(bitPattern: readUInt32(data, 36))
            guard dx.isFinite, dy.isFinite, abs(dx) <= 20_000, abs(dy) <= 20_000 else {
                throw PackedPointerFrameError.invalidDelta
            }
            frame.dx = dx
            frame.dy = dy
        default:
            guard data.count == headerBytes else { throw PackedPointerFrameError.invalidLength }
        }

        return frame
    }

    private func normalized(_ value: Float?) throws -> Float {
        guard let value, value.isFinite, (0...1).contains(value) else {
            throw PackedPointerFrameError.invalidCoordinates
        }
        return value
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(data[offset + index]) << UInt32(index * 8)
        }
        return value
    }

    private static func readUInt64(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        return value
    }
}
