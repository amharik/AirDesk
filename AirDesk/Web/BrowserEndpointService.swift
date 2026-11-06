import Foundation
import Security

@MainActor
final class BrowserEndpointService: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)

        var title: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting"
            case .running: return "Listening"
            case .failed: return "Failed"
            }
        }
    }

    enum ServiceError: LocalizedError, Equatable {
        case tokenGenerationFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .tokenGenerationFailed(let status):
                return "The browser endpoint token could not be generated (status \(status))."
            }
        }
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var endpointURL: URL?
    @Published private(set) var lastError: String?

    private let tokenLifetime: TimeInterval
    private let now: () -> Date
    private var host: BrowserEndpointHost?

    init(tokenLifetime: TimeInterval = 3_600, now: @escaping () -> Date = Date.init) {
        self.tokenLifetime = tokenLifetime
        self.now = now
    }

    func start(allowedOrigin: String) throws {
        if host != nil, state == .running {
            return
        }

        stop()
        state = .starting
        lastError = nil

        do {
            let token = try Self.makeToken()
            let configuration = BrowserEndpointHostConfiguration(
                token: token,
                tokenExpiresAt: now().addingTimeInterval(tokenLifetime),
                allowedOrigin: allowedOrigin
            )
            let host = try BrowserEndpointHost(configuration: configuration)
            let address = try host.start()
            guard let endpointURL = Self.makeEndpointURL(address: address, token: token) else {
                host.stop()
                throw BrowserEndpointHostError.invalidConfiguration("endpoint URL")
            }
            self.host = host
            self.endpointURL = endpointURL
            state = .running
        } catch {
            host?.stop()
            host = nil
            endpointURL = nil
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() {
        host?.stop()
        host = nil
        endpointURL = nil
        lastError = nil
        state = .stopped
    }

    func markFailed(_ error: Error) {
        stop()
        lastError = error.localizedDescription
        state = .failed(error.localizedDescription)
    }

    private static func makeEndpointURL(
        address: BrowserEndpointHostAddress,
        token: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = address.host
        components.port = Int(address.port)
        components.path = address.path
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private static func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw ServiceError.tokenGenerationFailed(status)
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
