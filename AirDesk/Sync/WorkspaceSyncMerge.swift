import AirDeskCore
import Foundation

indirect enum WorkspaceSyncJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([WorkspaceSyncJSONValue])
    case object([String: WorkspaceSyncJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WorkspaceSyncJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: WorkspaceSyncJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported workspace sync JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var objectValue: [String: WorkspaceSyncJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [WorkspaceSyncJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var uint64Value: UInt64? {
        guard case .number(let value) = self,
              value >= 0,
              value.rounded() == value,
              value <= Double(UInt64.max) else {
            return nil
        }
        return UInt64(value)
    }

    var canonicalString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct WorkspaceSyncLWWValue: Codable, Equatable, Sendable {
    var value: WorkspaceSyncJSONValue
    var revision: UInt64
    var deviceId: String

    init(value: WorkspaceSyncJSONValue, revision: UInt64, deviceId: String) {
        self.value = value
        self.revision = revision
        self.deviceId = deviceId
    }

    init?(json: WorkspaceSyncJSONValue) {
        guard let object = json.objectValue,
              let value = object["value"],
              let revision = object["revision"]?.uint64Value,
              let deviceId = object["deviceId"]?.stringValue else {
            return nil
        }
        self.init(value: value, revision: revision, deviceId: deviceId)
    }

    var json: WorkspaceSyncJSONValue {
        .object([
            "value": value,
            "revision": .number(Double(revision)),
            "deviceId": .string(deviceId)
        ])
    }
}

struct WorkspaceSyncAppendEntry: Codable, Equatable, Sendable {
    var id: String
    var value: WorkspaceSyncJSONValue
    var revision: UInt64?

    init(id: String, value: WorkspaceSyncJSONValue, revision: UInt64? = nil) {
        self.id = id
        self.value = value
        self.revision = revision
    }

    init?(json: WorkspaceSyncJSONValue) {
        guard let object = json.objectValue,
              let id = object["id"]?.stringValue,
              let value = object["value"] else {
            return nil
        }
        self.init(id: id, value: value, revision: object["revision"]?.uint64Value)
    }

    var json: WorkspaceSyncJSONValue {
        var object: [String: WorkspaceSyncJSONValue] = [
            "id": .string(id),
            "value": value
        ]
        if let revision {
            object["revision"] = .number(Double(revision))
        }
        return .object(object)
    }
}

enum WorkspaceSyncConflictReason: String, Codable, Sendable {
    case manualMerge = "manual-merge"
    case unclassifiedField = "unclassified-field"
    case ambiguousLWW = "ambiguous-lww"
    case appendLogDuplicateConflict = "append-log-duplicate-conflict"
    case invalidValue = "invalid-value"
}

struct WorkspaceSyncFieldConflict: Codable, Equatable, Sendable {
    var path: String
    var merge: WorkspaceMergeClass
    var reason: WorkspaceSyncConflictReason
    var local: WorkspaceSyncJSONValue?
    var remote: WorkspaceSyncJSONValue?
}

enum WorkspaceSyncMergeStatus: String, Codable, Sendable {
    case merged
    case unchanged
    case conflict
}

enum WorkspaceSyncWinner: String, Codable, Sendable {
    case local
    case remote
}

struct WorkspaceSyncFieldResult: Codable, Equatable, Sendable {
    var path: String
    var merge: WorkspaceMergeClass
    var status: WorkspaceSyncMergeStatus
    var changed: Bool
    var value: WorkspaceSyncJSONValue? = nil
    var winner: WorkspaceSyncWinner? = nil
    var conflicts: [WorkspaceSyncFieldConflict] = []
}

enum WorkspaceSyncLWWWinner: String, Sendable {
    case local
    case remote
    case equal
    case conflict
}

struct WorkspaceSyncLWWResult: Sendable {
    var winner: WorkspaceSyncLWWWinner
    var value: WorkspaceSyncLWWValue? = nil
    var conflict: WorkspaceSyncFieldConflict? = nil
}

struct WorkspaceSyncAppendLogResult: Sendable {
    var entries: [WorkspaceSyncAppendEntry]
    var added: Int
    var duplicates: [String]
    var conflicts: [WorkspaceSyncFieldConflict]
}

struct WorkspaceSyncMergeRegistry {
    private let classes: [String: WorkspaceMergeClass]
    let entries: [WorkspaceFieldMetadata]

    init(_ metadata: [WorkspaceFieldMetadata] = []) {
        self.entries = metadata
        var classes: [String: WorkspaceMergeClass] = [:]
        for entry in metadata {
            classes[entry.path] = entry.merge
        }
        self.classes = classes
    }

    func mergeClass(for path: String) -> WorkspaceMergeClass {
        classes[path] ?? .manual
    }

    func has(_ path: String) -> Bool {
        classes[path] != nil
    }
}

struct WorkspaceSyncSnapshot: Codable, Equatable, Sendable {
    var workspaceId: String
    var hostEpoch: UInt64
    var workspaceSeq: UInt64
    var revision: UInt64
    var fields: [String: WorkspaceSyncJSONValue]
    var metadata: [WorkspaceFieldMetadata]
}

struct WorkspaceSyncFieldPatch: Codable, Equatable, Sendable {
    var path: String
    var value: WorkspaceSyncJSONValue
    var revision: UInt64
    var deviceId: String
    var appendId: String?
}

struct WorkspaceSyncPatch: Codable, Equatable, Sendable {
    var workspaceId: String
    var senderDeviceId: String
    var hostEpoch: UInt64
    var baseWorkspaceSeq: UInt64
    var revision: UInt64
    var fields: [WorkspaceSyncFieldPatch]
}

enum WorkspaceSyncRejectReason: String, Codable, Sendable {
    case workspaceMismatch = "workspace-mismatch"
    case staleEpoch = "stale-epoch"
    case futureEpoch = "future-epoch"
    case staleSeq = "stale-seq"
    case futureSeq = "future-seq"
    case staleRevision = "stale-revision"
    case invalidPatch = "invalid-patch"
    case interrupted
}

enum WorkspaceSyncApplyStatus: String, Codable, Sendable {
    case applied
    case unchanged
    case conflict
    case rejected
}

struct WorkspaceSyncApplyHooks {
    var afterField: ((String) throws -> Void)?

    init(afterField: ((String) throws -> Void)? = nil) {
        self.afterField = afterField
    }
}

struct WorkspaceSyncApplyResult: Codable, Sendable {
    var status: WorkspaceSyncApplyStatus
    var snapshot: WorkspaceSyncSnapshot
    var fieldResults: [WorkspaceSyncFieldResult]
    var conflicts: [WorkspaceSyncFieldConflict]
    var reason: WorkspaceSyncRejectReason? = nil

    var isAccepted: Bool {
        status == .applied || status == .unchanged
    }
}

enum WorkspaceSyncMerge {
    static func valuesEqual(_ left: WorkspaceSyncJSONValue, _ right: WorkspaceSyncJSONValue) -> Bool {
        left.canonicalString == right.canonicalString
    }

    static func compareDeviceIds(_ left: String, _ right: String) -> Int {
        if left == right { return 0 }
        return left > right ? 1 : -1
    }

    static func compareLWW(_ local: WorkspaceSyncLWWValue, _ remote: WorkspaceSyncLWWValue) -> Int {
        if local.revision != remote.revision {
            return local.revision < remote.revision ? -1 : 1
        }
        return compareDeviceIds(local.deviceId, remote.deviceId)
    }

    static func mergeLWW(
        local: WorkspaceSyncLWWValue,
        remote: WorkspaceSyncLWWValue,
        path: String = ""
    ) -> WorkspaceSyncLWWResult {
        let ordering = compareLWW(local, remote)
        if ordering > 0 {
            return WorkspaceSyncLWWResult(winner: .local, value: local)
        }
        if ordering < 0 {
            return WorkspaceSyncLWWResult(winner: .remote, value: remote)
        }
        if valuesEqual(local.value, remote.value) {
            return WorkspaceSyncLWWResult(winner: .equal, value: local)
        }
        return WorkspaceSyncLWWResult(
            winner: .conflict,
            conflict: WorkspaceSyncFieldConflict(
                path: path,
                merge: .lww,
                reason: .ambiguousLWW,
                local: local.json,
                remote: remote.json
            )
        )
    }

    static func mergeAppendLog(
        local: [WorkspaceSyncAppendEntry],
        remote: [WorkspaceSyncAppendEntry],
        path: String = ""
    ) -> WorkspaceSyncAppendLogResult {
        let localIds = Set(local.map(\.id))
        var byID: [String: WorkspaceSyncAppendEntry] = [:]
        var duplicates: [String] = []
        var conflicts: [WorkspaceSyncFieldConflict] = []

        func record(_ entry: WorkspaceSyncAppendEntry) {
            guard let existing = byID[entry.id] else {
                byID[entry.id] = entry
                return
            }
            if !duplicates.contains(entry.id) {
                duplicates.append(entry.id)
            }
            guard !valuesEqual(existing.value, entry.value) else { return }

            let alreadyRecorded = conflicts.contains {
                $0.path == path
                    && $0.reason == .appendLogDuplicateConflict
                    && $0.local?.objectValue?["id"]?.stringValue == entry.id
            }
            if !alreadyRecorded {
                conflicts.append(
                    WorkspaceSyncFieldConflict(
                        path: path,
                        merge: .appendLog,
                        reason: .appendLogDuplicateConflict,
                        local: existing.json,
                        remote: entry.json
                    )
                )
            }
            if entry.value.canonicalString > existing.value.canonicalString {
                byID[entry.id] = entry
            }
        }

        for entry in local { record(entry) }
        for entry in remote { record(entry) }

        let entries = byID.values.sorted {
            let leftRevision = $0.revision ?? 0
            let rightRevision = $1.revision ?? 0
            if leftRevision != rightRevision { return leftRevision < rightRevision }
            return compareDeviceIds($0.id, $1.id) < 0
        }
        let added = byID.keys.filter { !localIds.contains($0) }.count
        return WorkspaceSyncAppendLogResult(
            entries: entries,
            added: added,
            duplicates: duplicates,
            conflicts: conflicts
        )
    }

    static func mergeManual(
        local: WorkspaceSyncJSONValue,
        remote: WorkspaceSyncJSONValue,
        path: String,
        classified: Bool
    ) -> WorkspaceSyncFieldResult {
        if valuesEqual(local, remote) {
            return WorkspaceSyncFieldResult(
                path: path,
                merge: .manual,
                status: .unchanged,
                changed: false,
                value: local,
                conflicts: []
            )
        }
        return WorkspaceSyncFieldResult(
            path: path,
            merge: .manual,
            status: .conflict,
            changed: false,
            value: local,
            conflicts: [
                WorkspaceSyncFieldConflict(
                    path: path,
                    merge: .manual,
                    reason: classified ? .manualMerge : .unclassifiedField,
                    local: local,
                    remote: remote
                )
            ]
        )
    }

    static func mergeField(
        registry: WorkspaceSyncMergeRegistry,
        path: String,
        local: WorkspaceSyncJSONValue,
        remote: WorkspaceSyncJSONValue
    ) -> WorkspaceSyncFieldResult {
        let merge = registry.mergeClass(for: path)

        if merge == .manual {
            return mergeManual(local: local, remote: remote, path: path, classified: registry.has(path))
        }

        if merge == .appendLog {
            let localEntries = local.arrayValue?.compactMap(WorkspaceSyncAppendEntry.init(json:)) ?? []
            let remoteEntries = remote.arrayValue?.compactMap(WorkspaceSyncAppendEntry.init(json:)) ?? []
            let result = mergeAppendLog(local: localEntries, remote: remoteEntries, path: path)
            return WorkspaceSyncFieldResult(
                path: path,
                merge: merge,
                status: result.conflicts.isEmpty
                    ? (result.added > 0 ? .merged : .unchanged)
                    : .conflict,
                changed: result.added > 0,
                value: .array(result.entries.map(\.json)),
                conflicts: result.conflicts
            )
        }

        guard let localValue = WorkspaceSyncLWWValue(json: local),
              let remoteValue = WorkspaceSyncLWWValue(json: remote) else {
            return WorkspaceSyncFieldResult(
                path: path,
                merge: merge,
                status: .conflict,
                changed: false,
                value: local,
                conflicts: [
                    WorkspaceSyncFieldConflict(
                        path: path,
                        merge: merge,
                        reason: .invalidValue,
                        local: local,
                        remote: remote
                    )
                ]
            )
        }
        let result = mergeLWW(local: localValue, remote: remoteValue, path: path)
        switch result.winner {
        case .local, .equal:
            return WorkspaceSyncFieldResult(
                path: path,
                merge: merge,
                status: .unchanged,
                changed: false,
                value: result.value?.json,
                winner: .local,
                conflicts: []
            )
        case .remote:
            return WorkspaceSyncFieldResult(
                path: path,
                merge: merge,
                status: .merged,
                changed: true,
                value: result.value?.json,
                winner: .remote,
                conflicts: []
            )
        case .conflict:
            return WorkspaceSyncFieldResult(
                path: path,
                merge: merge,
                status: .conflict,
                changed: false,
                value: nil,
                conflicts: result.conflict.map { [$0] } ?? []
            )
        }
    }

    static func applyPatch(
        _ snapshot: WorkspaceSyncSnapshot,
        _ patch: WorkspaceSyncPatch,
        hooks: WorkspaceSyncApplyHooks = WorkspaceSyncApplyHooks()
    ) -> WorkspaceSyncApplyResult {
        if patch.workspaceId != snapshot.workspaceId {
            return rejected(snapshot, reason: .workspaceMismatch)
        }
        if patch.hostEpoch < snapshot.hostEpoch {
            return rejected(snapshot, reason: .staleEpoch)
        }
        if patch.hostEpoch > snapshot.hostEpoch {
            return rejected(snapshot, reason: .futureEpoch)
        }
        if patch.baseWorkspaceSeq < snapshot.workspaceSeq {
            return rejected(snapshot, reason: .staleSeq)
        }
        if patch.baseWorkspaceSeq > snapshot.workspaceSeq {
            return rejected(snapshot, reason: .futureSeq)
        }
        if patch.revision < snapshot.revision {
            return rejected(snapshot, reason: .staleRevision)
        }

        let registry = WorkspaceSyncMergeRegistry(snapshot.metadata)
        var nextFields = snapshot.fields
        var fieldResults: [WorkspaceSyncFieldResult] = []

        for field in patch.fields {
            guard !field.path.isEmpty else {
                return rejected(snapshot, reason: .invalidPatch, fieldResults: fieldResults)
            }
            let hasLocal = nextFields[field.path] != nil
            let result = hasLocal
                ? mergeField(
                    registry: registry,
                    path: field.path,
                    local: nextFields[field.path] ?? .null,
                    remote: field.value
                )
                : mergeNewField(registry: registry, patch: field)
            fieldResults.append(result)
            if result.value != nil || result.status == .merged {
                nextFields[field.path] = result.value
            }
            do {
                try hooks.afterField?(field.path)
            } catch {
                return rejected(snapshot, reason: .interrupted, fieldResults: fieldResults)
            }
        }

        let conflicts = fieldResults.flatMap(\.conflicts)
        if !conflicts.isEmpty {
            return WorkspaceSyncApplyResult(
                status: .conflict,
                snapshot: snapshot,
                fieldResults: fieldResults,
                conflicts: conflicts
            )
        }
        guard fieldResults.contains(where: \.changed) else {
            return WorkspaceSyncApplyResult(
                status: .unchanged,
                snapshot: snapshot,
                fieldResults: fieldResults,
                conflicts: []
            )
        }

        var next = snapshot
        next.workspaceSeq = snapshot.workspaceSeq + 1
        next.revision = max(snapshot.revision + 1, patch.revision)
        next.fields = nextFields
        return WorkspaceSyncApplyResult(
            status: .applied,
            snapshot: next,
            fieldResults: fieldResults,
            conflicts: []
        )
    }

    static func mergeSnapshots(
        local: WorkspaceSyncSnapshot,
        remote: WorkspaceSyncSnapshot,
        backend: CoreFeaturePath = .native,
        hooks: WorkspaceSyncApplyHooks = WorkspaceSyncApplyHooks()
    ) -> WorkspaceSyncApplyResult {
        if backend == .core, hooks.afterField == nil {
            if let result = try? WorkspaceSyncCoreMerge.mergeSnapshots(local: local, remote: remote) {
                return result
            }
        }
        return mergeSnapshotsNative(local: local, remote: remote, hooks: hooks)
    }

    private static func mergeSnapshotsNative(
        local: WorkspaceSyncSnapshot,
        remote: WorkspaceSyncSnapshot,
        hooks: WorkspaceSyncApplyHooks
    ) -> WorkspaceSyncApplyResult {
        if local.workspaceId != remote.workspaceId {
            return rejected(local, reason: .workspaceMismatch)
        }
        if remote.hostEpoch < local.hostEpoch {
            return rejected(local, reason: .staleEpoch)
        }
        if remote.hostEpoch > local.hostEpoch {
            return rejected(local, reason: .futureEpoch)
        }

        var metadataByPath: [String: WorkspaceFieldMetadata] = [:]
        for entry in remote.metadata { metadataByPath[entry.path] = entry }
        for entry in local.metadata { metadataByPath[entry.path] = entry }
        let metadata = metadataByPath.values.sorted { $0.path < $1.path }
        let registry = WorkspaceSyncMergeRegistry(metadata)
        var fields = local.fields
        var fieldResults: [WorkspaceSyncFieldResult] = []
        let paths = Set(local.fields.keys).union(remote.fields.keys).sorted()

        for path in paths {
            let localValue = local.fields[path]
            let remoteValue = remote.fields[path]
            let merge = registry.mergeClass(for: path)
            let result: WorkspaceSyncFieldResult

            if localValue == nil, let remoteValue {
                result = mergeNewField(registry: registry, path: path, value: remoteValue, merge: merge)
            } else if remoteValue == nil, let localValue {
                result = WorkspaceSyncFieldResult(
                    path: path,
                    merge: merge,
                    status: .unchanged,
                    changed: false,
                    value: localValue,
                    conflicts: []
                )
            } else {
                result = mergeField(
                    registry: registry,
                    path: path,
                    local: localValue ?? .null,
                    remote: remoteValue ?? .null
                )
            }

            fieldResults.append(result)
            if result.value != nil || result.status == .merged {
                fields[path] = result.value
            }
            do {
                try hooks.afterField?(path)
            } catch {
                return rejected(local, reason: .interrupted, fieldResults: fieldResults)
            }
        }

        let conflicts = fieldResults.flatMap(\.conflicts)
        if !conflicts.isEmpty {
            return WorkspaceSyncApplyResult(
                status: .conflict,
                snapshot: local,
                fieldResults: fieldResults,
                conflicts: conflicts
            )
        }
        guard fieldResults.contains(where: \.changed) else {
            return WorkspaceSyncApplyResult(
                status: .unchanged,
                snapshot: local,
                fieldResults: fieldResults,
                conflicts: []
            )
        }

        var merged = local
        merged.workspaceSeq = max(local.workspaceSeq, remote.workspaceSeq) + 1
        merged.revision = max(local.revision, remote.revision) + 1
        merged.fields = fields
        merged.metadata = metadata
        return WorkspaceSyncApplyResult(
            status: .applied,
            snapshot: merged,
            fieldResults: fieldResults,
            conflicts: []
        )
    }

    private static func mergeNewField(
        registry: WorkspaceSyncMergeRegistry,
        patch: WorkspaceSyncFieldPatch
    ) -> WorkspaceSyncFieldResult {
        mergeNewField(
            registry: registry,
            path: patch.path,
            value: patch.value,
            merge: registry.mergeClass(for: patch.path),
            patch: patch
        )
    }

    private static func mergeNewField(
        registry: WorkspaceSyncMergeRegistry,
        path: String,
        value remoteValue: WorkspaceSyncJSONValue,
        merge: WorkspaceMergeClass,
        patch: WorkspaceSyncFieldPatch? = nil
    ) -> WorkspaceSyncFieldResult {
        if merge == .manual, !registry.has(path) {
            return WorkspaceSyncFieldResult(
                path: path,
                merge: merge,
                status: .conflict,
                changed: false,
                value: nil,
                conflicts: [
                    WorkspaceSyncFieldConflict(
                        path: path,
                        merge: merge,
                        reason: .unclassifiedField,
                        local: nil,
                        remote: remoteValue
                    )
                ]
            )
        }

        if merge == .appendLog {
            let entries: [WorkspaceSyncAppendEntry]
            if let array = remoteValue.arrayValue {
                entries = array.compactMap(WorkspaceSyncAppendEntry.init(json:))
            } else if let patch {
                entries = [
                    WorkspaceSyncAppendEntry(
                        id: patch.appendId ?? "\(patch.deviceId):\(patch.revision):\(path)",
                        value: remoteValue,
                        revision: patch.revision
                    )
                ]
            } else {
                entries = []
            }
            let merged = mergeAppendLog(local: [], remote: entries, path: path)
            return WorkspaceSyncFieldResult(
                path: path,
                merge: merge,
                status: merged.conflicts.isEmpty ? .merged : .conflict,
                changed: !merged.entries.isEmpty,
                value: .array(merged.entries.map(\.json)),
                conflicts: merged.conflicts
            )
        }

        if merge == .lww {
            if let patch {
                let value = WorkspaceSyncLWWValue(
                    value: patch.value,
                    revision: patch.revision,
                    deviceId: patch.deviceId
                )
                return WorkspaceSyncFieldResult(
                    path: path,
                    merge: merge,
                    status: .merged,
                    changed: true,
                    value: value.json,
                    conflicts: []
                )
            }
            if WorkspaceSyncLWWValue(json: remoteValue) != nil {
                return WorkspaceSyncFieldResult(
                    path: path,
                    merge: merge,
                    status: .merged,
                    changed: true,
                    value: remoteValue,
                    conflicts: []
                )
            }
        }

        return WorkspaceSyncFieldResult(
            path: path,
            merge: merge,
            status: .merged,
            changed: true,
            value: remoteValue,
            conflicts: []
        )
    }

    private static func rejected(
        _ snapshot: WorkspaceSyncSnapshot,
        reason: WorkspaceSyncRejectReason,
        fieldResults: [WorkspaceSyncFieldResult] = []
    ) -> WorkspaceSyncApplyResult {
        WorkspaceSyncApplyResult(
            status: .rejected,
            snapshot: snapshot,
            fieldResults: fieldResults,
            conflicts: fieldResults.flatMap(\.conflicts),
            reason: reason
        )
    }
}

enum WorkspaceSyncCoreMerge {
    static func mergeSnapshots(
        local: WorkspaceSyncSnapshot,
        remote: WorkspaceSyncSnapshot
    ) throws -> WorkspaceSyncApplyResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let localJSON = String(decoding: try encoder.encode(local), as: UTF8.self)
        let remoteJSON = String(decoding: try encoder.encode(remote), as: UTF8.self)
        let resultJSON = try coreSyncMergeSnapshots(localJson: localJSON, remoteJson: remoteJSON)
        return try JSONDecoder().decode(
            WorkspaceSyncApplyResult.self,
            from: Data(resultJSON.utf8)
        )
    }
}

struct WorkspaceSyncOfflineDrainResult: Sendable {
    var applied: [WorkspaceSyncFieldPatch]
    var haltedBy: WorkspaceSyncApplyResult?
    var remaining: [WorkspaceSyncFieldPatch]
}

final class WorkspaceSyncOfflineQueue {
    private var edits: [WorkspaceSyncFieldPatch] = []

    var size: Int { edits.count }

    func enqueue(_ edit: WorkspaceSyncFieldPatch) {
        edits.append(edit)
    }

    func entries() -> [WorkspaceSyncFieldPatch] {
        edits
    }

    func clear() {
        edits.removeAll()
    }

    func drain(
        apply: (WorkspaceSyncFieldPatch) -> WorkspaceSyncApplyResult
    ) -> WorkspaceSyncOfflineDrainResult {
        var applied: [WorkspaceSyncFieldPatch] = []
        let queued = edits
        for index in queued.indices {
            let edit = queued[index]
            let result = apply(edit)
            if result.isAccepted {
                applied.append(edit)
                continue
            }
            edits = Array(edits[index...])
            return WorkspaceSyncOfflineDrainResult(
                applied: applied,
                haltedBy: result,
                remaining: edits
            )
        }
        edits.removeAll()
        return WorkspaceSyncOfflineDrainResult(applied: applied, remaining: [])
    }
}

final class WorkspaceSyncEngine {
    private var current: WorkspaceSyncSnapshot
    private var committed: WorkspaceSyncSnapshot

    init(initial: WorkspaceSyncSnapshot) {
        self.current = initial
        self.committed = initial
    }

    var snapshot: WorkspaceSyncSnapshot { current }

    func apply(
        patch: WorkspaceSyncPatch,
        hooks: WorkspaceSyncApplyHooks = WorkspaceSyncApplyHooks()
    ) -> WorkspaceSyncApplyResult {
        let result = WorkspaceSyncMerge.applyPatch(current, patch, hooks: hooks)
        if result.isAccepted {
            current = result.snapshot
            committed = result.snapshot
        }
        return result
    }

    func recover() -> WorkspaceSyncSnapshot { committed }
}
