import CryptoKit
import Foundation
#if canImport(Darwin)
import Darwin
#endif

protocol WorkspaceStore: AnyObject {
    var lastRecoveryWarning: WorkspaceStoreError? { get }

    func load() throws -> WorkspaceManifest?
    @discardableResult
    func commit(_ manifest: WorkspaceManifest, expectedRevision: UInt64?) throws -> WorkspaceManifest
    @discardableResult
    func appendJournal(_ manifest: WorkspaceManifest) throws -> WorkspaceJournalEntry
    func loadJournal() throws -> [WorkspaceJournalEntry]
}

final class NativeWorkspaceStore: WorkspaceStore {
    static let manifestFileName = "workspace.json"
    static let journalFileName = "workspace.journal"

    private let directory: URL
    private let manifestURL: URL
    private let journalURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private(set) var lastRecoveryWarning: WorkspaceStoreError?

    var storageDirectory: URL { directory }
    var syncStateURL: URL { directory.appendingPathComponent("workspace.sync.json") }

    init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent(Self.manifestFileName)
        self.journalURL = directory.appendingPathComponent(Self.journalFileName)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func applicationSupport(fileManager: FileManager = .default) throws -> NativeWorkspaceStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("AirDesk/Workspace", isDirectory: true)
        return try NativeWorkspaceStore(directory: directory, fileManager: fileManager)
    }

    func load() throws -> WorkspaceManifest? {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked()
    }

    @discardableResult
    func commit(_ manifest: WorkspaceManifest, expectedRevision: UInt64?) throws -> WorkspaceManifest {
        lock.lock()
        defer { lock.unlock() }
        return try commitUnlocked(manifest, expectedRevision: expectedRevision)
    }

    @discardableResult
    func appendJournal(_ manifest: WorkspaceManifest) throws -> WorkspaceJournalEntry {
        lock.lock()
        defer { lock.unlock() }

        try manifest.validate()
        var journalManifest = manifest
        let nextSequence = max(
            manifest.recovery.journalSequence,
            try lastJournalSequenceUnlocked()
        ) + 1
        journalManifest.recovery.journalSequence = nextSequence
        journalManifest.recovery.integrityHash = try journalManifest.computedIntegrityHash()

        let entry = WorkspaceJournalEntry(
            sequence: nextSequence,
            revision: journalManifest.revision,
            checkpointSeq: journalManifest.recovery.checkpointSeq,
            createdAt: Date(),
            manifest: journalManifest
        )
        try appendJournalEntryUnlocked(entry)
        return entry
    }

    func loadJournal() throws -> [WorkspaceJournalEntry] {
        lock.lock()
        defer { lock.unlock() }
        return try loadJournalUnlocked()
    }

    private func loadUnlocked() throws -> WorkspaceManifest? {
        lastRecoveryWarning = nil

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            if let recovered = try recoverFromJournalUnlocked() {
                lastRecoveryWarning = .manifestMissing
                try? writeManifest(recovered)
                return recovered
            }
            return nil
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try decodeManifest(data)
            try validate(manifest)
            try verifyIntegrity(manifest)
            return manifest
        } catch {
            let failure = mapLoadError(error)
            lastRecoveryWarning = failure

            if case .unsupportedSchemaVersion = failure {
                throw failure
            }

            if let recovered = try recoverFromJournalUnlocked() {
                try? writeManifest(recovered)
                return recovered
            }
            throw failure
        }
    }

    private func commitUnlocked(
        _ manifest: WorkspaceManifest,
        expectedRevision: UInt64?
    ) throws -> WorkspaceManifest {
        try manifest.validate()

        let current = try loadUnlocked()
        switch (expectedRevision, current?.revision) {
        case (nil, nil):
            break
        case (nil, .some(let revision)):
            throw WorkspaceStoreError.revisionConflict(expected: nil, current: revision)
        case (.some(let expected), nil):
            throw WorkspaceStoreError.revisionConflict(expected: expected, current: 0)
        case (.some(let expected), .some(let revision)):
            guard expected == revision else {
                throw WorkspaceStoreError.revisionConflict(expected: expected, current: revision)
            }
        }

        var committed = manifest
        committed.revision = (current?.revision ?? 0) + 1
        committed.recovery.checkpointSeq = (current?.recovery.checkpointSeq ?? 0) + 1
        committed.recovery.journalSequence = max(
            current?.recovery.journalSequence ?? 0,
            try lastJournalSequenceUnlocked()
        ) + 1
        committed.recovery.lastCheckpointId = "checkpoint.\(committed.recovery.checkpointSeq)"
        committed.recovery.integrityHash = try committed.computedIntegrityHash()

        let entry = WorkspaceJournalEntry(
            sequence: committed.recovery.journalSequence,
            revision: committed.revision,
            checkpointSeq: committed.recovery.checkpointSeq,
            createdAt: Date(),
            manifest: committed
        )

        try appendJournalEntryUnlocked(entry)
        try writeManifest(committed)
        return committed
    }

    private func recoverFromJournalUnlocked() throws -> WorkspaceManifest? {
        let entries = try? loadJournalUnlocked()
        guard let entries else { return nil }

        for entry in entries.reversed() {
            do {
                try validate(entry.manifest)
                try verifyIntegrity(entry.manifest)
                return entry.manifest
            } catch {
                continue
            }
        }
        return nil
    }

    private func loadJournalUnlocked() throws -> [WorkspaceJournalEntry] {
        guard fileManager.fileExists(atPath: journalURL.path) else { return [] }

        let data = try Data(contentsOf: journalURL)
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var entries: [WorkspaceJournalEntry] = []
        entries.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            do {
                let entry = try decoder.decode(WorkspaceJournalEntry.self, from: Data(line.utf8))
                entries.append(entry)
            } catch {
                let lineNumber = index + 1
                if index == lines.count - 1 {
                    lastRecoveryWarning = .corruptJournal(line: lineNumber)
                    break
                }
                throw WorkspaceStoreError.corruptJournal(line: lineNumber)
            }
        }
        return entries
    }

    private func lastJournalSequenceUnlocked() throws -> UInt64 {
        try loadJournalUnlocked().last?.sequence ?? 0
    }

    private func appendJournalEntryUnlocked(_ entry: WorkspaceJournalEntry) throws {
        if !fileManager.fileExists(atPath: journalURL.path) {
            guard fileManager.createFile(atPath: journalURL.path, contents: nil) else {
                throw WorkspaceStoreError.writeFailed("Could not create the workspace journal.")
            }
            setFileProtection(journalURL)
        }

        var data = try encoder.encode(entry)
        data.append(0x0A)

        do {
            try repairJournalTailUnlocked()
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try synchronize(handle)
        } catch {
            throw WorkspaceStoreError.writeFailed(error.localizedDescription)
        }
    }

    private func repairJournalTailUnlocked() throws {
        guard fileManager.fileExists(atPath: journalURL.path) else { return }

        let data = try Data(contentsOf: journalURL)
        guard !data.isEmpty, data.last != 0x0A else { return }

        let text = String(decoding: data, as: UTF8.self)
        let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let lastLineIsComplete = !lastLine.isEmpty
            && (try? decoder.decode(WorkspaceJournalEntry.self, from: Data(lastLine.utf8))) != nil

        let targetLength: UInt64
        if lastLineIsComplete {
            targetLength = UInt64(data.count)
        } else if let lastNewline = data.lastIndex(of: 0x0A) {
            targetLength = UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)
        } else {
            targetLength = 0
        }

        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        try handle.truncate(atOffset: targetLength)
        try handle.seekToEnd()
        if lastLineIsComplete {
            try handle.write(contentsOf: Data([0x0A]))
        }
        try synchronize(handle)
    }

    private func writeManifest(_ manifest: WorkspaceManifest) throws {
        let data = try encoder.encode(manifest)
        let temporaryURL = directory.appendingPathComponent(
            "\(Self.manifestFileName).tmp-\(UUID().uuidString)"
        )

        do {
            guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
                throw WorkspaceStoreError.writeFailed("Could not create the workspace manifest.")
            }
            setFileProtection(temporaryURL)

            let handle = try FileHandle(forWritingTo: temporaryURL)
            try handle.write(contentsOf: data)
            try synchronize(handle)
            try handle.close()

            if fileManager.fileExists(atPath: manifestURL.path) {
                _ = try fileManager.replaceItemAt(
                    manifestURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: manifestURL)
            }
            synchronizeDirectory()
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if let storeError = error as? WorkspaceStoreError {
                throw storeError
            }
            throw WorkspaceStoreError.writeFailed(error.localizedDescription)
        }
    }

    private func decodeManifest(_ data: Data) throws -> WorkspaceManifest {
        do {
            return try decoder.decode(WorkspaceManifest.self, from: data)
        } catch {
            throw WorkspaceStoreError.corruptManifest
        }
    }

    private func validate(_ manifest: WorkspaceManifest) throws {
        do {
            try manifest.validate()
        } catch let error as WorkspaceManifestError {
            if case .unsupportedSchemaVersion(let version) = error {
                throw WorkspaceStoreError.unsupportedSchemaVersion(version)
            }
            throw WorkspaceStoreError.invalidManifest(error.localizedDescription)
        }
    }

    private func verifyIntegrity(_ manifest: WorkspaceManifest) throws {
        guard let storedHash = manifest.recovery.integrityHash, !storedHash.isEmpty else {
            throw WorkspaceStoreError.missingIntegrityHash
        }
        let computedHash = try manifest.computedIntegrityHash()
        guard storedHash == computedHash else {
            throw WorkspaceStoreError.integrityMismatch
        }
    }

    private func mapLoadError(_ error: Error) -> WorkspaceStoreError {
        if let storeError = error as? WorkspaceStoreError {
            return storeError
        }
        return .readFailed(error.localizedDescription)
    }

    private func synchronize(_ handle: FileHandle) throws {
        #if canImport(Darwin)
        if fcntl(handle.fileDescriptor, F_FULLFSYNC, 0) != -1 {
            return
        }
        if fsync(handle.fileDescriptor) == 0 {
            return
        }
        throw WorkspaceStoreError.writeFailed(String(cString: strerror(errno)))
        #else
        try handle.synchronize()
        #endif
    }

    private func synchronizeDirectory() {
        #if canImport(Darwin)
        directory.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            let descriptor = open(path, O_RDONLY)
            guard descriptor >= 0 else { return }
            _ = fsync(descriptor)
            close(descriptor)
        }
        #endif
    }

    private func setFileProtection(_ url: URL) {
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
        #endif
    }
}

struct WorkspaceJournalEntry: Codable, Equatable, Sendable {
    var sequence: UInt64
    var revision: UInt64
    var checkpointSeq: UInt64
    var createdAt: Date
    var manifest: WorkspaceManifest
}

enum WorkspaceStoreError: Error, Equatable, LocalizedError {
    case revisionConflict(expected: UInt64?, current: UInt64)
    case unsupportedSchemaVersion(Int)
    case invalidManifest(String)
    case corruptManifest
    case manifestMissing
    case missingIntegrityHash
    case integrityMismatch
    case corruptJournal(line: Int)
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .revisionConflict(let expected, let current):
            if let expected {
                return "Workspace revision conflict: expected \(expected), current \(current)."
            }
            return "Workspace already exists at revision \(current)."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported workspace schema version \(version)."
        case .invalidManifest(let detail):
            return "Invalid workspace manifest: \(detail)"
        case .corruptManifest:
            return "The workspace manifest is corrupt."
        case .manifestMissing:
            return "The workspace manifest was missing and was recovered from the journal."
        case .missingIntegrityHash:
            return "The workspace manifest has no integrity hash."
        case .integrityMismatch:
            return "The workspace manifest integrity check failed."
        case .corruptJournal(let line):
            return "The workspace journal is corrupt at line \(line)."
        case .readFailed(let detail):
            return "Could not read workspace state: \(detail)"
        case .writeFailed(let detail):
            return "Could not write workspace state: \(detail)"
        }
    }
}

extension WorkspaceManifest {
    func computedIntegrityHash() throws -> String {
        var copy = self
        copy.recovery.integrityHash = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(copy)
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
