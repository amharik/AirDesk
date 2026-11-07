import Foundation
import Security

struct BrowserEndpointSurfaceImage: Sendable {
    let jpegData: Data
    let width: Int
    let height: Int
}

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
    @Published private(set) var registeredDisplayCount = 0

    var surfaceImageProvider: (@MainActor () async -> BrowserEndpointSurfaceImage?)?

    private let tokenLifetime: TimeInterval
    private let now: () -> Date
    private let displaySessionId: String
    private var host: BrowserEndpointHost?
    private var workspaceId = "workspace.local"
    private var surfaceTask: Task<Void, Never>?
    private var surfaceTaskId: UUID?
    private var surfaceRevision: UInt64 = 0

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
            host.onDisplayRegistered = { [weak self, weak host] _ in
                Task { @MainActor [weak self, weak host] in
                    guard let self, let host, self.host === host else { return }
                    self.displayDidRegister()
                }
            }
            host.onConnectionClosed = { [weak self, weak host] _ in
                Task { @MainActor [weak self, weak host] in
                    guard let self, let host, self.host === host else { return }
                    self.displayDidClose()
                }
            }
            self.host = host
            self.workspaceId = resolvedWorkspaceId
            self.endpointURL = endpointURL
            self.presentationURL = presentationURL
            state = .running
        } catch {
            stopSurfaceStream()
            let currentHost = host
            host = nil
            currentHost?.stop()
            registeredDisplayCount = 0
            surfaceRevision = 0
            endpointURL = nil
            presentationURL = nil
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() {
        stopSurfaceStream()
        let currentHost = host
        host = nil
        currentHost?.stop()
        registeredDisplayCount = 0
        surfaceRevision = 0
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

    private func displayDidRegister() {
        guard host != nil else { return }
        registeredDisplayCount += 1
        startSurfaceStreamIfNeeded()
    }

    private func displayDidClose() {
        guard host != nil else { return }
        registeredDisplayCount = max(0, registeredDisplayCount - 1)
        if registeredDisplayCount == 0 {
            stopSurfaceStream()
        }
    }

    private func startSurfaceStreamIfNeeded() {
        guard surfaceTask == nil,
              registeredDisplayCount > 0,
              surfaceImageProvider != nil else {
            return
        }
        let taskId = UUID()
        surfaceTaskId = taskId
        surfaceTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.surfaceTaskId == taskId {
                    self.surfaceTask = nil
                    self.surfaceTaskId = nil
                }
            }
            while !Task.isCancelled {
                guard let self,
                      self.registeredDisplayCount > 0,
                      let provider = self.surfaceImageProvider else {
                    return
                }
                if let image = await provider(),
                   !Task.isCancelled,
                   self.surfaceTaskId == taskId,
                   let host = self.host,
                   self.registeredDisplayCount > 0 {
                    self.surfaceRevision &+= 1
                    let frame = BrowserEndpointSurfaceFrame(
                        workspaceId: self.workspaceId,
                        revision: self.surfaceRevision,
                        width: image.width,
                        height: image.height,
                        mimeType: "image/jpeg",
                        payloadBase64: image.jpegData.base64EncodedString()
                    )
                    _ = host.broadcastSurface(frame)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopSurfaceStream() {
        surfaceTask?.cancel()
        surfaceTask = nil
        surfaceTaskId = nil
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
