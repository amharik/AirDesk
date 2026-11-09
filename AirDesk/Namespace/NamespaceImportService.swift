import Foundation

enum NamespaceOperation: String, CaseIterable, Sendable {
    case attach
    case walk
    case open
    case read
    case write
    case clunk
    case stat
    case wstat
}

struct NamespaceLeaseRequest: Equatable, Sendable {
    let leaseId: String?
    let operation: NamespaceOperation
    let path: String
    let mode: AirDesk_Protocol__BindMode?
}

protocol NamespaceLeaseAuthorizing: AnyObject {
    func authorize(_ request: NamespaceLeaseRequest) throws
}

struct NamespaceLeaseGrant: Equatable, Sendable {
    let id: String
    var operations: Set<NamespaceOperation>
    var pathPrefix: String?
    var expiresAt: Date?
    var revoked: Bool
}

final class NamespaceAllowAllLeaseAuthorizer: NamespaceLeaseAuthorizing {
    func authorize(_ request: NamespaceLeaseRequest) throws {
        _ = request
    }
}

final class NamespaceLeaseRegistry: NamespaceLeaseAuthorizing {
    private var grants: [String: NamespaceLeaseGrant] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func grant(
        id: String,
        operations: Set<NamespaceOperation> = Set(NamespaceOperation.allCases),
        pathPrefix: String? = nil,
        expiresAt: Date? = nil
    ) throws {
        guard !id.isEmpty else {
            throw NamespaceError.invalidPath("lease id")
        }
        grants[id] = NamespaceLeaseGrant(
            id: id,
            operations: operations,
            pathPrefix: pathPrefix,
            expiresAt: expiresAt,
            revoked: false
        )
    }

    func revoke(id: String) {
        guard var grant = grants[id] else { return }
        grant.revoked = true
        grants[id] = grant
    }

    func remove(id: String) {
        grants.removeValue(forKey: id)
    }

    func authorize(_ request: NamespaceLeaseRequest) throws {
        guard let leaseId = request.leaseId, let grant = grants[leaseId] else {
            throw NamespaceError.leaseDenied
        }
        guard !grant.revoked else {
            throw NamespaceError.leaseRevoked
        }
        if let expiresAt = grant.expiresAt, expiresAt <= now() {
            throw NamespaceError.leaseExpired
        }
        guard grant.operations.contains(request.operation) else {
            throw NamespaceError.leaseDenied
        }
        if let prefix = grant.pathPrefix, !prefix.isEmpty {
            let normalized = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
            let matches = request.path == normalized
                || request.path.hasPrefix(normalized + "/")
            guard matches else {
                throw NamespaceError.leaseDenied
            }
        }
    }
}

enum NamespaceError: Error, Equatable, LocalizedError {
    case invalidPath(String)
    case absolutePathRejected
    case pathEscapesRoot
    case symlinkEscape
    case notFound(String)
    case notDirectory(String)
    case isDirectory(String)
    case fidInUse(UInt32)
    case fidNotFound(UInt32)
    case fidAlreadyOpen(UInt32)
    case notOpened(UInt32)
    case permissionDenied
    case leaseDenied
    case leaseRevoked
    case leaseExpired
    case tooLarge
    case unsupportedBindMode
    case conflict(String)
    case io(String)

    var status: AirDesk_Protocol__ResourceStatus {
        switch self {
        case .notFound, .fidNotFound:
            return .notFound
        case .permissionDenied, .leaseDenied, .leaseExpired, .notOpened, .unsupportedBindMode:
            return .unauthorized
        case .leaseRevoked:
            return .revoked
        case .fidInUse, .conflict:
            return .conflict
        case .invalidPath, .absolutePathRejected, .pathEscapesRoot, .symlinkEscape,
             .notDirectory, .isDirectory, .fidAlreadyOpen, .tooLarge:
            return .invalid
        case .io:
            return .unavailable
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidPath(let detail):
            return "InvalidPath: \(detail)"
        case .absolutePathRejected:
            return "AbsolutePathRejected: namespace paths must be relative."
        case .pathEscapesRoot:
            return "PathEscapesRoot: parent traversal is not permitted."
        case .symlinkEscape:
            return "SymlinkEscape: the resolved path is outside the namespace root."
        case .notFound(let path):
            return "NotFound: \(path)"
        case .notDirectory(let path):
            return "NotDirectory: \(path)"
        case .isDirectory(let path):
            return "IsDirectory: \(path)"
        case .fidInUse(let fid):
            return "FidInUse: \(fid)"
        case .fidNotFound(let fid):
            return "FidNotFound: \(fid)"
        case .fidAlreadyOpen(let fid):
            return "FidAlreadyOpen: \(fid)"
        case .notOpened(let fid):
            return "NotOpened: \(fid)"
        case .permissionDenied:
            return "PermissionDenied: the fid bind mode does not permit this operation."
        case .leaseDenied:
            return "LeaseDenied: no matching capability lease authorizes this operation."
        case .leaseRevoked:
            return "LeaseRevoked: the capability lease was revoked."
        case .leaseExpired:
            return "LeaseExpired: the capability lease has expired."
        case .tooLarge:
            return "TooLarge: the requested read, write or stat value exceeds its bound."
        case .unsupportedBindMode:
            return "UnsupportedBindMode"
        case .conflict(let detail):
            return "Conflict: \(detail)"
        case .io(let detail):
            return "IO: \(detail)"
        }
    }
}

enum NamespaceLimits {
    static let maxReadBytes = 64 * 1024
    static let maxWriteBytes = 64 * 1024
    static let maxPathSegments = 64
    static let maxSegmentBytes = 255
    static let maxStatNameBytes = 256
    static let maxFileBytes: UInt64 = 64 * 1024 * 1024
}

enum NamespacePathRules {
    static func components(_ path: String) throws -> [String] {
        guard !path.isEmpty else { return [] }
        guard !path.hasPrefix("/") else {
            throw NamespaceError.absolutePathRejected
        }
        var result: [String] = []
        for raw in path.split(separator: "/", omittingEmptySubsequences: false) {
            let segment = String(raw)
            guard !segment.isEmpty else {
                throw NamespaceError.invalidPath(path)
            }
            if segment == "." {
                continue
            }
            try validateSegment(segment)
            result.append(segment)
        }
        return result
    }

    static func validateSegment(_ segment: String) throws {
        guard !segment.isEmpty else {
            throw NamespaceError.invalidPath(segment)
        }
        if segment == ".." {
            throw NamespaceError.pathEscapesRoot
        }
        guard !segment.hasPrefix("/") else {
            throw NamespaceError.absolutePathRejected
        }
        guard !segment.contains("/"), !segment.contains("\0") else {
            throw NamespaceError.invalidPath(segment)
        }
        guard segment.utf8.count <= NamespaceLimits.maxSegmentBytes else {
            throw NamespaceError.tooLarge
        }
    }

    static func append(_ base: String, _ segment: String) throws -> String {
        if segment == "." {
            return base
        }
        try validateSegment(segment)
        return base.isEmpty ? segment : base + "/" + segment
    }
}

struct NamespaceQid: Equatable, Sendable {
    let type: UInt8
    let version: UInt32
    let path: UInt64

    init(type: UInt8, version: UInt32, path: UInt64) {
        self.type = type
        self.version = version
        self.path = path
    }

    init(_ qid: AirDesk_Protocol__Qid?) {
        type = qid?.type ?? 0
        version = qid?.version ?? 0
        path = qid?.path ?? 0
    }

    var isDirectory: Bool {
        type & 0x80 != 0
    }

    var generated: AirDesk_Protocol__Qid {
        AirDesk_Protocol__Qid(type: type, version: version, path: path)
    }

    static func make(path: String, isDirectory: Bool, version: UInt32 = 0) -> NamespaceQid {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return NamespaceQid(type: isDirectory ? 0x80 : 0, version: version, path: hash)
    }
}

struct NamespaceStat: Equatable, Sendable {
    var qid: NamespaceQid
    var mode: UInt32
    var length: UInt64
    var name: String
    var modifiedAt: UInt64

    init(
        qid: NamespaceQid,
        mode: UInt32,
        length: UInt64,
        name: String,
        modifiedAt: UInt64
    ) {
        self.qid = qid
        self.mode = mode
        self.length = length
        self.name = name
        self.modifiedAt = modifiedAt
    }
}

protocol NamespaceStorage: AnyObject {
    func attach(aname: String) throws
    func stat(path: String) throws -> NamespaceStat
    func read(path: String, offset: UInt64, count: Int) throws -> Data
    func write(path: String, offset: UInt64, data: Data, append: Bool) throws -> Int
    func wstat(path: String, stat: NamespaceStat) throws -> String
}

final class InMemoryNamespaceStorage: NamespaceStorage {
    private final class Node {
        var name: String
        let isDirectory: Bool
        var data: Data
        var mode: UInt32
        var modifiedAt: UInt64
        var version: UInt32
        var children: [String: Node]

        init(
            name: String,
            isDirectory: Bool,
            data: Data = Data(),
            mode: UInt32,
            modifiedAt: UInt64 = 0,
            version: UInt32 = 0
        ) {
            self.name = name
            self.isDirectory = isDirectory
            self.data = data
            self.mode = mode
            self.modifiedAt = modifiedAt
            self.version = version
            self.children = [:]
        }
    }

    private let root: Node

    init(entries: [String: Data] = [:]) throws {
        root = Node(name: "", isDirectory: true, mode: 0o755)
        for (path, data) in entries {
            try addFile(path: path, data: data)
        }
    }

    func addFile(path: String, data: Data) throws {
        let components = try NamespacePathRules.components(path)
        guard !components.isEmpty else {
            throw NamespaceError.invalidPath(path)
        }
        var current = root
        for component in components.dropLast() {
            if let existing = current.children[component] {
                guard existing.isDirectory else {
                    throw NamespaceError.notDirectory(path)
                }
                current = existing
            } else {
                let directory = Node(name: component, isDirectory: true, mode: 0o755)
                current.children[component] = directory
                current = directory
            }
        }
        let name = components[components.count - 1]
        if let existing = current.children[name] {
            guard !existing.isDirectory else {
                throw NamespaceError.isDirectory(path)
            }
            existing.data = data
            existing.modifiedAt = Self.nowMilliseconds()
            existing.version &+= 1
        } else {
            current.children[name] = Node(
                name: name,
                isDirectory: false,
                data: data,
                mode: 0o644,
                modifiedAt: Self.nowMilliseconds()
            )
        }
    }

    func attach(aname: String) throws {
        _ = aname
    }

    func stat(path: String) throws -> NamespaceStat {
        let node = try node(for: path)
        let components = try NamespacePathRules.components(path)
        return NamespaceStat(
            qid: .make(path: path, isDirectory: node.isDirectory, version: node.version),
            mode: node.mode,
            length: node.isDirectory ? 0 : UInt64(node.data.count),
            name: components.last ?? "",
            modifiedAt: node.modifiedAt
        )
    }

    func read(path: String, offset: UInt64, count: Int) throws -> Data {
        guard count <= NamespaceLimits.maxReadBytes else {
            throw NamespaceError.tooLarge
        }
        guard offset <= NamespaceLimits.maxFileBytes else {
            throw NamespaceError.tooLarge
        }
        let node = try node(for: path)
        guard !node.isDirectory else {
            throw NamespaceError.isDirectory(path)
        }
        let start = Int(offset)
        guard start < node.data.count else {
            return Data()
        }
        let end = min(node.data.count, start + count)
        return node.data.subdata(in: start..<end)
    }

    func write(path: String, offset: UInt64, data: Data, append: Bool) throws -> Int {
        guard data.count <= NamespaceLimits.maxWriteBytes else {
            throw NamespaceError.tooLarge
        }
        let node = try node(for: path)
        guard !node.isDirectory else {
            throw NamespaceError.isDirectory(path)
        }
        let effectiveOffset = append ? UInt64(node.data.count) : offset
        guard effectiveOffset <= NamespaceLimits.maxFileBytes,
              effectiveOffset + UInt64(data.count) <= NamespaceLimits.maxFileBytes else {
            throw NamespaceError.tooLarge
        }
        let start = Int(effectiveOffset)
        if start > node.data.count {
            node.data.append(Data(repeating: 0, count: start - node.data.count))
        }
        let end = start + data.count
        if end > node.data.count {
            node.data.append(Data(repeating: 0, count: end - node.data.count))
        }
        node.data.replaceSubrange(start..<end, with: data)
        node.modifiedAt = Self.nowMilliseconds()
        node.version &+= 1
        return data.count
    }

    func wstat(path: String, stat: NamespaceStat) throws -> String {
        let components = try NamespacePathRules.components(path)
        guard !components.isEmpty else {
            throw NamespaceError.invalidPath(path)
        }
        let node = try node(for: path)
        var newPath = path

        if !stat.name.isEmpty, stat.name != node.name {
            try NamespacePathRules.validateSegment(stat.name)
            let parent = try parentNode(for: components)
            guard parent.children[stat.name] == nil else {
                throw NamespaceError.conflict(stat.name)
            }
            parent.children.removeValue(forKey: node.name)
            node.name = stat.name
            parent.children[stat.name] = node
            let parentPath = components.dropLast().joined(separator: "/")
            newPath = parentPath.isEmpty ? stat.name : parentPath + "/" + stat.name
        }

        if !node.isDirectory,
           stat.length != UInt64.max,
           stat.length != UInt64(node.data.count) {
            try Self.resize(&node.data, to: stat.length)
        }
        if stat.mode != UInt32.max {
            node.mode = stat.mode & 0o7777
        }
        if stat.modifiedAt != 0 {
            node.modifiedAt = stat.modifiedAt
        }
        node.version &+= 1
        return newPath
    }

    private func node(for path: String) throws -> Node {
        let components = try NamespacePathRules.components(path)
        var current = root
        for component in components {
            guard current.isDirectory else {
                throw NamespaceError.notDirectory(path)
            }
            guard let next = current.children[component] else {
                throw NamespaceError.notFound(path)
            }
            current = next
        }
        return current
    }

    private func parentNode(for components: [String]) throws -> Node {
        guard components.count > 1 else { return root }
        let parentPath = components.dropLast().joined(separator: "/")
        return try node(for: parentPath)
    }

    private static func resize(_ data: inout Data, to length: UInt64) throws {
        guard length <= NamespaceLimits.maxFileBytes else {
            throw NamespaceError.tooLarge
        }
        let target = Int(length)
        if target < data.count {
            data.removeSubrange(target..<data.count)
        } else if target > data.count {
            data.append(Data(repeating: 0, count: target - data.count))
        }
    }

    private static func nowMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}

final class ConfinedFileSystemNamespaceStorage: NamespaceStorage {
    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NamespaceError.notFound(rootURL.path)
        }
        self.rootURL = resolvedRoot
        self.fileManager = fileManager
    }

    func attach(aname: String) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NamespaceError.notFound(aname)
        }
    }

    func stat(path: String) throws -> NamespaceStat {
        let url = try resolve(path: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NamespaceError.notFound(path)
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw NamespaceError.io(error.localizedDescription)
        }
        let directory = isDirectory.boolValue
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint32Value
            ?? (directory ? 0o755 : 0o644)
        let modifiedAt = (attributes[.modificationDate] as? Date)
            .map { UInt64($0.timeIntervalSince1970 * 1000) } ?? 0
        let name = path.isEmpty ? "" : url.lastPathComponent
        guard name.utf8.count <= NamespaceLimits.maxStatNameBytes else {
            throw NamespaceError.tooLarge
        }
        return NamespaceStat(
            qid: .make(path: path, isDirectory: directory),
            mode: mode,
            length: directory ? 0 : size,
            name: name,
            modifiedAt: modifiedAt
        )
    }

    func read(path: String, offset: UInt64, count: Int) throws -> Data {
        guard count <= NamespaceLimits.maxReadBytes else {
            throw NamespaceError.tooLarge
        }
        guard offset <= NamespaceLimits.maxFileBytes else {
            throw NamespaceError.tooLarge
        }
        let url = try resolve(path: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NamespaceError.notFound(path)
        }
        guard !isDirectory.boolValue else {
            throw NamespaceError.isDirectory(path)
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: count) ?? Data()
        } catch {
            throw NamespaceError.io(error.localizedDescription)
        }
    }

    func write(path: String, offset: UInt64, data: Data, append: Bool) throws -> Int {
        guard data.count <= NamespaceLimits.maxWriteBytes else {
            throw NamespaceError.tooLarge
        }
        let url = try resolve(path: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NamespaceError.notFound(path)
        }
        guard !isDirectory.boolValue else {
            throw NamespaceError.isDirectory(path)
        }
        let effectiveOffset = append ? try stat(path: path).length : offset
        guard effectiveOffset <= NamespaceLimits.maxFileBytes,
              effectiveOffset + UInt64(data.count) <= NamespaceLimits.maxFileBytes else {
            throw NamespaceError.tooLarge
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: effectiveOffset)
            try handle.write(contentsOf: data)
            return data.count
        } catch {
            throw NamespaceError.io(error.localizedDescription)
        }
    }

    func wstat(path: String, stat: NamespaceStat) throws -> String {
        let url = try resolve(path: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NamespaceError.notFound(path)
        }
        var finalURL = url
        var newPath = path
        let components = try NamespacePathRules.components(path)

        if !stat.name.isEmpty, stat.name != url.lastPathComponent {
            guard !components.isEmpty else {
                throw NamespaceError.invalidPath(path)
            }
            try NamespacePathRules.validateSegment(stat.name)
            let destination = url.deletingLastPathComponent()
                .appendingPathComponent(stat.name)
                .standardizedFileURL
            guard isWithinRoot(destination) else {
                throw NamespaceError.symlinkEscape
            }
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw NamespaceError.conflict(stat.name)
            }
            do {
                try fileManager.moveItem(at: url, to: destination)
            } catch {
                throw NamespaceError.io(error.localizedDescription)
            }
            finalURL = destination
            let parentPath = components.dropLast().joined(separator: "/")
            newPath = parentPath.isEmpty ? stat.name : parentPath + "/" + stat.name
        }

        do {
            if !isDirectory.boolValue, stat.length != UInt64.max {
                guard stat.length <= NamespaceLimits.maxFileBytes else {
                    throw NamespaceError.tooLarge
                }
                let handle = try FileHandle(forWritingTo: finalURL)
                defer { try? handle.close() }
                try handle.truncate(atOffset: stat.length)
            }
            if stat.mode != UInt32.max {
                try fileManager.setAttributes(
                    [.posixPermissions: stat.mode & 0o7777],
                    ofItemAtPath: finalURL.path
                )
            }
            if stat.modifiedAt != 0 {
                try fileManager.setAttributes(
                    [.modificationDate: Date(timeIntervalSince1970: Double(stat.modifiedAt) / 1000)],
                    ofItemAtPath: finalURL.path
                )
            }
        } catch let error as NamespaceError {
            throw error
        } catch {
            throw NamespaceError.io(error.localizedDescription)
        }
        return newPath
    }

    private func resolve(path: String) throws -> URL {
        let components = try NamespacePathRules.components(path)
        var candidate = rootURL
        for component in components {
            candidate.appendPathComponent(component)
        }
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard isWithinRoot(resolved) else {
            throw NamespaceError.symlinkEscape
        }
        return resolved
    }

    private func isWithinRoot(_ url: URL) -> Bool {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= rootComponents.count else { return false }
        return Array(components.prefix(rootComponents.count)) == rootComponents
    }
}

final class NamespaceImportService {
    private struct FidState {
        var path: String
        var leaseId: String?
        var aname: String
        var mode: AirDesk_Protocol__BindMode?
        var opened: Bool
    }

    private let storage: NamespaceStorage
    private let leaseAuthorizer: NamespaceLeaseAuthorizing
    private var fids: [UInt32: FidState] = [:]

    init(
        storage: NamespaceStorage,
        leaseAuthorizer: NamespaceLeaseAuthorizing = NamespaceAllowAllLeaseAuthorizer()
    ) {
        self.storage = storage
        self.leaseAuthorizer = leaseAuthorizer
    }

    var activeFids: Set<UInt32> {
        Set(fids.keys)
    }

    func isFidActive(_ fid: UInt32) -> Bool {
        fids[fid] != nil
    }

    @discardableResult
    func attach(
        fid: UInt32,
        aname: String,
        uname: String,
        leaseId: String?
    ) throws -> NamespaceStat {
        _ = uname
        guard fids[fid] == nil else {
            throw NamespaceError.fidInUse(fid)
        }
        try NamespacePathRules.validateSegment(aname)
        try authorize(leaseId: leaseId, operation: .attach, path: aname, mode: nil)
        try storage.attach(aname: aname)
        let stat = try storage.stat(path: "")
        fids[fid] = FidState(
            path: "",
            leaseId: leaseId,
            aname: aname,
            mode: nil,
            opened: false
        )
        return stat
    }

    func walk(fid: UInt32, newFid: UInt32, wnames: [String]) throws -> [NamespaceQid] {
        guard let state = fids[fid] else {
            throw NamespaceError.fidNotFound(fid)
        }
        guard !state.opened else {
            throw NamespaceError.fidAlreadyOpen(fid)
        }
        guard wnames.count <= NamespaceLimits.maxPathSegments else {
            throw NamespaceError.tooLarge
        }
        if newFid != fid, fids[newFid] != nil {
            throw NamespaceError.fidInUse(newFid)
        }
        try authorize(state: state, operation: .walk, path: state.path, mode: nil)

        var path = state.path
        var qids: [NamespaceQid] = []
        for (index, name) in wnames.enumerated() {
            if name == "." {
                let stat = try storage.stat(path: path)
                qids.append(stat.qid)
                continue
            }
            let next = try NamespacePathRules.append(path, name)
            try authorize(state: state, operation: .walk, path: next, mode: nil)
            let stat = try storage.stat(path: next)
            if index < wnames.count - 1, !stat.qid.isDirectory {
                throw NamespaceError.notDirectory(next)
            }
            path = next
            qids.append(stat.qid)
        }

        let newState = FidState(
            path: path,
            leaseId: state.leaseId,
            aname: state.aname,
            mode: nil,
            opened: false
        )
        if newFid == fid {
            fids[fid] = newState
        } else {
            fids[newFid] = newState
        }
        return qids
    }

    @discardableResult
    func open(fid: UInt32, mode: AirDesk_Protocol__BindMode) throws -> NamespaceStat {
        guard var state = fids[fid] else {
            throw NamespaceError.fidNotFound(fid)
        }
        guard !state.opened else {
            throw NamespaceError.fidAlreadyOpen(fid)
        }
        try authorize(state: state, operation: .open, path: state.path, mode: mode)
        let stat = try storage.stat(path: state.path)
        state.opened = true
        state.mode = mode
        fids[fid] = state
        return stat
    }

    func read(fid: UInt32, offset: UInt64, count: Int) throws -> Data {
        guard let state = fids[fid] else {
            throw NamespaceError.fidNotFound(fid)
        }
        guard state.opened, let mode = state.mode else {
            throw NamespaceError.notOpened(fid)
        }
        guard mode != .append else {
            throw NamespaceError.permissionDenied
        }
        guard count <= NamespaceLimits.maxReadBytes else {
            throw NamespaceError.tooLarge
        }
        try authorize(state: state, operation: .read, path: state.path, mode: mode)
        return try storage.read(path: state.path, offset: offset, count: count)
    }

    func write(fid: UInt32, offset: UInt64, data: Data) throws -> Int {
        guard let state = fids[fid] else {
            throw NamespaceError.fidNotFound(fid)
        }
        guard state.opened, let mode = state.mode else {
            throw NamespaceError.notOpened(fid)
        }
        guard mode == .readWrite || mode == .append else {
            throw NamespaceError.permissionDenied
        }
        guard data.count <= NamespaceLimits.maxWriteBytes else {
            throw NamespaceError.tooLarge
        }
        try authorize(state: state, operation: .write, path: state.path, mode: mode)
        return try storage.write(
            path: state.path,
            offset: offset,
            data: data,
            append: mode == .append
        )
    }

    func clunk(fid: UInt32) throws {
        guard let state = fids[fid] else {
            throw NamespaceError.fidNotFound(fid)
        }
        try authorize(state: state, operation: .clunk, path: state.path, mode: state.mode)
        fids.removeValue(forKey: fid)
    }

    func stat(fid: UInt32) throws -> NamespaceStat {
        guard let state = fids[fid] else {
            throw NamespaceError.fidNotFound(fid)
        }
        try authorize(state: state, operation: .stat, path: state.path, mode: state.mode)
        return try storage.stat(path: state.path)
    }

    func wstat(fid: UInt32, stat: NamespaceStat) throws {
        guard var state = fids[fid] else {
            throw NamespaceError.fidNotFound(fid)
        }
        guard state.opened, state.mode == .readWrite else {
            throw NamespaceError.permissionDenied
        }
        guard stat.name.utf8.count <= NamespaceLimits.maxStatNameBytes else {
            throw NamespaceError.tooLarge
        }
        try authorize(state: state, operation: .wstat, path: state.path, mode: state.mode)
        state.path = try storage.wstat(path: state.path, stat: stat)
        fids[fid] = state
    }

    private func authorize(
        leaseId: String?,
        operation: NamespaceOperation,
        path: String,
        mode: AirDesk_Protocol__BindMode?
    ) throws {
        try leaseAuthorizer.authorize(
            NamespaceLeaseRequest(
                leaseId: leaseId,
                operation: operation,
                path: path,
                mode: mode
            )
        )
    }

    private func authorize(
        state: FidState,
        operation: NamespaceOperation,
        path: String,
        mode: AirDesk_Protocol__BindMode?
    ) throws {
        try authorize(
            leaseId: state.leaseId,
            operation: operation,
            path: path,
            mode: mode
        )
    }
}
