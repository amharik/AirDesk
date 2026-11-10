import XCTest
@testable import AirDesk

final class ResourceTransferServiceTests: XCTestCase {
    private var baseURL: URL!

    override func setUpWithError() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResourceTransferServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outsideURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let baseURL {
            try? FileManager.default.removeItem(at: baseURL)
        }
    }

    func testAppScopedRootIsInsideDocuments() throws {
        let root = try ResourceRoot.appDocuments()

        XCTAssertEqual(root.kind, .appDocuments)
        XCTAssertEqual(root.id, ResourceRoot.defaultAppDocumentsIdentifier)
        XCTAssertFalse(root.startAccessingSecurityScope())
        XCTAssertEqual(
            try ResourceRoot(
                id: ResourceRoot.defaultAppDocumentsIdentifier,
                kind: .appDocuments,
                url: root.url
            ),
            root
        )
    }

    func testRootsRejectDeviceWideMissingAndNonDirectoryPaths() throws {
        XCTAssertThrowsError(try ResourceRoot(
            id: "root",
            kind: .userSelected,
            url: URL(fileURLWithPath: "/", isDirectory: true)
        )) { error in
            XCTAssertEqual(error as? ResourceRootError, .deviceWideAccessDenied)
        }

        XCTAssertThrowsError(try ResourceRoot(
            id: "root",
            kind: .userSelected,
            url: baseURL.appendingPathComponent("missing", isDirectory: true)
        )) { error in
            guard case .rootNotFound = error as? ResourceRootError else {
                return XCTFail("Expected rootNotFound")
            }
        }

        let file = rootURL.appendingPathComponent("file.txt")
        try Data("file".utf8).write(to: file)
        XCTAssertThrowsError(try ResourceRoot(
            id: "root",
            kind: .userSelected,
            url: file
        )) { error in
            guard case .notDirectory = error as? ResourceRootError else {
                return XCTFail("Expected notDirectory")
            }
        }

        XCTAssertThrowsError(try ResourceRoot(
            id: "root",
            kind: .userSelected,
            url: URL(string: "https://example.com")!
        )) { error in
            XCTAssertEqual(error as? ResourceRootError, .notFileURL)
        }

        XCTAssertThrowsError(try ResourceRoot(
            id: " ",
            kind: .userSelected,
            url: rootURL
        )) { error in
            XCTAssertEqual(error as? ResourceRootError, .invalidIdentifier)
        }

        XCTAssertThrowsError(try ResourceRoot(
            id: "app",
            kind: .appDocuments,
            url: rootURL
        )) { error in
            XCTAssertEqual(error as? ResourceRootError, .appScopedRootOutsideContainer)
        }
    }

    func testStatReadWriteAndAppendStayInsideRoot() throws {
        let file = rootURL.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: file)
        let service = try makeService()

        let stat = try service.stat(path: "notes.txt")
        XCTAssertEqual(stat.kind, .file)
        XCTAssertEqual(stat.name, "notes.txt")
        XCTAssertEqual(stat.size, 5)

        let middle = try service.read(path: "notes.txt", offset: 1, count: 3)
        XCTAssertEqual(middle, Data("ell".utf8))

        XCTAssertEqual(
            try service.write(path: "notes.txt", offset: 0, data: Data("H".utf8)),
            1
        )
        XCTAssertEqual(
            try service.write(path: "notes.txt", data: Data("!".utf8), append: true),
            1
        )
        XCTAssertEqual(try service.read(path: "notes.txt"), Data("Hello!".utf8))

        XCTAssertEqual(service.events.map(\.kind), [.stat, .read, .write, .write, .read])
        XCTAssertTrue(service.events.allSatisfy { $0.outcome == .success })
        XCTAssertEqual(service.events.map(\.sequence), [1, 2, 3, 4, 5])
    }

    func testAbsoluteTraversalAndMalformedPathsAreDenied() throws {
        let secret = outsideURL.appendingPathComponent("secret.txt")
        try Data("outside".utf8).write(to: secret)
        let service = try makeService()

        assertTransferError(.absolutePathRejected) {
            _ = try service.read(path: secret.path)
        }
        assertTransferError(.pathEscapesRoot) {
            _ = try service.read(path: "../outside/secret.txt")
        }
        assertTransferError(.invalidPath("nested//file")) {
            _ = try service.read(path: "nested//file")
        }
        assertTransferError(.invalidPath("path is too long")) {
            _ = try service.read(path: String(repeating: "a", count: 4_097))
        }

        XCTAssertEqual(service.events.last?.outcome, .denied)
    }

    func testSymlinkEscapeIsDeniedAndInternalSymlinkResolves() throws {
        let secret = outsideURL.appendingPathComponent("secret.txt")
        try Data("outside".utf8).write(to: secret)
        let escape = rootURL.appendingPathComponent("escape.txt")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: secret)

        let target = rootURL.appendingPathComponent("target.txt")
        try Data("inside".utf8).write(to: target)
        let internalLink = rootURL.appendingPathComponent("inside-link.txt")
        try FileManager.default.createSymbolicLink(
            at: internalLink,
            withDestinationURL: target
        )

        let service = try makeService()

        assertTransferError(.symlinkEscape) {
            _ = try service.read(path: "escape.txt")
        }
        XCTAssertEqual(try service.read(path: "inside-link.txt"), Data("inside".utf8))
        XCTAssertEqual(service.events.last?.outcome, .success)
    }

    func testDirectoriesAndMissingFilesFailTyped() throws {
        let service = try makeService()

        assertTransferError(.isDirectory("")) {
            _ = try service.read(path: "")
        }
        assertTransferError(.isDirectory("")) {
            _ = try service.write(path: "", data: Data("x".utf8))
        }
        assertTransferError(.notFound("missing.txt")) {
            _ = try service.stat(path: "missing.txt")
        }
        XCTAssertEqual(service.events.last?.outcome, .failed)
    }

    func testReadWriteAndFileSizeLimitsAreBounded() throws {
        var limits = ResourceTransferLimits.standard
        limits.maxReadBytes = 4
        limits.maxWriteBytes = 4
        limits.maxFileBytes = 6
        let file = rootURL.appendingPathComponent("small.txt")
        try Data("abc".utf8).write(to: file)
        let service = try makeService(limits: limits)

        assertTransferError(.readTooLarge(5)) {
            _ = try service.read(path: "small.txt", count: 5)
        }
        assertTransferError(.offsetOutOfBounds) {
            _ = try service.read(path: "small.txt", offset: 4)
        }
        assertTransferError(.writeTooLarge(5)) {
            _ = try service.write(path: "small.txt", data: Data(repeating: 1, count: 5))
        }
        assertTransferError(.fileTooLarge) {
            _ = try service.write(
                path: "small.txt",
                offset: 6,
                data: Data([1])
            )
        }
        assertTransferError(.fileTooLarge) {
            _ = try service.write(
                path: "small.txt",
                data: Data(repeating: 2, count: 4),
                append: true
            )
        }

        XCTAssertEqual(try service.read(path: "small.txt"), Data("abc".utf8))
    }

    func testPathLimitsAreBounded() throws {
        var limits = ResourceTransferLimits.standard
        limits.maxPathSegments = 2
        limits.maxPathSegmentBytes = 3
        let service = try makeService(limits: limits)

        assertTransferError(.invalidPath("too many path segments")) {
            _ = try service.stat(path: "a/b/c")
        }
        assertTransferError(.invalidPath("path segment is too long")) {
            _ = try service.stat(path: "abcd")
        }
    }

    func testTransferEventsAreBoundedAndCallbacksContinue() throws {
        let file = rootURL.appendingPathComponent("events.txt")
        try Data("events".utf8).write(to: file)
        var limits = ResourceTransferLimits.standard
        limits.maxEvents = 2
        let service = try makeService(limits: limits)
        var callbacks: [ResourceTransferEvent] = []
        service.onEvent = { callbacks.append($0) }

        _ = try service.stat(path: "events.txt")
        _ = try service.read(path: "events.txt")
        _ = try service.write(path: "events.txt", offset: 0, data: Data("E".utf8))

        XCTAssertEqual(callbacks.count, 3)
        XCTAssertEqual(service.events.count, 2)
        XCTAssertEqual(service.events.map(\.sequence), [2, 3])
        XCTAssertEqual(service.events.last?.kind, .write)
        XCTAssertEqual(service.events.last?.byteCount, 1)
    }

    func testCloseReleasesAccessAndRejectsOperations() throws {
        let file = rootURL.appendingPathComponent("closed.txt")
        try Data("closed".utf8).write(to: file)
        let service = try makeService()

        service.close()
        service.close()

        XCTAssertTrue(service.isClosed)
        assertTransferError(.closed) {
            _ = try service.read(path: "closed.txt")
        }
        XCTAssertEqual(service.events.last?.outcome, .failed)
    }

    private var rootURL: URL {
        baseURL.appendingPathComponent("root", isDirectory: true)
    }

    private var outsideURL: URL {
        baseURL.appendingPathComponent("outside", isDirectory: true)
    }

    private func makeService(
        limits: ResourceTransferLimits = .standard
    ) throws -> ResourceTransferService {
        let root = try ResourceRoot(id: "user-root", kind: .userSelected, url: rootURL)
        return try ResourceTransferService(
            root: root,
            limits: limits,
            nowMillis: { 1_000 }
        )
    }

    private func assertTransferError(
        _ expected: ResourceTransferError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ResourceTransferError, expected, file: file, line: line)
        }
    }
}
