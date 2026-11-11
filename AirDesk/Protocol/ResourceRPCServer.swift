import Foundation

final class ResourceRPCServer {
    private let service: NamespaceImportService
    private let leaseId: String?
    private let maxRequestBytes: Int

    init(
        service: NamespaceImportService,
        leaseId: String? = nil,
        maxRequestBytes: Int = ResourceRPCCodec.maxRequestBytes
    ) {
        self.service = service
        self.leaseId = leaseId
        self.maxRequestBytes = maxRequestBytes
    }

    func handle(_ data: Data) -> Data {
        guard data.count <= maxRequestBytes else {
            return ResourceRPCCodec.encodeError(.invalid)
        }
        do {
            return try handleRequest(data)
        } catch let error as NamespaceError {
            return ResourceRPCCodec.encodeError(error.status)
        } catch {
            return ResourceRPCCodec.encodeError(.invalid)
        }
    }

    func handleRequest(_ data: Data) throws -> Data {
        let rpc = try ResourceRPCCodec.root(data)
        guard ResourceRPCCodec.isRequestOpCode(rpc.opCode) else {
            throw ResourceRPCError.wrongOpCode
        }

        switch rpc.opCode {
        case .attach:
            try require(rpc, payloadType: .resourceattach)
            guard let request = rpc.payload(type: AirDesk_Protocol__ResourceAttach.self) else {
                throw ResourceRPCError.missingPayload
            }
            let uname = request.uname ?? ""
            let aname = request.aname ?? ""
            guard uname.utf8.count <= 128, aname.utf8.count <= 128 else {
                throw NamespaceError.invalidPath("attach name")
            }
            let stat = try service.attach(
                fid: request.fid,
                aname: aname,
                uname: uname,
                leaseId: leaseId
            )
            return ResourceRPCCodec.encodeAttachResult(fid: request.fid, qid: stat.qid)

        case .walk:
            try require(rpc, payloadType: .resourcewalk)
            guard let request = rpc.payload(type: AirDesk_Protocol__ResourceWalk.self) else {
                throw ResourceRPCError.missingPayload
            }
            var wnames: [String] = []
            for name in request.wnames {
                guard let name else { throw NamespaceError.invalidPath("wname") }
                wnames.append(name)
            }
            let qids = try service.walk(
                fid: request.fid,
                newFid: request.newFid,
                wnames: wnames
            )
            return ResourceRPCCodec.encodeWalkResult(qids: qids)

        case .open_:
            try require(rpc, payloadType: .resourceopen)
            guard let request = rpc.payload(type: AirDesk_Protocol__ResourceOpen.self) else {
                throw ResourceRPCError.missingPayload
            }
            let stat = try service.open(fid: request.fid, mode: request.mode)
            return ResourceRPCCodec.encodeOpenResult(qid: stat.qid)

        case .read:
            try require(rpc, payloadType: .resourceread)
            guard let request = rpc.payload(type: AirDesk_Protocol__ResourceRead.self) else {
                throw ResourceRPCError.missingPayload
            }
            guard request.count <= UInt32(NamespaceLimits.maxReadBytes) else {
                throw NamespaceError.tooLarge
            }
            let data = try service.read(
                fid: request.fid,
                offset: request.offset,
                count: Int(request.count)
            )
            return ResourceRPCCodec.encodeReadResult(data: data)

        case .write:
            try require(rpc, payloadType: .resourcewrite)
            guard let request = rpc.payload(type: AirDesk_Protocol__ResourceWrite.self) else {
                throw ResourceRPCError.missingPayload
            }
            let data = Data(request.data)
            guard data.count <= NamespaceLimits.maxWriteBytes else {
                throw NamespaceError.tooLarge
            }
            let count = try service.write(
                fid: request.fid,
                offset: request.offset,
                data: data
            )
            return ResourceRPCCodec.encodeWriteResult(count: UInt32(count))

        case .clunk:
            try require(rpc, payloadType: .resourceclunk)
            guard let request = rpc.payload(type: AirDesk_Protocol__ResourceClunk.self) else {
                throw ResourceRPCError.missingPayload
            }
            try service.clunk(fid: request.fid)
            return ResourceRPCCodec.encodeClunkResult()

        case .stat:
            try require(rpc, payloadType: .resourcestatrequest)
            guard let request = rpc.payload(type: AirDesk_Protocol__ResourceStatRequest.self) else {
                throw ResourceRPCError.missingPayload
            }
            let stat = try service.stat(fid: request.fid)
            return ResourceRPCCodec.encodeStatResult(stat: stat)

        case .wstat:
            try require(rpc, payloadType: .resourcewstat)
            guard let request = rpc.payload(type: AirDesk_Protocol__ResourceWstat.self),
                  let stat = ResourceRPCCodec.decodeStat(request.stat) else {
                throw ResourceRPCError.missingPayload
            }
            try service.wstat(fid: request.fid, stat: stat)
            return ResourceRPCCodec.encodeWstatResult()

        case .compound:
            try require(rpc, payloadType: .resourcecompoundrequest)
            let request = try ResourceCompoundCodec.decodeCompoundRequest(data)
            return try compound(request)

        case .attachResult, .walkResult, .openResult, .readResult, .writeResult,
             .clunkResult, .statResult, .wstatResult, .compoundResult:
            throw ResourceRPCError.wrongOpCode
        }
    }

    private func compound(_ request: ResourceCompoundRequestPayload) throws -> Data {
        guard request.readCount <= UInt32(NamespaceLimits.maxReadBytes) else {
            throw NamespaceError.tooLarge
        }
        _ = try service.walk(
            fid: request.fid,
            newFid: request.newFid,
            wnames: request.wnames
        )
        _ = try service.open(fid: request.newFid, mode: request.openMode)
        let data = request.readCount > 0
            ? try service.read(
                fid: request.newFid,
                offset: request.readOffset,
                count: Int(request.readCount)
            )
            : Data()
        let stat = try service.stat(fid: request.newFid)
        if request.clunk {
            try service.clunk(fid: request.newFid)
        }

        let qid = ResourceQid(
            type: stat.qid.type,
            version: stat.qid.version,
            path: stat.qid.path
        )
        let result = ResourceCompoundResultPayload(
            requestId: request.requestId,
            status: .ok,
            qid: qid,
            iounit: ResourceRPCCodec.iounit,
            data: data,
            blob: nil,
            stat: ResourceStatInfo(
                qid: qid,
                mode: stat.mode,
                length: stat.length,
                name: stat.name,
                modifiedAt: stat.modifiedAt
            ),
            clunkStatus: .ok
        )
        return try ResourceCompoundCodec.encodeCompoundResult(result)
    }

    private func require(
        _ rpc: AirDesk_Protocol__ResourceRpc,
        payloadType: AirDesk_Protocol__ResourceRpcPayload
    ) throws {
        guard rpc.payloadType == payloadType else {
            throw ResourceRPCError.wrongPayload
        }
    }
}
