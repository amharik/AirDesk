import Foundation
import XCTest
@testable import AirDesk

final class ResourceRPCTests: XCTestCase {
    private let text = Data("hello namespace".utf8)

    func testAllOpcodesRoundTripThroughClientAndServer() throws {
        let storage = try InMemoryNamespaceStorage(entries: ["dir/file.txt": text])
        let leases = NamespaceLeaseRegistry()
        try leases.grant(id: "lease")
        let service = NamespaceImportService(storage: storage, leaseAuthorizer: leases)
        let server = ResourceRPCServer(service: service, leaseId: "lease")
        let client = ResourceRPCClient { server.handle($0) }

        let root = try client.attach(fid: 1, aname: "workspace")
        XCTAssertTrue(root.isDirectory)

        let qids = try client.walk(fid: 1, newFid: 2, wnames: ["dir", "file.txt"])
        XCTAssertEqual(qids.count, 2)
        XCTAssertTrue(qids[0].isDirectory)
        XCTAssertFalse(qids[1].isDirectory)

        let opened = try client.open(fid: 2, mode: .readWrite)
        XCTAssertFalse(opened.qid.isDirectory)
        XCTAssertEqual(opened.iounit, ResourceRPCCodec.iounit)

        let stat = try client.stat(fid: 2)
        XCTAssertEqual(stat.name, "file.txt")
        XCTAssertEqual(stat.length, UInt64(text.count))

        XCTAssertEqual(try client.read(fid: 2, offset: 0, count: 5), Data("hello".utf8))
        XCTAssertEqual(try client.write(fid: 2, offset: 6, data: Data("WORLD".utf8)), 5)
        XCTAssertEqual(
            try client.read(fid: 2, offset: 0, count: 15),
            Data("hello WORLDpace".utf8)
        )

        try client.wstat(
            fid: 2,
            stat: NamespaceStat(
                qid: stat.qid,
                mode: UInt32.max,
                length: 5,
                name: "renamed.txt",
                modifiedAt: 0
            )
        )
        let renamed = try client.stat(fid: 2)
        XCTAssertEqual(renamed.name, "renamed.txt")
        XCTAssertEqual(renamed.length, 5)

        try client.clunk(fid: 2)
        XCTAssertFalse(service.isFidActive(2))

        _ = try client.attach(fid: 3, aname: "workspace")
        let compound = try client.compound(
            ResourceCompoundRequestPayload(
                requestId: 9,
                fid: 3,
                newFid: 4,
                wnames: ["dir", "renamed.txt"],
                openMode: .readOnly,
                readOffset: 0,
                readCount: 5,
                clunk: true
            )
        )
        XCTAssertEqual(compound.requestId, 9)
        XCTAssertEqual(compound.status, .ok)
        XCTAssertEqual(compound.data, Data("hello".utf8))
        XCTAssertEqual(compound.stat?.name, "renamed.txt")
        XCTAssertEqual(compound.clunkStatus, .ok)
        XCTAssertFalse(service.isFidActive(4))
    }

    func testPathConfinementAndSymlinkEscapeOverRPC() throws {
        let storage = try InMemoryNamespaceStorage(entries: ["file.txt": text])
        let leases = NamespaceLeaseRegistry()
        try leases.grant(id: "lease")
        let service = NamespaceImportService(storage: storage, leaseAuthorizer: leases)
        let server = ResourceRPCServer(service: service, leaseId: "lease")
        let client = ResourceRPCClient { server.handle($0) }
        _ = try client.attach(fid: 1, aname: "workspace")

        assertRemoteStatus(.invalid) {
            _ = try client.walk(fid: 1, newFid: 2, wnames: [".."])
        }
        assertRemoteStatus(.invalid) {
            _ = try client.walk(fid: 1, newFid: 3, wnames: ["etc/passwd"])
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("airdesk-rpc-root-\(UUID().uuidString)")
        let outside = fileManager.temporaryDirectory
            .appendingPathComponent("airdesk-rpc-outside-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: outside)
        }
        try Data("inside".utf8).write(to: root.appendingPathComponent("inside.txt"))
        try Data("outside".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        let confined = try ConfinedFileSystemNamespaceStorage(rootURL: root)
        let confinedService = NamespaceImportService(
            storage: confined,
            leaseAuthorizer: leases
        )
        let confinedServer = ResourceRPCServer(service: confinedService, leaseId: "lease")
        let confinedClient = ResourceRPCClient { confinedServer.handle($0) }

        _ = try confinedClient.attach(fid: 10, aname: "workspace")
        let inside = try confinedClient.walk(
            fid: 10,
            newFid: 11,
            wnames: ["inside.txt"]
        )
        XCTAssertEqual(inside.count, 1)
        assertRemoteStatus(.invalid) {
            _ = try confinedClient.walk(
                fid: 10,
                newFid: 12,
                wnames: ["escape", "secret.txt"]
            )
        }
    }

    func testChunkedReadWriteAndSizeCaps() throws {
        let payload = Data(repeating: 0x41, count: 150_000)
        let storage = try InMemoryNamespaceStorage(entries: ["large.bin": payload])
        let leases = NamespaceLeaseRegistry()
        try leases.grant(id: "lease")
        let service = NamespaceImportService(storage: storage, leaseAuthorizer: leases)
        let server = ResourceRPCServer(service: service, leaseId: "lease")

        var readCounts: [UInt32] = []
        var writeCounts: [UInt32] = []
        let client = ResourceRPCClient { data in
            let rpc = try ResourceRPCCodec.root(data)
            if rpc.opCode == .read,
               let request = rpc.payload(type: AirDesk_Protocol__ResourceRead.self) {
                readCounts.append(request.count)
            }
            if rpc.opCode == .write,
               let request = rpc.payload(type: AirDesk_Protocol__ResourceWrite.self) {
                writeCounts.append(UInt32(request.data.count))
            }
            return server.handle(data)
        }

        _ = try client.attach(fid: 1, aname: "workspace")
        _ = try client.walk(fid: 1, newFid: 2, wnames: ["large.bin"])
        _ = try client.open(fid: 2, mode: .readOnly)

        let read = try client.readAll(fid: 2, count: payload.count)
        XCTAssertEqual(read, payload)
        XCTAssertEqual(readCounts.count, 3)
        XCTAssertEqual(readCounts.first, UInt32(ResourceRPCCodec.maxChunkBytes))
        XCTAssertTrue(
            readCounts.allSatisfy { $0 <= UInt32(ResourceRPCCodec.maxChunkBytes) }
        )

        assertRemoteStatus(.invalid) {
            _ = try client.read(
                fid: 2,
                offset: 0,
                count: UInt32(NamespaceLimits.maxReadBytes) + 1
            )
        }

        _ = try client.walk(fid: 1, newFid: 3, wnames: ["large.bin"])
        _ = try client.open(fid: 3, mode: .readWrite)
        let replacement = Data(repeating: 0x42, count: payload.count)
        XCTAssertEqual(
            try client.writeAll(fid: 3, data: replacement),
            replacement.count
        )
        XCTAssertEqual(writeCounts.count, 3)
        XCTAssertTrue(
            writeCounts.allSatisfy { $0 <= UInt32(ResourceRPCCodec.maxChunkBytes) }
        )
        XCTAssertEqual(try client.readAll(fid: 2, count: payload.count), replacement)

        let tinyServer = ResourceRPCServer(
            service: service,
            leaseId: "lease",
            maxRequestBytes: 8
        )
        XCTAssertEqual(
            try XCTUnwrap(
                responseStatus(tinyServer.handle(ResourceRPCCodec.encodeStat(fid: 1)))
            ),
            .invalid
        )
    }

    func testLeaseDenialAndRevocationOverRPC() throws {
        let storage = try InMemoryNamespaceStorage(entries: ["file.txt": text])
        let leases = NamespaceLeaseRegistry()
        try leases.grant(id: "lease")
        let service = NamespaceImportService(storage: storage, leaseAuthorizer: leases)
        let server = ResourceRPCServer(service: service, leaseId: "lease")
        let client = ResourceRPCClient { server.handle($0) }

        _ = try client.attach(fid: 1, aname: "workspace")
        _ = try client.walk(fid: 1, newFid: 2, wnames: ["file.txt"])
        _ = try client.open(fid: 2, mode: .readOnly)
        XCTAssertEqual(try client.read(fid: 2, offset: 0, count: 5), Data("hello".utf8))

        leases.revoke(id: "lease")
        assertRemoteStatus(.revoked) {
            _ = try client.read(fid: 2, offset: 0, count: 5)
        }
        assertRemoteStatus(.revoked) {
            try client.clunk(fid: 2)
        }
        XCTAssertTrue(service.isFidActive(2))

        let unleasedService = NamespaceImportService(
            storage: storage,
            leaseAuthorizer: leases
        )
        let unleasedServer = ResourceRPCServer(service: unleasedService, leaseId: nil)
        let unleasedClient = ResourceRPCClient { unleasedServer.handle($0) }
        assertRemoteStatus(.unauthorized) {
            _ = try unleasedClient.attach(fid: 5, aname: "workspace")
        }
    }

    func testRejectsResultOpcodesAnd9PTunnelFrames() throws {
        let storage = try InMemoryNamespaceStorage(entries: ["file.txt": text])
        let service = NamespaceImportService(storage: storage)
        let server = ResourceRPCServer(service: service)

        let resultFrame = ResourceRPCCodec.encodeWalkResult(qids: [])
        XCTAssertEqual(
            try XCTUnwrap(responseStatus(server.handle(resultFrame))),
            .invalid
        )

        let ninePFrame = Data([0, 0, 0, 7, 100, 0, 0])
        XCTAssertEqual(
            try XCTUnwrap(responseStatus(server.handle(ninePFrame))),
            .invalid
        )

        let client = ResourceRPCClient { _ in ResourceRPCCodec.encodeStat(fid: 1) }
        XCTAssertThrowsError(try client.stat(fid: 1)) { error in
            XCTAssertEqual(error as? ResourceRPCError, .wrongOpCode)
        }
    }

    private func assertRemoteStatus(
        _ expected: AirDesk_Protocol__ResourceStatus,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? ResourceRPCError,
                .remoteStatus(expected),
                file: file,
                line: line
            )
        }
    }

    private func responseStatus(
        _ data: Data
    ) throws -> AirDesk_Protocol__ResourceStatus? {
        let rpc = try ResourceRPCCodec.root(data)
        guard rpc.opCode == .compoundResult,
              let result = rpc.payload(type: AirDesk_Protocol__ResourceCompoundResult.self) else {
            return nil
        }
        return result.status
    }
}
