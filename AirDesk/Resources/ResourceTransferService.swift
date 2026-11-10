import Foundation

enum ResourceTransferEntryKind: String, Equatable {
    case file
    case directory
}

struct ResourceTransferStat: Equatable {
    var path: String
    var kind: ResourceTransferEntryKind
    var size: UInt64
    var mode: UInt32
    var name: String
    var modifiedAtMillis: UInt64
}

enum ResourceTransferEventKind: String, Equatable {
    case stat
    case read
    case write
}

enum ResourceTransferEventOutcome: String, Equatable {
    case success
    case denied
    case failed
}

struct ResourceTransferEvent: Equatable {
    var sequence: UInt64
    var timestampMillis: Int64
    var kind: ResourceTransferEventKind
    var outcome: ResourceTransferEventOutcome
    var path: String
    var byteCount: Int
    var offset: UInt64
}

struct ResourceTransferLimits: Equatable {
    static let standard = ResourceTransferLimits()

    static let eventPathCharacters = 512

    var maxReadBytes = 64 * 1_024
    var maxWriteBytes = 64 * 1_024
    var maxFileBytes: UInt64 = 64 * 1_024 * 1_024
    var maxPathBytes = 4_096
    var maxPathSegments = 64
    var maxPathSegmentBytes = 255
    var maxStatNameBytes = 255
    var maxEvents = 128

    func validate() throws {
        guard maxReadBytes > 0 else {
            throw ResourceTransferError.invalidLimits("maxReadBytes")
        }
        guard maxWriteBytes > 0 else {
            throw ResourceTransferError.invalidLimits("maxWriteBytes")
        }
        guard maxFileBytes > 0 else {
            throw ResourceTransferError.invalidLimits("maxFileBytes")
        }
        guard maxPathBytes > 0 else {
            throw ResourceTransferError.invalidLimits("maxPathBytes")
        }
        guard maxPathSegments > 0 else {
            throw ResourceTransferError.invalidLimits("maxPathSegments")
        }
        guard maxPathSegmentBytes > 0 else {
            throw ResourceTransferError.invalidLimits("maxPathSegmentBytes")
        }
        guard maxStatNameBytes > 0 else {
            throw ResourceTransferError.invalidLimits("maxStatNameBytes")
        }
        guard maxEvents > 0 else {
            throw ResourceTransferError.invalidLimits("maxEvents")
        }
    }
}

enum ResourceTransferError: Error, Equatable, LocalizedError {
    case invalidLimits(String)
    case closed
    case invalidPath(String)
    case absolutePathRejected
    case pathEscapesRoot
    case symlinkEscape
    case notFound(String)
    case isDirectory(String)
    case notRegularFile(String)
    case readTooLarge(Int)
    case writeTooLarge(Int)
    case fileTooLarge
    case offsetOutOfBounds
    case io(String)

    var isDenied: Bool {
        switch self {
        case .invalidPath, .absolutePathRejected, .pathEscapesRoot, .symlinkEscape:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidLimits(let field):
            return "Invalid resource transfer limit: \(field)."
        case .closed:
            return "The resource transfer service is closed."
        case .invalidPath(let reason):
            return "Invalid resource path: \(reason)."
        case .absolutePathRejected:
            return "Absolute resource paths are not permitted."
        case .pathEscapesRoot:
            return "Parent traversal is outside the resource root."
        case .symlinkEscape:
            return "The resolved path is outside the resource root."
        case .notFound(let path):
            return "The resource does not exist: \(path)"
        case .isDirectory(let path):
            return "The resource is a directory: \(path)"
        case .notRegularFile(let path):
            return "The resource is not a regular file: \(path)"
        case .readTooLarge(let count):
            return "The read request is too large: \(count) bytes."
        case .writeTooLarge(let count):
            return "The write request is too large: \(count) bytes."
        case .fileTooLarge:
            return "The resulting file would exceed the transfer limit."
        case .offsetOutOfBounds:
            return "The transfer offset is outside the file."
        case .io(let reason):
            return "Resource transfer failed: \(reason)."
        }
    }
}

final class ResourceTransferService {
    private let root: ResourceRoot
    private let limits: ResourceTransferLimits
    private let fileManager: FileManager
    private let nowMillis: () -> Int64
    private var securityScopeActive = false
    private var closed = false
    private var nextSequence: UInt64 = 0

    private(set) var events: [ResourceTransferEvent] = []
    var onEvent: ((ResourceTransferEvent) -> Void)?

    init(
        root: ResourceRoot,
        limits: ResourceTransferLimits = .standard,
        fileManager: FileManager = .default,
        nowMillis: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) throws {
        try limits.validate()
        self.root = root
        self.limits = limits
        self.fileManager = fileManager
        self.nowMillis = nowMillis
        securityScopeActive = root.startAccessingSecurityScope()
    }

    deinit {
        if securityScopeActive {
            root.stopAccessingSecurityScope()
        }
    }

    var isClosed: Bool {
        closed
    }

    func close() {
        guard !closed else { return }
        closed = true
        if securityScopeActive {
            securityScopeActive = false
            root.stopAccessingSecurityScope()
        }
    }

    func stat(path: String) throws -> ResourceTransferStat {
        try ensureOpen(.stat, path: path, offset: 0)
        do {
            let url = try resolve(path)
            let attributes = try attributes(at: url, path: path)
            let entryKind: ResourceTransferEntryKind
            if let type = attributes[.type] as? FileAttributeType, type == .typeDirectory {
                entryKind = .directory
            } else if let type = attributes[.type] as? FileAttributeType, type == .typeRegular {
                entryKind = .file
            } else {
                throw ResourceTransferError.notRegularFile(path)
            }

            let name = url.lastPathComponent
            guard name.utf8.count <= limits.maxStatNameBytes else {
                throw ResourceTransferError.invalidPath("stat name is too long")
            }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let mode = (attributes[.posixPermissions] as? NSNumber)?.uint32Value
                ?? (entryKind == .directory ? 0o755 : 0o644)
            let modifiedAt = (attributes[.modificationDate] as? Date)
                .map { UInt64(max(0, $0.timeIntervalSince1970 * 1_000)) } ?? 0
            let result = ResourceTransferStat(
                path: path,
                kind: entryKind,
                size: entryKind == .directory ? 0 : size,
                mode: mode,
                name: name,
                modifiedAtMillis: modifiedAt
            )
            record(.stat, outcome: .success, path: path, byteCount: 0, offset: 0)
            return result
        } catch {
            throw failure(.stat, path: path, offset: 0, error: error)
        }
    }

    func read(
        path: String,
        offset: UInt64 = 0,
        count: Int? = nil
    ) throws -> Data {
        try ensureOpen(.read, path: path, offset: offset)
        do {
            let requestedCount = count ?? limits.maxReadBytes
            guard requestedCount >= 0, requestedCount <= limits.maxReadBytes else {
                throw ResourceTransferError.readTooLarge(requestedCount)
            }
            guard offset <= limits.maxFileBytes else {
                throw ResourceTransferError.offsetOutOfBounds
            }
            let url = try resolve(path)
            let attributes = try attributes(at: url, path: path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                if (attributes[.type] as? FileAttributeType) == .typeDirectory {
                    throw ResourceTransferError.isDirectory(path)
                }
                throw ResourceTransferError.notRegularFile(path)
            }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard offset <= size else {
                throw ResourceTransferError.offsetOutOfBounds
            }
            let available = size - offset
            let requested = UInt64(requestedCount)
            let readCount = Int(Swift.min(available, requested))
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: readCount) ?? Data()
            record(.read, outcome: .success, path: path, byteCount: data.count, offset: offset)
            return data
        } catch {
            throw failure(.read, path: path, offset: offset, error: error)
        }
    }

    func write(
        path: String,
        offset: UInt64 = 0,
        data: Data,
        append: Bool = false
    ) throws -> Int {
        try ensureOpen(.write, path: path, offset: offset)
        do {
            guard data.count <= limits.maxWriteBytes else {
                throw ResourceTransferError.writeTooLarge(data.count)
            }
            guard offset <= limits.maxFileBytes else {
                throw ResourceTransferError.fileTooLarge
            }
            let url = try resolve(path)
            let attributes = try attributes(at: url, path: path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                if (attributes[.type] as? FileAttributeType) == .typeDirectory {
                    throw ResourceTransferError.isDirectory(path)
                }
                throw ResourceTransferError.notRegularFile(path)
            }
            let currentSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let effectiveOffset = append ? currentSize : offset
            guard effectiveOffset <= limits.maxFileBytes,
                  UInt64(data.count) <= limits.maxFileBytes - effectiveOffset else {
                throw ResourceTransferError.fileTooLarge
            }
            if data.isEmpty {
                record(.write, outcome: .success, path: path, byteCount: 0, offset: effectiveOffset)
                return 0
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: effectiveOffset)
            try handle.write(contentsOf: data)
            record(
                .write,
                outcome: .success,
                path: path,
                byteCount: data.count,
                offset: effectiveOffset
            )
            return data.count
        } catch {
            throw failure(.write, path: path, offset: offset, error: error)
        }
    }

    private func ensureOpen(
        _ kind: ResourceTransferEventKind,
        path: String,
        offset: UInt64
    ) throws {
        guard !closed else {
            throw failure(kind, path: path, offset: offset, error: ResourceTransferError.closed)
        }
    }

    private func resolve(_ path: String) throws -> URL {
        guard path.utf8.count <= limits.maxPathBytes else {
            throw ResourceTransferError.invalidPath("path is too long")
        }
        guard !path.contains("\0") else {
            throw ResourceTransferError.invalidPath("path contains a NUL byte")
        }
        guard !path.hasPrefix("/") else {
            throw ResourceTransferError.absolutePathRejected
        }

        var components: [String] = []
        if !path.isEmpty {
            let rawComponents = path.split(separator: "/", omittingEmptySubsequences: false)
            for raw in rawComponents {
                let segment = String(raw)
                guard !segment.isEmpty else {
                    throw ResourceTransferError.invalidPath(path)
                }
                if segment == "." {
                    continue
                }
                guard segment != ".." else {
                    throw ResourceTransferError.pathEscapesRoot
                }
                guard segment.utf8.count <= limits.maxPathSegmentBytes else {
                    throw ResourceTransferError.invalidPath("path segment is too long")
                }
                components.append(segment)
                guard components.count <= limits.maxPathSegments else {
                    throw ResourceTransferError.invalidPath("too many path segments")
                }
            }
        }

        var candidate = root.url
        for component in components {
            candidate.appendPathComponent(component)
        }
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard isInsideRoot(resolved) else {
            throw ResourceTransferError.symlinkEscape
        }
        return resolved
    }

    private func attributes(
        at url: URL,
        path: String
    ) throws -> [FileAttributeKey: Any] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ResourceTransferError.notFound(path)
        }
        do {
            return try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw ResourceTransferError.io(error.localizedDescription)
        }
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootComponents = root.url.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= rootComponents.count else { return false }
        return Array(components.prefix(rootComponents.count)) == rootComponents
    }

    private func failure(
        _ kind: ResourceTransferEventKind,
        path: String,
        offset: UInt64,
        error: Error
    ) -> ResourceTransferError {
        let typed = error as? ResourceTransferError
            ?? ResourceTransferError.io(error.localizedDescription)
        record(
            kind,
            outcome: typed.isDenied ? .denied : .failed,
            path: path,
            byteCount: 0,
            offset: offset
        )
        return typed
    }

    private func record(
        _ kind: ResourceTransferEventKind,
        outcome: ResourceTransferEventOutcome,
        path: String,
        byteCount: Int,
        offset: UInt64
    ) {
        nextSequence += 1
        let event = ResourceTransferEvent(
            sequence: nextSequence,
            timestampMillis: nowMillis(),
            kind: kind,
            outcome: outcome,
            path: String(path.prefix(ResourceTransferLimits.eventPathCharacters)),
            byteCount: byteCount,
            offset: offset
        )
        events.append(event)
        if events.count > limits.maxEvents {
            events.removeFirst(events.count - limits.maxEvents)
        }
        onEvent?(event)
    }
}
