import Foundation
import OpenSSL

enum NativeP256Error: Swift.Error, Equatable, LocalizedError {
    case invalidLength(String)
    case invalidPoint(String)
    case identityPoint(String)
    case invalidScalar(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidLength(let detail): return "InvalidLength: \(detail)"
        case .invalidPoint(let detail): return "InvalidPoint: \(detail)"
        case .identityPoint(let detail): return "IdentityPoint: \(detail)"
        case .invalidScalar(let detail): return "InvalidScalar: \(detail)"
        case .operationFailed(let detail): return "OperationFailed: \(detail)"
        }
    }
}

final class NativeP256Group {
    static let prime256v1NID = Int32(415)
    static let scalarBytes = 32
    static let uncompressedPointBytes = 65

    let group: OpaquePointer
    private let order: OpaquePointer
    private let context: OpaquePointer

    init() throws {
        guard let group = EC_GROUP_new_by_curve_name(Self.prime256v1NID) else {
            throw NativeP256Error.operationFailed("could not create P-256 group")
        }
        guard let order = BN_new(), let context = BN_CTX_new() else {
            EC_GROUP_free(group)
            throw NativeP256Error.operationFailed("could not allocate P-256 order")
        }
        guard EC_GROUP_get_order(group, order, context) == 1 else {
            BN_free(order)
            BN_CTX_free(context)
            EC_GROUP_free(group)
            throw NativeP256Error.operationFailed("could not read P-256 order")
        }
        self.group = group
        self.order = order
        self.context = context
    }

    deinit {
        BN_free(order)
        BN_CTX_free(context)
        EC_GROUP_free(group)
    }

    func generator() throws -> NativeP256Point {
        guard let raw = EC_POINT_new(group) else {
            throw NativeP256Error.operationFailed("could not allocate P-256 point")
        }
        guard EC_POINT_mul(group, raw, BN_value_one(), nil, nil, context) == 1 else {
            EC_POINT_free(raw)
            throw NativeP256Error.operationFailed("could not derive P-256 generator")
        }
        return NativeP256Point(group: self, point: raw)
    }

    func decode(_ data: Data, requireUncompressed: Bool = true) throws -> NativeP256Point {
        if data == Data([0x00]) {
            throw NativeP256Error.identityPoint("point is the identity")
        }
        if requireUncompressed {
            guard data.count == Self.uncompressedPointBytes, data.first == 0x04 else {
                throw NativeP256Error.invalidLength("point must be an uncompressed SEC1 P-256 point")
            }
        }
        guard let raw = EC_POINT_new(group) else {
            throw NativeP256Error.operationFailed("could not allocate P-256 point")
        }
        let decoded = data.withUnsafeBytes { bytes in
            EC_POINT_oct2point(
                group,
                raw,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                data.count,
                context
            )
        }
        guard decoded == 1 else {
            EC_POINT_free(raw)
            throw NativeP256Error.invalidPoint("point is not on P-256")
        }
        guard EC_POINT_is_at_infinity(group, raw) == 0 else {
            EC_POINT_free(raw)
            throw NativeP256Error.identityPoint("point is the identity")
        }
        guard EC_POINT_is_on_curve(group, raw, context) == 1 else {
            EC_POINT_free(raw)
            throw NativeP256Error.invalidPoint("point is not on P-256")
        }
        return NativeP256Point(group: self, point: raw)
    }

    func isInfinity(_ point: NativeP256Point) -> Bool {
        EC_POINT_is_at_infinity(group, point.point) == 1
    }

    func encode(_ point: NativeP256Point) throws -> Data {
        try withExtendedLifetime(self) {
            guard EC_POINT_is_at_infinity(group, point.point) == 0 else {
                throw NativeP256Error.identityPoint("point is the identity")
            }
            let length = EC_POINT_point2oct(
                group,
                point.point,
                POINT_CONVERSION_UNCOMPRESSED,
                nil,
                0,
                context
            )
            guard length == Self.uncompressedPointBytes else {
                throw NativeP256Error.invalidPoint("point did not encode as uncompressed P-256")
            }
            var bytes = [UInt8](repeating: 0, count: length)
            let written = bytes.withUnsafeMutableBufferPointer { buffer in
                EC_POINT_point2oct(
                    group,
                    point.point,
                    POINT_CONVERSION_UNCOMPRESSED,
                    buffer.baseAddress,
                    length,
                    context
                )
            }
            guard written == length else {
                throw NativeP256Error.operationFailed("could not encode P-256 point")
            }
            return Data(bytes)
        }
    }

    func multiply(_ point: NativeP256Point, by scalar: Data, allowZero: Bool = false) throws -> NativeP256Point {
        let value = try scalarBIGNUM(scalar, allowZero: allowZero)
        defer { BN_clear_free(value) }
        guard let raw = EC_POINT_new(group) else {
            throw NativeP256Error.operationFailed("could not allocate P-256 point")
        }
        guard EC_POINT_mul(group, raw, nil, point.point, value, context) == 1 else {
            EC_POINT_free(raw)
            throw NativeP256Error.operationFailed("could not multiply P-256 point")
        }
        return NativeP256Point(group: self, point: raw)
    }

    func add(_ left: NativeP256Point, _ right: NativeP256Point) throws -> NativeP256Point {
        guard let raw = EC_POINT_new(group) else {
            throw NativeP256Error.operationFailed("could not allocate P-256 point")
        }
        guard EC_POINT_add(group, raw, left.point, right.point, context) == 1 else {
            EC_POINT_free(raw)
            throw NativeP256Error.operationFailed("could not add P-256 points")
        }
        return NativeP256Point(group: self, point: raw)
    }

    func subtract(_ left: NativeP256Point, _ right: NativeP256Point) throws -> NativeP256Point {
        guard let negated = EC_POINT_dup(right.point, group) else {
            throw NativeP256Error.operationFailed("could not copy P-256 point")
        }
        guard EC_POINT_invert(group, negated, context) == 1 else {
            EC_POINT_free(negated)
            throw NativeP256Error.operationFailed("could not negate P-256 point")
        }
        guard let raw = EC_POINT_new(group) else {
            EC_POINT_free(negated)
            throw NativeP256Error.operationFailed("could not allocate P-256 point")
        }
        guard EC_POINT_add(group, raw, left.point, negated, context) == 1 else {
            EC_POINT_free(negated)
            EC_POINT_free(raw)
            throw NativeP256Error.operationFailed("could not subtract P-256 points")
        }
        EC_POINT_free(negated)
        return NativeP256Point(group: self, point: raw)
    }

    func linearCombination(
        generatorScalar: Data?,
        point: NativeP256Point?,
        pointScalar: Data?
    ) throws -> NativeP256Point {
        let generatorValue = try generatorScalar.map { try scalarBIGNUM($0, allowZero: true) }
        let pointValue = try pointScalar.map { try scalarBIGNUM($0, allowZero: true) }
        defer {
            if let generatorValue { BN_clear_free(generatorValue) }
            if let pointValue { BN_clear_free(pointValue) }
        }
        guard let raw = EC_POINT_new(group) else {
            throw NativeP256Error.operationFailed("could not allocate P-256 point")
        }
        let result = EC_POINT_mul(
            group,
            raw,
            generatorValue,
            point?.point,
            pointValue,
            context
        )
        guard result == 1 else {
            EC_POINT_free(raw)
            throw NativeP256Error.operationFailed("could not compute P-256 linear combination")
        }
        return NativeP256Point(group: self, point: raw)
    }

    private func scalarBIGNUM(_ scalar: Data, allowZero: Bool) throws -> OpaquePointer {
        guard scalar.count == Self.scalarBytes else {
            throw NativeP256Error.invalidLength("scalar must be 32 bytes")
        }
        let bytes = [UInt8](scalar)
        guard let value = bytes.withUnsafeBufferPointer({
            BN_bin2bn($0.baseAddress, Int32(bytes.count), nil)
        }) else {
            throw NativeP256Error.operationFailed("could not allocate scalar")
        }
        let isZero = BN_num_bits(value) == 0
        if (!allowZero && isZero) || BN_cmp(value, order) >= 0 {
            BN_clear_free(value)
            throw NativeP256Error.invalidScalar("scalar is out of range")
        }
        return value
    }
}

final class NativeP256Point {
    fileprivate let group: NativeP256Group
    let point: OpaquePointer

    fileprivate init(group: NativeP256Group, point: OpaquePointer) {
        self.group = group
        self.point = point
    }

    deinit {
        EC_POINT_free(point)
    }
}
