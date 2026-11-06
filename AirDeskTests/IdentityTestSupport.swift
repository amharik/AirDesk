import Foundation
@testable import AirDesk

final class InMemoryDeviceIdentitySecretStore: DeviceIdentitySecretStore {
    var data: Data?
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    func load() throws -> Data? {
        data
    }

    func save(_ data: Data) throws {
        self.data = data
        saveCount += 1
    }

    func delete() {
        data = nil
        deleteCount += 1
    }
}

final class InMemoryDeviceRegistryStorage: DeviceRegistryStorage {
    var data: Data?
    private(set) var saveCount = 0

    func load() throws -> Data? {
        data
    }

    func save(_ data: Data) throws {
        self.data = data
        saveCount += 1
    }
}
