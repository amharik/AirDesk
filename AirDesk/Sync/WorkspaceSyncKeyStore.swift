import CryptoKit
import Foundation

struct WorkspaceSyncKeyStoreState: Codable, Equatable, Sendable {
    var generation: UInt64
    var pendingRotations: [String: Data]
    var rotationIssuerDeviceId: String?

    init(
        generation: UInt64 = 1,
        pendingRotations: [String: Data] = [:],
        rotationIssuerDeviceId: String? = nil
    ) {
        self.generation = generation
        self.pendingRotations = pendingRotations
        self.rotationIssuerDeviceId = rotationIssuerDeviceId
    }
}

enum WorkspaceSyncKeyStoreError: Error, Equatable, LocalizedError {
    case corruptState

    var errorDescription: String? {
        switch self {
        case .corruptState:
            return "The workspace sync key state is corrupt."
        }
    }
}

protocol WorkspaceSyncKeyStoring {
    func loadKey(workspaceId: String) throws -> SymmetricKey?
    func saveKey(_ key: SymmetricKey, workspaceId: String) throws
    func deleteKey(workspaceId: String)
    func loadState(workspaceId: String) throws -> WorkspaceSyncKeyStoreState
    func saveState(_ state: WorkspaceSyncKeyStoreState, workspaceId: String) throws
}

extension WorkspaceSyncKeyStoring {
    func loadState(workspaceId: String) throws -> WorkspaceSyncKeyStoreState {
        WorkspaceSyncKeyStoreState()
    }

    func saveState(_ state: WorkspaceSyncKeyStoreState, workspaceId: String) throws {}
}

struct KeychainWorkspaceSyncKeyStore: WorkspaceSyncKeyStoring {
    let service: String

    init(service: String = "com.airdesk.ios.workspace-sync") {
        self.service = service
    }

    func loadKey(workspaceId: String) throws -> SymmetricKey? {
        guard let data = try SecureStorage.load(service: service, account: account(for: workspaceId)) else {
            return nil
        }
        return try WorkspaceSyncCrypto.importKey(data)
    }

    func saveKey(_ key: SymmetricKey, workspaceId: String) throws {
        let data = key.withUnsafeBytes { Data($0) }
        try SecureStorage.save(data, service: service, account: account(for: workspaceId))
    }

    func deleteKey(workspaceId: String) {
        SecureStorage.delete(service: service, account: account(for: workspaceId))
        SecureStorage.delete(service: service, account: stateAccount(for: workspaceId))
    }

    func loadState(workspaceId: String) throws -> WorkspaceSyncKeyStoreState {
        guard let data = try SecureStorage.load(
            service: service,
            account: stateAccount(for: workspaceId)
        ) else {
            return WorkspaceSyncKeyStoreState()
        }
        do {
            return try JSONDecoder().decode(WorkspaceSyncKeyStoreState.self, from: data)
        } catch {
            throw WorkspaceSyncKeyStoreError.corruptState
        }
    }

    func saveState(_ state: WorkspaceSyncKeyStoreState, workspaceId: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try SecureStorage.save(
            data,
            service: service,
            account: stateAccount(for: workspaceId)
        )
    }

    private func account(for workspaceId: String) -> String {
        "workspace-sync-\(workspaceId)"
    }

    private func stateAccount(for workspaceId: String) -> String {
        "workspace-sync-state-\(workspaceId)"
    }
}
