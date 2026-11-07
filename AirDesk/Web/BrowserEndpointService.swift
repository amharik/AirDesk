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
    @Published private(set) var presentationURL: URL?
    @Published private(set) var lastError: String?

    private let tokenLifetime: TimeInterval
    private let now: () -> Date
    private let displaySessionId: String
    private var host: BrowserEndpointHost?

    init(
        tokenLifetime: TimeInterval = 3_600,
        now: @escaping () -> Date = Date.init,
        displaySessionId: String = "display.\(UUID().uuidString.lowercased())"
    ) {
        self.tokenLifetime = tokenLifetime
        self.now = now
        self.displaySessionId = displaySessionId
    }

    func start(
        allowedOrigin: String,
        presentationBaseURL: URL? = nil,
        workspaceId: String? = nil
    ) throws {
        if host != nil, state == .running {
            return
        }

        let resolvedWorkspaceId = workspaceId ?? "workspace.local"
        if presentationBaseURL != nil,
           !BrowserEndpointValidation.isValidIdentifier(resolvedWorkspaceId) {
            throw BrowserEndpointProtocolError.invalidIdentifier("workspaceId")
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
            let presentationURL = try presentationBaseURL.map {
                try Self.makePresentationURL(
                    baseURL: $0,
                    endpointURL: endpointURL,
                    token: token,
                    workspaceId: resolvedWorkspaceId,
                    displaySessionId: displaySessionId
                )
            }
            self.host = host
            self.endpointURL = endpointURL
            self.presentationURL = presentationURL
            state = .running
        } catch {
            host?.stop()
            host = nil
            endpointURL = nil
            presentationURL = nil
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() {
        host?.stop()
        host = nil
        endpointURL = nil
        presentationURL = nil
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

    private static func makePresentationURL(
        baseURL: URL,
        endpointURL: URL,
        token: String,
        workspaceId: String,
        displaySessionId: String
    ) throws -> URL {
        var endpointComponents = URLComponents(
            url: endpointURL,
            resolvingAgainstBaseURL: false
        )
        endpointComponents?.queryItems = nil
        guard let endpoint = endpointComponents?.url?.absoluteString else {
            throw BrowserEndpointHostError.invalidConfiguration("presentation endpoint URL")
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("endpoint.html"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "endpoint", value: endpoint),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "workspace", value: workspaceId),
            URLQueryItem(name: "display", value: displaySessionId)
        ]
        guard let url = components?.url else {
            throw BrowserEndpointHostError.invalidConfiguration("presentation URL")
        }
        return url
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
