import XCTest
@testable import AirDesk

final class NamespaceImportServiceTests: XCTestCase {
    private let text = Data("hello namespace".utf8)

    func testPathRulesRejectAbsoluteTraversalAndEmptySegments() {
        XCTAssertEqual(try NamespacePathRules.components(""), [])
        XCTAssertEqual(try NamespacePathRules.components("a/./b"), ["a", "b"])

        assertNamespaceError(.absolutePathRejected) {
            _ = try NamespacePathRules.components("/etc/passwd")
        }
        assertNamespaceError(.pathEscapesRoot) {
            _ = try NamespacePathRules.components("dir/../secret")
        }
        assertNamespaceError(.invalidPath("dir//file")) {
            _ = try NamespacePathRules.components("dir//file")
        }
        assertNamespaceError(.invalidPath("dir/")) {
            _ = try NamespacePathRules.components("dir/")
        }
        assertNamespaceError(.tooLarge) {
            _ = try NamespacePathRules.validateSegment(String(repeating: "x", count: 256))
        }
    }

    func testAttachWalkOpenReadWriteAndClunk() throws {
        let storage = try InMemoryNamespaceStorage(
            entries: ["dir/file.txt": text]
        )
        let leases = NamespaceLeaseRegistry()
        try leases.grant(id: "lease")
        let service = NamespaceImportService(storage: storage, leaseAuthorizer: leases)

        let root = try service.attach(
            fid: 1,
            aname: "workspace",
            uname: "user",
            leaseId: "lease"
        )
        XCTAssertTrue(root.qid.isDirectory)
        XCTAssertEqual(service.activeFids, [1])

        let qids = try service.walk(fid: 1, newFid: 2, wnames: ["dir", "file.txt"])
        XCTAssertEqual(qids.count, 2)
        XCTAssertTrue(qids[0].isDirectory)
        XCTAssertFalse(qids[1].isDirectory)

        let opened = try service.open(fid: 2, mode: .readWrite)
        XCTAssertEqual(opened.length, UInt64(text.count))
        XCTAssertEqual(
            try service.read(fid: 2, offset: 0, count: 5),
            Data("hello".utf8)
        )
        XCTAssertEqual(
            try service.write(fid: 2, offset: 6, data: Data("WORLD".utf8)),
            Int(5)
        )
        XCTAssertEqual(
            try service.read(fid: 2, offset: 0, count: 15),
            Data("hello WORLDpace".utf8)
        )

        try service.clunk(fid: 2)
        XCTAssertFalse(service.isFidActive(2))
        XCTAssertEqual(service.activeFids, [1])
    }

    func testBindModesEnforceReadAndWritePermissions() throws {
        let storage = try InMemoryNamespaceStorage(entries: ["file.txt": text])
        let service = NamespaceImportService(storage: storage)
        _ = try service.attach(fid: 1, aname: "workspace", uname: "u", leaseId: nil)
        _ = try service.walk(fid: 1, newFid: 2, wnames: ["file.txt"])
        _ = try service.open(fid: 2, mode: .readOnly)

        assertNamespaceError(.permissionDenied) {
            _ = try service.write(fid: 2, offset: 0, data: Data("x".utf8))
        }

        _ = try service.attach(fid: 3, aname: "workspace", uname: "u", leaseId: nil)
        _ = try service.walk(fid: 3, newFid: 4, wnames: ["file.txt"])
        _ = try service.open(fid: 4, mode: .append)

        assertNamespaceError(.permissionDenied) {
            _ = try service.read(fid: 4, offset: 0, count: 1)
        }
        XCTAssertEqual(
            try service.write(fid: 4, offset: UInt64.max, data: Data("!".utf8)),
            1
        )
        XCTAssertEqual(
            try storage.read(path: "file.txt", offset: 0, count: 64),
            text + Data("!".utf8)
        )
    }

    func testFidLifecycleErrors() throws {
        let storage = try InMemoryNamespaceStorage(entries: ["file.txt": text])
        let service = NamespaceImportService(storage: storage)
        _ = try service.attach(fid: 1, aname: "workspace", uname: "u", leaseId: nil)

        assertNamespaceError(.fidInUse(1)) {
            _ = try service.attach(fid: 1, aname: "other", uname: "u", leaseId: nil)
        }
        assertNamespaceError(.fidNotFound(2)) {
            _ = try service.read(fid: 2, offset: 0, count: 1)
        }
        _ = try service.walk(fid: 1, newFid: 2, wnames: ["file.txt"])
        assertNamespaceError(.notOpened(2)) {
            _ = try service.read(fid: 2, offset: 0, count: 1)
        }
        _ = try service.open(fid: 2, mode: .readOnly)
        assertNamespaceError(.fidAlreadyOpen(2)) {
            _ = try service.open(fid: 2, mode: .readOnly)
        }
        assertNamespaceError(.fidNotFound(99)) {
            _ = try service.stat(fid: 99)
        }
        assertNamespaceError(.fidNotFound(99)) {
            try service.clunk(fid: 99)
        }
    }

    func testWstatRenamesResizesAndUpdatesFidPathRepeatedly() throws {
        let storage = try InMemoryNamespaceStorage(entries: ["dir/a.txt": text])
        let service = NamespaceImportService(storage: storage)
        _ = try service.attach(fid: 1, aname: "workspace", uname: "u", leaseId: nil)
        _ = try service.walk(fid: 1, newFid: 2, wnames: ["dir", "a.txt"])
        _ = try service.open(fid: 2, mode: .readWrite)

        try service.wstat(
            fid: 2,
            stat: NamespaceStat(
                qid: .make(path: "dir/a.txt", isDirectory: false),
                mode: UInt32.max,
                length: 5,
                name: "b.txt",
                modifiedAt: 0
            )
        )
        let first = try service.stat(fid: 2)
        XCTAssertEqual(first.name, "b.txt")
        XCTAssertEqual(first.length, 5)
        assertNamespaceError(.notFound("dir/a.txt")) {
            _ = try storage.stat(path: "dir/a.txt")
        }

        try service.wstat(
            fid: 2,
            stat: NamespaceStat(
                qid: first.qid,
                mode: 0o600,
                length: UInt64.max,
                name: "c.txt",
                modifiedAt: 1_700_000_000_000
            )
        )
        let second = try service.stat(fid: 2)
        XCTAssertEqual(second.name, "c.txt")
        XCTAssertEqual(second.mode, 0o600)
        XCTAssertEqual(second.modifiedAt, 1_700_000_000_000)
        XCTAssertEqual(
            try storage.read(path: "dir/c.txt", offset: 0, count: 64),
            Data("hello".utf8)
        )
        assertNamespaceError(.notFound("dir/b.txt")) {
            _ = try storage.stat(path: "dir/b.txt")
        }
    }

    func testLeaseDeniesMissingRevokedExpiredAndOutOfPrefixOperations() throws {
        let now = Date(timeIntervalSince1970: 200)
        let leases = NamespaceLeaseRegistry(now: { now })
        try leases.grant(
            id: "expired",
            operations: [.read],
            expiresAt: Date(timeIntervalSince1970: 100)
        )
        try leases.grant(id: "revoked", operations: [.read])
        leases.revoke(id: "revoked")
        try leases.grant(id: "prefix", operations: [.read], pathPrefix: "allowed")

        let request = NamespaceLeaseRequest(
            leaseId: "missing",
            operation: .read,
            path: "allowed/file",
            mode: .readOnly
        )
        assertNamespaceError(.leaseDenied) {
            try leases.authorize(request)
        }
        assertNamespaceError(.leaseExpired) {
            try leases.authorize(
                NamespaceLeaseRequest(
                    leaseId: "expired",
                    operation: .read,
                    path: "file",
                    mode: .readOnly
                )
            )
        }
        assertNamespaceError(.leaseRevoked) {
            try leases.authorize(
                NamespaceLeaseRequest(
                    leaseId: "revoked",
                    operation: .read,
                    path: "file",
                    mode: .readOnly
                )
            )
        }
        XCTAssertNoThrow(
            try leases.authorize(
                NamespaceLeaseRequest(
                    leaseId: "prefix",
                    operation: .read,
                    path: "allowed/file",
                    mode: .readOnly
                )
            )
        )
        assertNamespaceError(.leaseDenied) {
            try leases.authorize(
                NamespaceLeaseRequest(
                    leaseId: "prefix",
                    operation: .read,
                    path: "allowedness/file",
                    mode: .readOnly
                )
            )
        }
    }

    func testDeniedClunkKeepsFidActive() throws {
        let storage = try InMemoryNamespaceStorage(entries: ["file.txt": text])
        let leases = NamespaceLeaseRegistry()
        try leases.grant(id: "lease", operations: [.attach])
        let service = NamespaceImportService(storage: storage, leaseAuthorizer: leases)
        _ = try service.attach(fid: 1, aname: "workspace", uname: "u", leaseId: "lease")

        assertNamespaceError(.leaseDenied) {
            try service.clunk(fid: 1)
        }
        XCTAssertTrue(service.isFidActive(1))
    }

    func testConfinedFileSystemRejectsSymlinkEscape() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("airdesk-namespace-\(UUID().uuidString)")
        let outside = fileManager.temporaryDirectory
            .appendingPathComponent("airdesk-outside-\(UUID().uuidString)")
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

        let storage = try ConfinedFileSystemNamespaceStorage(rootURL: root)
        XCTAssertEqual(
            try storage.read(path: "inside.txt", offset: 0, count: 32),
            Data("inside".utf8)
        )
        assertNamespaceError(.symlinkEscape) {
            _ = try storage.read(path: "escape/secret.txt", offset: 0, count: 32)
        }
        assertNamespaceError(.absolutePathRejected) {
            _ = try storage.stat(path: root.appendingPathComponent("inside.txt").path)
        }
    }

    func testErrorStatusMappingCoversSecurityAndConflict() {
        XCTAssertEqual(NamespaceError.leaseDenied.status, .unauthorized)
        XCTAssertEqual(NamespaceError.leaseRevoked.status, .revoked)
        XCTAssertEqual(NamespaceError.symlinkEscape.status, .invalid)
        XCTAssertEqual(NamespaceError.conflict("x").status, .conflict)
        XCTAssertEqual(NamespaceError.io("x").status, .unavailable)
    }

    private func assertNamespaceError(
        _ expected: NamespaceError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? NamespaceError, expected, file: file, line: line)
        }
    }
}
