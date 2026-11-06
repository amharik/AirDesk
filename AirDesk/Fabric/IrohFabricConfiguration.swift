import Foundation
import IrohLib

enum IrohRelayPolicy: Equatable, Sendable {
    case directOnly
    case selfHosted(urls: [String])

    func relayMode() throws -> RelayMode {
        switch self {
        case .directOnly:
            return .disabled()
        case .selfHosted(let urls):
            let normalized = urls
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !normalized.isEmpty,
                  normalized.allSatisfy({ URL(string: $0)?.scheme?.lowercased() == "https" }) else {
                throw IrohFabricError.invalidRelayURLs
            }
            return try RelayMode.customFromUrls(urls: normalized)
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .directOnly:
            return "direct-only"
        case .selfHosted:
            return "self-hosted-relay"
        }
    }
}

struct IrohFabricConfiguration: Sendable {
    static let defaultALPN = Data("airdesk/fabric/1".utf8)

    let alpn: Data
    let relayPolicy: IrohRelayPolicy
    let bindAddress: String?
    let identitySeed: Data?

    init(
        alpn: Data = IrohFabricConfiguration.defaultALPN,
        relayPolicy: IrohRelayPolicy = .directOnly,
        bindAddress: String? = nil,
        identitySeed: Data? = nil
    ) throws {
        guard (1...255).contains(alpn.count) else {
            throw IrohFabricError.invalidALPN
        }
        if let identitySeed, identitySeed.count != 32 {
            throw IrohFabricError.invalidIdentity
        }
        self.alpn = alpn
        self.relayPolicy = relayPolicy
        self.bindAddress = bindAddress
        self.identitySeed = identitySeed
    }
}

enum IrohIdentityStore {
    static let service = "com.airdesk.ios.iroh"
    static let account = "secret-key"

    static func loadOrCreate() throws -> Data {
        if let stored = try SecureStorage.load(service: service, account: account) {
            guard stored.count == 32 else { throw IrohFabricError.invalidIdentity }
            return stored
        }
        let seed = SecretKey.generate().toBytes()
        guard seed.count == 32 else { throw IrohFabricError.invalidIdentity }
        try SecureStorage.save(seed, service: service, account: account)
        return seed
    }
}
