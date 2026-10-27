import Foundation
import Network
import OSLog

enum LocalAssetServerError: LocalizedError, Equatable {
    case missingRoot
    case startTimedOut
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRoot:
            return "The local desktop assets directory is missing."
        case .startTimedOut:
            return "The local asset server did not start in time."
        case .startFailed(let reason):
            return "The local asset server failed: \(reason)"
        }
    }
}

final class LocalAssetServer: @unchecked Sendable {
    static let shared = LocalAssetServer()

    private let logger = Logger(subsystem: "com.airdesk.ios", category: "LocalAssetServer")
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.airdesk.ios.local-assets", qos: .userInitiated)
    private var listener: NWListener?
    private var rootDirectory: URL?
    private var baseURL: URL?

    private final class StartBox: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<UInt16, Error>?

        func complete(_ result: Result<UInt16, Error>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard self.result == nil else { return false }
            self.result = result
            return true
        }

        func value() -> Result<UInt16, Error>? {
            lock.lock()
            defer { lock.unlock() }
            return result
        }
    }

    func start(rootDirectory: URL) throws -> URL {
        let root = rootDirectory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalAssetServerError.missingRoot
        }

        lock.lock()
        defer { lock.unlock() }

        if let baseURL, self.rootDirectory == root {
            return baseURL
        }
        stopLocked()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw LocalAssetServerError.startFailed(error.localizedDescription)
        }

        self.listener = listener
        self.rootDirectory = root

        let box = StartBox()
        let semaphore = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if box.complete(.success(listener.port?.rawValue ?? 0)) {
                    semaphore.signal()
                }
            case .failed(let error):
                if box.complete(.failure(error)) {
                    semaphore.signal()
                }
            case .cancelled:
                if box.complete(.failure(LocalAssetServerError.startFailed("The listener was cancelled."))) {
                    semaphore.signal()
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            Self.handle(connection, rootDirectory: root)
        }
        listener.start(queue: queue)

        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            listener.cancel()
            self.listener = nil
            self.rootDirectory = nil
            throw LocalAssetServerError.startTimedOut
        }

        guard let result = box.value() else {
            listener.cancel()
            self.listener = nil
            self.rootDirectory = nil
            throw LocalAssetServerError.startFailed("The listener did not report a state.")
        }

        let port: UInt16
        switch result {
        case .success(let value):
            port = value
        case .failure(let error):
            listener.cancel()
            self.listener = nil
            self.rootDirectory = nil
            throw error
        }

        guard port > 0, let url = URL(string: "http://127.0.0.1:\(port)/") else {
            listener.cancel()
            self.listener = nil
            self.rootDirectory = nil
            throw LocalAssetServerError.startFailed("The listener did not expose a usable port.")
        }

        baseURL = url
        logger.info("Local asset server listening on \(url.absoluteString, privacy: .public)")
        return url
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        rootDirectory = nil
        baseURL = nil
    }

    deinit {
        listener?.cancel()
    }

    nonisolated private static func handle(_ connection: NWConnection, rootDirectory: URL) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        receiveRequest(connection, rootDirectory: rootDirectory, buffer: Data())
    }

    nonisolated private static func receiveRequest(_ connection: NWConnection, rootDirectory: URL, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if buffer.count > 64 * 1024 {
                send(connection, status: "431 Request Header Fields Too Large", contentType: "text/plain; charset=utf-8", body: Data("Request headers too large.".utf8))
                return
            }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                respond(connection, rootDirectory: rootDirectory, request: buffer)
                return
            }
            if isComplete || error != nil {
                send(connection, status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Malformed request.".utf8))
                return
            }
            receiveRequest(connection, rootDirectory: rootDirectory, buffer: buffer)
        }
    }

    nonisolated private static func respond(_ connection: NWConnection, rootDirectory: URL, request: Data) {
        let headerEnd = request.range(of: Data("\r\n\r\n".utf8))?.lowerBound ?? request.endIndex
        let header = String(decoding: request[..<headerEnd], as: UTF8.self)
        guard let requestLine = header.components(separatedBy: "\r\n").first else {
            send(connection, status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Malformed request.".utf8))
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(connection, status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Malformed request.".utf8))
            return
        }
        let method = String(parts[0]).uppercased()
        guard method == "GET" || method == "HEAD" else {
            send(connection, status: "405 Method Not Allowed", contentType: "text/plain; charset=utf-8", body: Data("Method not allowed.".utf8))
            return
        }

        var path = String(parts[1])
        if let query = path.firstIndex(of: "?") {
            path = String(path[..<query])
        }
        path = path.removingPercentEncoding ?? path
        if path.isEmpty || path == "/" {
            path = "/index.html"
        }
        guard path.hasPrefix("/"), !path.contains(".."), !path.contains("\0") else {
            send(connection, status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not found.".utf8))
            return
        }

        let relative = String(path.dropFirst())
        let fileURL = rootDirectory.appendingPathComponent(relative).standardizedFileURL
        let rootPath = rootDirectory.standardizedFileURL.path
        guard fileURL.path == rootPath || fileURL.path.hasPrefix(rootPath + "/") else {
            send(connection, status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not found.".utf8))
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let body = try? Data(contentsOf: fileURL) else {
            send(connection, status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not found.".utf8))
            return
        }

        send(
            connection,
            status: "200 OK",
            contentType: mimeType(for: fileURL.pathExtension),
            body: body,
            headOnly: method == "HEAD"
        )
    }

    nonisolated private static func send(
        _ connection: NWConnection,
        status: String,
        contentType: String,
        body: Data,
        headOnly: Bool = false
    ) {
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cross-Origin-Opener-Policy: same-origin",
            "Cross-Origin-Embedder-Policy: require-corp",
            "Cross-Origin-Resource-Policy: same-origin",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var payload = Data(headers.utf8)
        if !headOnly {
            payload.append(body)
        }
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    nonisolated private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "js", "mjs":
            return "text/javascript; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "wasm":
            return "application/wasm"
        case "json", "map":
            return "application/json; charset=utf-8"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "ico":
            return "image/x-icon"
        default:
            return "application/octet-stream"
        }
    }
}
