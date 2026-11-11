import FlatBuffers
import Foundation

enum ResourceRPCError: Error, Equatable, LocalizedError {
    case invalidFlatBuffer
    case wrongOpCode
    case wrongPayload
    case missingPayload
    case unexpectedResponse
    case requestTooLarge
    case invalidChunkSize
    case remoteStatus(AirDesk_Protocol__ResourceStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFlatBuffer:
            return "Invalid resource RPC FlatBuffer."
        case .wrongOpCode:
            return "Unexpected resource RPC op code."
        case .wrongPayload:
            return "Unexpected resource RPC payload."
        case .missingPayload:
            return "Missing resource RPC payload."
        case .unexpectedResponse:
            return "Unexpected resource RPC response."
        case .requestTooLarge:
            return "Resource RPC request exceeds its size bound."
        case .invalidChunkSize:
            return "Resource RPC chunk size is outside its bound."
        case .remoteStatus(let status):
            return "Remote resource RPC failed with status \(status)."
        }
    }
}

struct ResourceOpenReply: Equatable {
    var qid: NamespaceQid
    var iounit: UInt32
}

enum ResourceRPCCodec {
    static let maxChunkBytes = NamespaceLimits.maxReadBytes
    static let maxRequestBytes = 128 * 1024
    static let iounit: UInt32 = UInt32(NamespaceLimits.maxReadBytes)

    static func isRequestOpCode(_ opCode: AirDesk_Protocol__ResourceOpCode) -> Bool {
        switch opCode {
        case .attach, .walk, .open_, .read, .write, .clunk, .stat, .wstat, .compound:
            return true
        case .attachResult, .walkResult, .openResult, .readResult, .writeResult,
             .clunkResult, .statResult, .wstatResult, .compoundResult:
            return false
        }
    }

    static func root(_ data: Data) throws -> AirDesk_Protocol__ResourceRpc {
        var buffer = ByteBuffer(data: data)
        do {
            return try getCheckedRoot(byteBuffer: &buffer)
        } catch {
            throw ResourceRPCError.invalidFlatBuffer
        }
    }

    static func encodeAttach(
        fid: UInt32,
        afid: UInt32 = 0,
        uname: String = "",
        aname: String,
        coseToken: Data = Data()
    ) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        let unameOffset = uname.isEmpty ? Offset() : builder.create(string: uname)
        let anameOffset = builder.create(string: aname)
        let tokenOffset = coseToken.isEmpty ? Offset() : builder.createVector(bytes: coseToken)
        let payload = AirDesk_Protocol__ResourceAttach.createResourceAttach(
            &builder,
            fid: fid,
            afid: afid,
            unameOffset: unameOffset,
            anameOffset: anameOffset,
            coseTokenVectorOffset: tokenOffset
        )
        return finish(
            builder: &builder,
            payloadType: .resourceattach,
            payload: payload,
            opCode: .attach
        )
    }

    static func encodeWalk(fid: UInt32, newFid: UInt32, wnames: [String]) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        let nameOffsets = wnames.map { builder.create(string: $0) }
        let names = builder.createVector(ofOffsets: nameOffsets)
        let payload = AirDesk_Protocol__ResourceWalk.createResourceWalk(
            &builder,
            fid: fid,
            newFid: newFid,
            wnamesVectorOffset: names
        )
        return finish(
            builder: &builder,
            payloadType: .resourcewalk,
            payload: payload,
            opCode: .walk
        )
    }

    static func encodeOpen(fid: UInt32, mode: AirDesk_Protocol__BindMode) -> Data {
        var builder = FlatBufferBuilder(initialSize: 128)
        let payload = AirDesk_Protocol__ResourceOpen.createResourceOpen(
            &builder,
            fid: fid,
            mode: mode
        )
        return finish(
            builder: &builder,
            payloadType: .resourceopen,
            payload: payload,
            opCode: .open_
        )
    }

    static func encodeRead(fid: UInt32, offset: UInt64, count: UInt32) -> Data {
        var builder = FlatBufferBuilder(initialSize: 128)
        let payload = AirDesk_Protocol__ResourceRead.createResourceRead(
            &builder,
            fid: fid,
            offset: offset,
            count: count
        )
        return finish(
            builder: &builder,
            payloadType: .resourceread,
            payload: payload,
            opCode: .read
        )
    }

    static func encodeWrite(fid: UInt32, offset: UInt64, data: Data) -> Data {
        var builder = FlatBufferBuilder(initialSize: Int32(max(128, data.count + 64)))
        let bytes = data.isEmpty ? Offset() : builder.createVector(bytes: data)
        let payload = AirDesk_Protocol__ResourceWrite.createResourceWrite(
            &builder,
            fid: fid,
            offset: offset,
            dataVectorOffset: bytes
        )
        return finish(
            builder: &builder,
            payloadType: .resourcewrite,
            payload: payload,
            opCode: .write
        )
    }

    static func encodeClunk(fid: UInt32) -> Data {
        var builder = FlatBufferBuilder(initialSize: 64)
        let payload = AirDesk_Protocol__ResourceClunk.createResourceClunk(
            &builder,
            fid: fid
        )
        return finish(
            builder: &builder,
            payloadType: .resourceclunk,
            payload: payload,
            opCode: .clunk
        )
    }

    static func encodeStat(fid: UInt32) -> Data {
        var builder = FlatBufferBuilder(initialSize: 64)
        let payload = AirDesk_Protocol__ResourceStatRequest.createResourceStatRequest(
            &builder,
            fid: fid
        )
        return finish(
            builder: &builder,
            payloadType: .resourcestatrequest,
            payload: payload,
            opCode: .stat
        )
    }

    static func encodeWstat(fid: UInt32, stat: NamespaceStat) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        let statOffset = createStat(stat, builder: &builder)
        let payload = AirDesk_Protocol__ResourceWstat.createResourceWstat(
            &builder,
            fid: fid,
            statOffset: statOffset
        )
        return finish(
            builder: &builder,
            payloadType: .resourcewstat,
            payload: payload,
            opCode: .wstat
        )
    }

    static func encodeAttachResult(fid: UInt32, qid: NamespaceQid) -> Data {
        var builder = FlatBufferBuilder(initialSize: 128)
        let payload = AirDesk_Protocol__ResourceAttachResult.createResourceAttachResult(
            &builder,
            fid: fid,
            qid: qid.generated
        )
        return finish(
            builder: &builder,
            payloadType: .resourceattachresult,
            payload: payload,
            opCode: .attachResult
        )
    }

    static func encodeWalkResult(qids: [NamespaceQid]) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        let qidVector = builder.createVector(ofStructs: qids.map(\.generated))
        let payload = AirDesk_Protocol__ResourceWalkResult.createResourceWalkResult(
            &builder,
            wqidsVectorOffset: qidVector
        )
        return finish(
            builder: &builder,
            payloadType: .resourcewalkresult,
            payload: payload,
            opCode: .walkResult
        )
    }

    static func encodeOpenResult(qid: NamespaceQid) -> Data {
        var builder = FlatBufferBuilder(initialSize: 128)
        let payload = AirDesk_Protocol__ResourceOpenResult.createResourceOpenResult(
            &builder,
            qid: qid.generated,
            iounit: iounit
        )
        return finish(
            builder: &builder,
            payloadType: .resourceopenresult,
            payload: payload,
            opCode: .openResult
        )
    }

    static func encodeReadResult(data: Data) -> Data {
        var builder = FlatBufferBuilder(initialSize: Int32(max(128, data.count + 64)))
        let bytes = data.isEmpty ? Offset() : builder.createVector(bytes: data)
        let payload = AirDesk_Protocol__ResourceReadResult.createResourceReadResult(
            &builder,
            dataVectorOffset: bytes
        )
        return finish(
            builder: &builder,
            payloadType: .resourcereadresult,
            payload: payload,
            opCode: .readResult
        )
    }

    static func encodeWriteResult(count: UInt32) -> Data {
        var builder = FlatBufferBuilder(initialSize: 64)
        let payload = AirDesk_Protocol__ResourceWriteResult.createResourceWriteResult(
            &builder,
            count: count
        )
        return finish(
            builder: &builder,
            payloadType: .resourcewriteresult,
            payload: payload,
            opCode: .writeResult
        )
    }

    static func encodeClunkResult(status: AirDesk_Protocol__ResourceStatus = .ok) -> Data {
        var builder = FlatBufferBuilder(initialSize: 64)
        let payload = AirDesk_Protocol__ResourceClunkResult.createResourceClunkResult(
            &builder,
            status: status
        )
        return finish(
            builder: &builder,
            payloadType: .resourceclunkresult,
            payload: payload,
            opCode: .clunkResult
        )
    }

    static func encodeStatResult(stat: NamespaceStat) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        let statOffset = createStat(stat, builder: &builder)
        let payload = AirDesk_Protocol__ResourceStatResult.createResourceStatResult(
            &builder,
            statOffset: statOffset
        )
        return finish(
            builder: &builder,
            payloadType: .resourcestatresult,
            payload: payload,
            opCode: .statResult
        )
    }

    static func encodeWstatResult(status: AirDesk_Protocol__ResourceStatus = .ok) -> Data {
        var builder = FlatBufferBuilder(initialSize: 64)
        let payload = AirDesk_Protocol__ResourceWstatResult.createResourceWstatResult(
            &builder,
            status: status
        )
        return finish(
            builder: &builder,
            payloadType: .resourcewstatresult,
            payload: payload,
            opCode: .wstatResult
        )
    }

    static func encodeError(_ status: AirDesk_Protocol__ResourceStatus) -> Data {
        let result = ResourceCompoundResultPayload(
            requestId: 0,
            status: status,
            qid: nil,
            iounit: iounit,
            data: Data(),
            blob: nil,
            stat: nil,
            clunkStatus: .ok
        )
        return (try? ResourceCompoundCodec.encodeCompoundResult(result)) ?? Data()
    }

    static func createStat(
        _ stat: NamespaceStat,
        builder: inout FlatBufferBuilder
    ) -> Offset {
        let name = builder.create(string: stat.name)
        return AirDesk_Protocol__ResourceStat.createResourceStat(
            &builder,
            qid: stat.qid.generated,
            mode: stat.mode,
            length: stat.length,
            nameOffset: name,
            modifiedAt: stat.modifiedAt
        )
    }

    static func decodeStat(_ stat: AirDesk_Protocol__ResourceStat?) -> NamespaceStat? {
        guard let stat else { return nil }
        return NamespaceStat(
            qid: NamespaceQid(stat.qid),
            mode: stat.mode,
            length: stat.length,
            name: stat.name ?? "",
            modifiedAt: stat.modifiedAt
        )
    }

    static func finish(
        builder: inout FlatBufferBuilder,
        payloadType: AirDesk_Protocol__ResourceRpcPayload,
        payload: Offset,
        opCode: AirDesk_Protocol__ResourceOpCode
    ) -> Data {
        let rpc = AirDesk_Protocol__ResourceRpc.createResourceRpc(
            &builder,
            payloadType: payloadType,
            payloadOffset: payload,
            opCode: opCode
        )
        builder.finish(offset: rpc)
        return Data(builder.data)
    }
}

final class ResourceRPCClient {
    typealias Transport = (Data) throws -> Data

    private let transport: Transport

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    func attach(
        fid: UInt32,
        aname: String,
        uname: String = "",
        afid: UInt32 = 0,
        coseToken: Data = Data()
    ) throws -> NamespaceQid {
        let data = try transport(
            ResourceRPCCodec.encodeAttach(
                fid: fid,
                afid: afid,
                uname: uname,
                aname: aname,
                coseToken: coseToken
            )
        )
        let rpc = try ResourceRPCCodec.root(data)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .attachResult, payloadType: .resourceattachresult)
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceAttachResult.self) else {
            throw ResourceRPCError.missingPayload
        }
        return NamespaceQid(result.qid)
    }

    func walk(fid: UInt32, newFid: UInt32, wnames: [String]) throws -> [NamespaceQid] {
        let data = try transport(
            ResourceRPCCodec.encodeWalk(fid: fid, newFid: newFid, wnames: wnames)
        )
        let rpc = try ResourceRPCCodec.root(data)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .walkResult, payloadType: .resourcewalkresult)
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceWalkResult.self) else {
            throw ResourceRPCError.missingPayload
        }
        var qids: [NamespaceQid] = []
        for index in 0..<result.wqids.count {
            qids.append(NamespaceQid(result.wqids[index]))
        }
        return qids
    }

    func open(fid: UInt32, mode: AirDesk_Protocol__BindMode) throws -> ResourceOpenReply {
        let data = try transport(ResourceRPCCodec.encodeOpen(fid: fid, mode: mode))
        let rpc = try ResourceRPCCodec.root(data)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .openResult, payloadType: .resourceopenresult)
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceOpenResult.self) else {
            throw ResourceRPCError.missingPayload
        }
        return ResourceOpenReply(qid: NamespaceQid(result.qid), iounit: result.iounit)
    }

    func read(fid: UInt32, offset: UInt64, count: UInt32) throws -> Data {
        let data = try transport(
            ResourceRPCCodec.encodeRead(fid: fid, offset: offset, count: count)
        )
        let rpc = try ResourceRPCCodec.root(data)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .readResult, payloadType: .resourcereadresult)
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceReadResult.self) else {
            throw ResourceRPCError.missingPayload
        }
        return Data(result.data)
    }

    func write(fid: UInt32, offset: UInt64, data: Data) throws -> Int {
        let response = try transport(
            ResourceRPCCodec.encodeWrite(fid: fid, offset: offset, data: data)
        )
        let rpc = try ResourceRPCCodec.root(response)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .writeResult, payloadType: .resourcewriteresult)
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceWriteResult.self) else {
            throw ResourceRPCError.missingPayload
        }
        return Int(result.count)
    }

    func clunk(fid: UInt32) throws {
        let data = try transport(ResourceRPCCodec.encodeClunk(fid: fid))
        let rpc = try ResourceRPCCodec.root(data)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .clunkResult, payloadType: .resourceclunkresult)
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceClunkResult.self) else {
            throw ResourceRPCError.missingPayload
        }
        guard result.status == .ok else {
            throw ResourceRPCError.remoteStatus(result.status)
        }
    }

    func stat(fid: UInt32) throws -> NamespaceStat {
        let data = try transport(ResourceRPCCodec.encodeStat(fid: fid))
        let rpc = try ResourceRPCCodec.root(data)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .statResult, payloadType: .resourcestatresult)
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceStatResult.self),
              let stat = ResourceRPCCodec.decodeStat(result.stat) else {
            throw ResourceRPCError.missingPayload
        }
        return stat
    }

    func wstat(fid: UInt32, stat: NamespaceStat) throws {
        let data = try transport(ResourceRPCCodec.encodeWstat(fid: fid, stat: stat))
        let rpc = try ResourceRPCCodec.root(data)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .wstatResult, payloadType: .resourcewstatresult)
        guard let result = rpc.payload(type: AirDesk_Protocol__ResourceWstatResult.self) else {
            throw ResourceRPCError.missingPayload
        }
        guard result.status == .ok else {
            throw ResourceRPCError.remoteStatus(result.status)
        }
    }

    func compound(_ request: ResourceCompoundRequestPayload) throws -> ResourceCompoundResultPayload {
        let data = try transport(ResourceCompoundCodec.encodeCompoundRequest(request))
        let rpc = try ResourceRPCCodec.root(data)
        try throwRemoteStatusIfPresent(rpc)
        try require(rpc, opCode: .compoundResult, payloadType: .resourcecompoundresult)
        return try ResourceCompoundCodec.decodeCompoundResult(data)
    }

    func readAll(
        fid: UInt32,
        offset: UInt64 = 0,
        count: Int,
        chunkSize: Int = ResourceRPCCodec.maxChunkBytes
    ) throws -> Data {
        guard chunkSize > 0, chunkSize <= ResourceRPCCodec.maxChunkBytes else {
            throw ResourceRPCError.invalidChunkSize
        }
        guard count >= 0 else {
            throw ResourceRPCError.invalidChunkSize
        }
        var result = Data()
        var currentOffset = offset
        var remaining = count
        while remaining > 0 {
            let requested = min(remaining, chunkSize)
            let chunk = try read(fid: fid, offset: currentOffset, count: UInt32(requested))
            if chunk.isEmpty {
                break
            }
            result.append(chunk)
            currentOffset += UInt64(chunk.count)
            remaining -= chunk.count
            if chunk.count < requested {
                break
            }
        }
        return result
    }

    func writeAll(
        fid: UInt32,
        offset: UInt64 = 0,
        data: Data,
        chunkSize: Int = ResourceRPCCodec.maxChunkBytes
    ) throws -> Int {
        guard chunkSize > 0, chunkSize <= ResourceRPCCodec.maxChunkBytes else {
            throw ResourceRPCError.invalidChunkSize
        }
        var written = 0
        var currentOffset = offset
        while written < data.count {
            let end = min(written + chunkSize, data.count)
            let chunk = data.subdata(in: written..<end)
            let count = try write(fid: fid, offset: currentOffset, data: chunk)
            written += count
            currentOffset += UInt64(count)
            if count < chunk.count {
                break
            }
        }
        return written
    }

    private func require(
        _ rpc: AirDesk_Protocol__ResourceRpc,
        opCode: AirDesk_Protocol__ResourceOpCode,
        payloadType: AirDesk_Protocol__ResourceRpcPayload
    ) throws {
        guard rpc.opCode == opCode else { throw ResourceRPCError.wrongOpCode }
        guard rpc.payloadType == payloadType else { throw ResourceRPCError.wrongPayload }
    }

    private func throwRemoteStatusIfPresent(_ rpc: AirDesk_Protocol__ResourceRpc) throws {
        guard rpc.opCode == .compoundResult,
              rpc.payloadType == .resourcecompoundresult,
              let result = rpc.payload(type: AirDesk_Protocol__ResourceCompoundResult.self) else {
            return
        }
        if result.status != .ok {
            throw ResourceRPCError.remoteStatus(result.status)
        }
    }
}
