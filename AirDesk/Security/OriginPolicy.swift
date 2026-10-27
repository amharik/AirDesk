import Foundation

struct OriginPolicy {
    let allowedFileDirectory: URL?
    let allowedOrigins: Set<String>

    init(allowedFileDirectory: URL? = nil, allowedOrigins: Set<String> = []) {
        self.allowedFileDirectory = allowedFileDirectory?.standardizedFileURL
        self.allowedOrigins = allowedOrigins
    }

    func isAllowedNavigation(_ url: URL) -> Bool {
        if url.isFileURL {
            guard let allowedFileDirectory else { return false }
            let standardized = url.standardizedFileURL
            let base = allowedFileDirectory.path.hasSuffix("/")
                ? allowedFileDirectory.path
                : allowedFileDirectory.path + "/"
            return standardized.path == allowedFileDirectory.path || standardized.path.hasPrefix(base)
        }

        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return false }
        let isLoopbackHTTP = scheme == "http" && (host == "127.0.0.1" || host == "localhost" || host == "::1")
        guard scheme == "https" || isLoopbackHTTP else { return false }
        let origin = url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
        return allowedOrigins.contains(origin) || allowedOrigins.contains(host)
    }

    func isAllowedBridgeType(_ type: String) -> Bool {
        BridgeMessage.allowedTypes.contains(type)
    }

    static func isAllowedRemoteRuntime(_ url: URL, configuredOrigin: String?) -> Bool {
        guard let configuredOrigin, !configuredOrigin.isEmpty else { return false }
        guard url.scheme?.lowercased() == "https", let host = url.host else { return false }
        if url.host == configuredOrigin { return true }
        if let origin = URLComponents(string: configuredOrigin), origin.host == host { return true }
        return false
    }
}
