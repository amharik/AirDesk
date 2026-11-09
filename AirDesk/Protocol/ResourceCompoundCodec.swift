import FlatBuffers
import Foundation

enum ResourceCompoundError: Error, Equatable, LocalizedError {
    case invalidFlatBuffer
    case wrongOpCode
    case wrongPayload
    case missingPayload
    case unsupportedBlobVersion
    case unsupportedBlobAlgorithm
    case invalidBlobDigest
    case invalidBlobLength
    case inlineTooLarge
    case ambiguousPayload
    case invalidPathSegment
    case tooManyPathSegments

    var errorDescription: String? {
        switch self {
        case .invalidFlatBuffer: return "invalid resource FlatBuffer."
        case .wrongOpCode: return "expected resource compound op code."
        case .wrongPayload: return "expected resource compound payload."
        case .missingPayload: return "missing resource payload."
        case .unsupportedBlobVersion: return "unsupported blob handle version."
        case .unsupportedBlobAlgorithm: return "unsupported blob digest algorithm."
        case .invalidBlobDigest: return "blake3 digest must be 32 bytes."
        case .invalidBlobLength: return "invalid blob length."
        case .inlineTooLarge: return "inline result exceeds 64 KiB; return a blob handle."
        case .ambiguousPayload: return "result cannot carry both inline data and a blob handle."
        case .invalidPathSegment: return "invalid path segment."
        case .tooManyPathSegments: return "too many path segments."
        }
    }
}

struct ResourceQid: Equatable {
    var type: UInt8
    var version: UInt32
    var path: UInt64
}

struct ResourceBlobHandle: Equatable {
    var version: UInt32
    var algorithm: AirDesk_Protocol__BlobAlgorithm
    var digest: Data
    var length: UInt64
    var expiresAt: UInt64
}

struct ResourceStatInfo: Equatable {
    var qid: ResourceQid?
    var mode: UInt32
    var length: UInt64
    var name: String
    var modifiedAt: UInt64
}

struct ResourceCompoundRequestPayload: Equatable {
    var requestId: UInt64
    var fid: UInt32
    var newFid: UInt32
    var wnames: [String]
    var openMode: AirDesk_Protocol__BindMode
    var readOffset: UInt64
    var readCount: UInt32
    var clunk: Bool
}

struct ResourceCompoundResultPayload: Equatable {
    var requestId: UInt64
    var status: AirDesk_Protocol__ResourceStatus
    var qid: ResourceQid?
    var iounit: UInt32
    var data: Data
    var blob: ResourceBlobHandle?
    var stat: ResourceStatInfo?
    var clunkStatus: AirDesk_Protocol__ResourceStatus
}

struct ResourceReadResultPayload: Equatable {
    var data: Data
    var blob: ResourceBlobHandle?
}

enum ResourceCompoundCodec {
    static let inlineLimit = 64 * 1024
    static let blobHandleVersion: UInt32 = 1
    static let blake3DigestBytes = 32
    static let maxPathSegments = 32
    static let maxPathSegmentBytes = 255

    static let defaultQid = ResourceQid(type: 0, version: 0, path: 0)

    static func validatePathSegments(_ wnames: [String]) throws {
        guard wnames.count <= maxPathSegments else { throw ResourceCompoundError.tooManyPathSegments }
        for name in wnames {
            guard !name.isEmpty,
                  name.utf8.count <= maxPathSegmentBytes,
                  name != ".",
                  name != "..",
                  !name.contains("/")
            else {
                throw ResourceCompoundError.invalidPathSegment
            }
        }
    }

    static func validateBlobHandle(_ handle: ResourceBlobHandle) throws {
        guard handle.version == blobHandleVersion else {
            throw ResourceCompoundError.unsupportedBlobVersion
        }
        guard handle.algorithm == .blake3 else {
            throw ResourceCompoundError.unsupportedBlobAlgorithm
        }
        guard handle.digest.count == blake3DigestBytes else {
            throw ResourceCompoundError.invalidBlobDigest
        }
        guard handle.length > 0 else { throw ResourceCompoundError.invalidBlobLength }
    }

    static func validateCompoundRequest(_ request: ResourceCompoundRequestPayload) throws {
        try validatePathSegments(request.wnames)
    }

    static func validateCompoundResult(_ result: ResourceCompoundResultPayload) throws {
        guard result.data.count <= inlineLimit else { throw ResourceCompoundError.inlineTooLarge }
        guard result.data.isEmpty || result.blob == nil else {
            throw ResourceCompoundError.ambiguousPayload
        }
        if let blob = result.blob {
            try validateBlobHandle(blob)
        }
    }

    static func validateReadResult(_ result: ResourceReadResultPayload) throws {
        guard result.data.count <= inlineLimit else { throw ResourceCompoundError.inlineTooLarge }
        guard result.data.isEmpty || result.blob == nil else {
            throw ResourceCompoundError.ambiguousPayload
        }
        if let blob = result.blob {
            try validateBlobHandle(blob)
        }
    }

    static func encodeCompoundRequest(_ request: ResourceCompoundRequestPayload) throws -> Data {
        try validateCompoundRequest(request)

        var builder = FlatBufferBuilder(initialSize: 1024)
        let segmentOffsets = request.wnames.map { builder.create(string: $0) }
        let wnames = builder.createVector(ofOffsets: segmentOffsets)
        let payload = AirDesk_Protocol__ResourceCompoundRequest.createResourceCompoundRequest(
            &builder,
            requestId: request.requestId,
            fid: request.fid,
            newFid: request.newFid,
            wnamesVectorOffset: wnames,
            openMode: request.openMode,
            readOffset: request.readOffset,
            readCount: request.readCount,
            clunk: request.clunk
        )
        return try finish(
            builder: &builder,
            payloadType: .resourcecompoundrequest,
            payload: payload,
            opCode: .compound
        )
    }

    static func decodeCompoundRequest(_ data: Data) throws -> ResourceCompoundRequestPayload {
        let rpc = try root(data)
        guard rpc.opCode == .compound else { throw ResourceCompoundError.wrongOpCode }
        guard rpc.payloadType == .resourcecompoundrequest else {
            throw ResourceCompoundError.wrongPayload
        }
        guard let request = rpc.payload(type: AirDesk_Protocol__ResourceCompoundRequest.self) else {
            throw ResourceCompoundError.missingPayload
        }

        var wnames: [String] = []
        for name in request.wnames {
            guard let name else { throw ResourceCompoundError.invalidPathSegment }
            wnames.append(name)
        }
        let decoded = ResourceCompoundRequestPayload(
            requestId: request.requestId,
            fid: request.fid,
            newFid: request.newFid,
            wnames: wnames,
            openMode: request.openMode,
            readOffset: request.readOffset,
            readCount: request.readCount,
            clunk: request.clunk
        )
        try validateCompoundRequest(decoded)
        return decoded
    }

    static func encodeCompoundResult(_ result: ResourceCompoundResultPayload) throws -> Data {
        try validateCompoundResult(result)

        var builder = FlatBufferBuilder(initialSize: 1024)
        let dataOffset = result.data.isEmpty ? Offset() : builder.createVector(bytes: result.data)
        let blobOffset = try result.blob.map { try createBlobHandle($0, builder: &builder) } ?? Offset()
        let statOffset = result.stat.map { createStat($0, builder: &builder) } ?? Offset()
        let qid = result.qid ?? defaultQid
        let payload = AirDesk_Protocol__ResourceCompoundResult.createResourceCompoundResult(
            &builder,
            requestId: result.requestId,
            status: result.status,
            qid: AirDesk_Protocol__Qid(type: qid.type, version: qid.version, path: qid.path),
            iounit: result.iounit,
            dataVectorOffset: dataOffset,
            blobOffset: blobOffset,
            statOffset: statOffset,
            clunkStatus: result.clunkStatus
        )
        return try finish(
            builder: &builder,
            payloadType: .resourcecompoundresult,
            payload: payload,
            opCode: .compoundResult
        )
    }

    static func decodeCompoundResult(_ data: Data) throws -> ResourceCompoundResultPayload {
        let rpc = try root(data)
        guard rpc.opCode == .compoundResult else { throw ResourceCompoundError.wrongOpCode }
        guard rpc.payloadType == .resourcecompoundresult else {
            throw ResourceCompoundError.wrongPayload
        }
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceCompoundResult.self) else {
            throw ResourceCompoundError.missingPayload
        }

        let decoded = ResourceCompoundResultPayload(
            requestId: result.requestId,
            status: result.status,
            qid: result.qid.map { ResourceQid(type: $0.type, version: $0.version, path: $0.path) },
            iounit: result.iounit,
            data: Data(result.data),
            blob: try result.blob.map { try decodeBlobHandle($0) },
            stat: result.stat.map { stat in
                ResourceStatInfo(
                    qid: stat.qid.map { ResourceQid(type: $0.type, version: $0.version, path: $0.path) },
                    mode: stat.mode,
                    length: stat.length,
                    name: stat.name ?? "",
                    modifiedAt: stat.modifiedAt
                )
            },
            clunkStatus: result.clunkStatus
        )
        try validateCompoundResult(decoded)
        return decoded
    }

    static func encodeReadResult(_ result: ResourceReadResultPayload) throws -> Data {
        try validateReadResult(result)

        var builder = FlatBufferBuilder(initialSize: 1024)
        let dataOffset = result.data.isEmpty ? Offset() : builder.createVector(bytes: result.data)
        let blobOffset = try result.blob.map { try createBlobHandle($0, builder: &builder) } ?? Offset()
        let payload = AirDesk_Protocol__ResourceReadResult.createResourceReadResult(
            &builder,
            dataVectorOffset: dataOffset,
            blobOffset: blobOffset
        )
        return try finish(
            builder: &builder,
            payloadType: .resourcereadresult,
            payload: payload,
            opCode: .readResult
        )
    }

    static func decodeReadResult(_ data: Data) throws -> ResourceReadResultPayload {
        let rpc = try root(data)
        guard rpc.opCode == .readResult, rpc.payloadType == .resourcereadresult else {
            throw ResourceCompoundError.wrongPayload
        }
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceReadResult.self) else {
            throw ResourceCompoundError.missingPayload
        }
        let decoded = ResourceReadResultPayload(
            data: Data(result.data),
            blob: try result.blob.map { try decodeBlobHandle($0) }
        )
        try validateReadResult(decoded)
        return decoded
    }

    private static func root(_ data: Data) throws -> AirDesk_Protocol__ResourceRpc {
        var buffer = ByteBuffer(data: data)
        do {
            return try getCheckedRoot(byteBuffer: &buffer)
        } catch {
            throw ResourceCompoundError.invalidFlatBuffer
        }
    }

    private static func finish(
        builder: inout FlatBufferBuilder,
        payloadType: AirDesk_Protocol__ResourceRpcPayload,
        payload: Offset,
        opCode: AirDesk_Protocol__ResourceOpCode
    ) throws -> Data {
        let rpc = AirDesk_Protocol__ResourceRpc.createResourceRpc(
            &builder,
            payloadType: payloadType,
            payloadOffset: payload,
            opCode: opCode
        )
        builder.finish(offset: rpc)
        return Data(builder.data)
    }

    private static func createBlobHandle(
        _ handle: ResourceBlobHandle,
        builder: inout FlatBufferBuilder
    ) throws -> Offset {
        try validateBlobHandle(handle)
        let digest = builder.createVector(bytes: handle.digest)
        return AirDesk_Protocol__BlobHandle.createBlobHandle(
            &builder,
            version: handle.version,
            algorithm: handle.algorithm,
            digestVectorOffset: digest,
            length: handle.length,
            expiresAt: handle.expiresAt
        )
    }

    private static func createStat(
        _ stat: ResourceStatInfo,
        builder: inout FlatBufferBuilder
    ) -> Offset {
        let name = builder.create(string: stat.name)
        let qid = stat.qid ?? defaultQid
        return AirDesk_Protocol__ResourceStat.createResourceStat(
            &builder,
            qid: AirDesk_Protocol__Qid(type: qid.type, version: qid.version, path: qid.path),
            mode: stat.mode,
            length: stat.length,
            nameOffset: name,
            modifiedAt: stat.modifiedAt
        )
    }

    private static func decodeBlobHandle(_ handle: AirDesk_Protocol__BlobHandle) throws -> ResourceBlobHandle {
        let decoded = ResourceBlobHandle(
            version: handle.version,
            algorithm: handle.algorithm,
            digest: Data(handle.digest),
            length: handle.length,
            expiresAt: handle.expiresAt
        )
        try validateBlobHandle(decoded)
        return decoded
    }
}
