import Foundation

enum WorkspaceQuotaKind: String, Codable, CaseIterable, Sendable {
    case workers
    case memory
    case cpu
    case handles
    case persistedStorage = "persisted-storage"
}

extension WorkspaceQuotas {
    var requiredKinds: Set<WorkspaceQuotaKind> {
        var result = Set<WorkspaceQuotaKind>()
        if workers != nil { result.insert(.workers) }
        if memoryBytes != nil { result.insert(.memory) }
        if cpuMillis != nil { result.insert(.cpu) }
        if handles != nil { result.insert(.handles) }
        if persistedBytes != nil { result.insert(.persistedStorage) }
        return result
    }
}
