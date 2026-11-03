import Foundation

struct MovementModifiers: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let shift = MovementModifiers(rawValue: 1 << 0)
    static let option = MovementModifiers(rawValue: 1 << 1)
    static let command = MovementModifiers(rawValue: 1 << 2)

    static let all: MovementModifiers = [.shift, .option, .command]

    init(rawValue: UInt8) {
        self.rawValue = rawValue & 0b111
    }
}

struct PackedMovementFrame: Equatable, Sendable {
    static let magic: UInt8 = 0xA5
    static let byteCount = 16
    static let version = 12

    let leaseEpochLow: UInt16
    let seq: UInt32
    let x: Float
    let y: Float
    let buttonMask: UInt8
    let modifiers: MovementModifiers

    init(
        leaseEpochLow: UInt16,
        seq: UInt32,
        x: Float,
        y: Float,
        buttonMask: UInt8 = 0,
        modifiers: MovementModifiers = []
    ) {
        self.leaseEpochLow = leaseEpochLow
        self.seq = seq
        self.x = x
        self.y = y
        self.buttonMask = buttonMask
        self.modifiers = modifiers
    }

    func encoded() throws -> Data {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw PackedMovementFrameError.invalidCoordinates
        }
        guard buttonMask <= 0b111 else {
            throw PackedMovementFrameError.invalidButtonMask
        }

        let flags = (buttonMask << 2) | ((modifiers.rawValue & 0b111) << 5)
        var data = Data(capacity: Self.byteCount)
        data.append(Self.magic)
        data.append(flags)
        append(leaseEpochLow, to: &data)
        append(seq, to: &data)
        append(x.bitPattern, to: &data)
        append(y.bitPattern, to: &data)
        return data
    }

    static func decode(_ data: Data, negotiated: Bool = true) throws -> PackedMovementFrame {
        guard negotiated else {
            throw PackedMovementFrameError.packedFormatNotNegotiated
        }
        guard data.count == byteCount else {
            throw PackedMovementFrameError.invalidLength
        }
        guard data[0] == magic else {
            throw PackedMovementFrameError.invalidMagic
        }

        let flags = data[1]
        guard flags & 0b11 == 0 else {
            throw PackedMovementFrameError.edgeNotAllowed
        }
        let buttonMask = (flags >> 2) & 0b111
        let modifiers = MovementModifiers(rawValue: (flags >> 5) & 0b111)

        let x = Float(bitPattern: readUInt32(data, 8))
        let y = Float(bitPattern: readUInt32(data, 12))
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw PackedMovementFrameError.invalidCoordinates
        }

        return PackedMovementFrame(
            leaseEpochLow: readUInt16(data, 2),
            seq: readUInt32(data, 4),
            x: x,
            y: y,
            buttonMask: buttonMask,
            modifiers: modifiers
        )
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
}

enum PackedMovementFrameError: Error, Equatable, LocalizedError {
    case invalidLength
    case invalidMagic
    case edgeNotAllowed
    case invalidCoordinates
    case invalidButtonMask
    case packedFormatNotNegotiated

    var errorDescription: String? {
        switch self {
        case .invalidLength:
            return "Packed movement frame must be exactly 16 bytes."
        case .invalidMagic:
            return "Packed movement frame has an unknown magic byte."
        case .edgeNotAllowed:
            return "Packed movement frames cannot carry input edges."
        case .invalidCoordinates:
            return "Packed movement frame has invalid coordinates."
        case .invalidButtonMask:
            return "Packed movement frame has an invalid button mask."
        case .packedFormatNotNegotiated:
            return "Packed movement format was not negotiated for this connection."
        }
    }
}
