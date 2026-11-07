import CryptoKit
import Foundation

protocol WorkspaceSyncKeyStoring {
    func loadKey(workspaceId: String) throws -> SymmetricKey?
    func saveKey(_ key: SymmetricKey, workspaceId: String) throws
    func deleteKey(workspaceId: String)
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
    }

    private func account(for workspaceId: String) -> String {
        "workspace-sync-\(workspaceId)"
    }
}
