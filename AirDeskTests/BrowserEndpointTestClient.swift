import Foundation
import Network
@testable import AirDesk

struct BrowserEndpointTestResponse {
    let statusLine: String
    let statusCode: Int
    let headers: [String: String]
    let body: String
}

enum BrowserEndpointTestClientError: Error {
    case timedOut
    case connectionClosed
    case unexpectedResponse(String)
    case protocolError(String)
}

final class BrowserEndpointTestClient: @unchecked Sendable {
    private final class ReadyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var completed = false

        init(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func complete(_ result: Result<Void, Error>) {
            lock.lock()
            guard !completed, let continuation else {
                lock.unlock()
                return
            }
            completed = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        }
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.airdesk.ios.browser-endpoint.test-client")
    private let lock = NSLock()
    private var buffer = Data()
    private var isClosed = false

    private init(_ connection: NWConnection) {
        self.connection = connection
    }

    static func validRequest(
        port: UInt16,
        target: String,
        origin: String,
        key: String = "dGhlIHNhbXBsZSBub25jZQ=="
    ) -> String {
        [
            "GET \(target) HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Key: \(key)",
            "Origin: \(origin)",
            "",
            ""
        ].joined(separator: "\r\n")
    }

    static func connect(
        port: UInt16,
        target: String,
        origin: String
    ) async throws -> BrowserEndpointTestClient {
        let client = try await open(
            port: port,
            request: validRequest(port: port, target: target, origin: origin)
        )
        let response = try await client.readHTTPResponse()
        guard response.statusCode == 101 else {
            client.close()
            throw BrowserEndpointTestClientError.unexpectedResponse(response.statusLine)
        }
        return client
    }

    static func open(port: UInt16, request: String) async throws -> BrowserEndpointTestClient {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw BrowserEndpointTestClientError.protocolError("invalid port")
        }
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: endpointPort,
            using: .tcp
        )
        let client = BrowserEndpointTestClient(connection)
        try await client.start()
        client.sendRaw(Data(request.utf8))
        return client
    }

    func readHTTPResponse(timeout: TimeInterval = 5) async throws -> BrowserEndpointTestResponse {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let headerRange = buffer.range(of: Data("\r\n\r\n".utf8))
            let closed = isClosed
            lock.unlock()

            if headerRange != nil {
                return try await consumeResponse()
            }
            if closed {
                throw BrowserEndpointTestClientError.connectionClosed
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw BrowserEndpointTestClientError.timedOut
    }

    func nextFrame(timeout: TimeInterval = 5) async throws -> BrowserEndpointFrame {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            do {
                if let frame = try BrowserEndpointFrameParser.parse(
                    from: &buffer,
                    expectedMasked: false,
                    maximumPayload: 1_048_576
                ) {
                    lock.unlock()
                    return frame
                }
            } catch {
                lock.unlock()
                throw error
            }
            let closed = isClosed
            lock.unlock()
            if closed {
                throw BrowserEndpointTestClientError.connectionClosed
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw BrowserEndpointTestClientError.timedOut
    }

    func nextText(timeout: TimeInterval = 5) async throws -> String {
        while true {
            let frame = try await nextFrame(timeout: timeout)
            switch frame.opcode {
            case .text:
                guard let text = String(data: frame.payload, encoding: .utf8) else {
                    throw BrowserEndpointTestClientError.protocolError("invalid server text")
                }
                return text
            case .ping:
                sendFrame(.pong(frame.payload))
                continue
            case .pong, .continuation:
                continue
            case .close:
                throw BrowserEndpointTestClientError.connectionClosed
            case .binary:
                throw BrowserEndpointTestClientError.protocolError("unexpected binary frame")
            }
        }
    }

    func sendText(_ text: String) {
        sendFrame(.text(Data(text.utf8)))
    }

    func sendUnmaskedText(_ text: String) {
        sendRaw(BrowserEndpointFrame.text(Data(text.utf8)).encoded(masked: false))
    }

    func sendPing(_ payload: Data = Data([0x31])) {
        sendFrame(.ping(payload))
    }

    func sendPong(_ payload: Data) {
        sendFrame(.pong(payload))
    }

    func sendClose(code: UInt16 = 1000, reason: String = "") {
        sendFrame(.close(code: code, reason: reason))
    }

    func waitUntilClosed(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let closed = isClosed
            lock.unlock()
            if closed { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw BrowserEndpointTestClientError.timedOut
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let box = ReadyBox(continuation)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    box.complete(.success(()))
                case .failed(let error):
                    self?.markClosed()
                    box.complete(.failure(error))
                case .cancelled:
                    self?.markClosed()
                    box.complete(.failure(BrowserEndpointTestClientError.connectionClosed))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        receiveLoop()
    }

    private func markClosed() {
        lock.lock()
        isClosed = true
        lock.unlock()
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.lock.lock()
            if let data {
                self.buffer.append(data)
            }
            if isComplete || error != nil {
                self.isClosed = true
            }
            self.lock.unlock()
            if !isComplete && error == nil {
                self.receiveLoop()
            }
        }
    }

    private func sendRaw(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func sendFrame(_ frame: BrowserEndpointFrame) {
        sendRaw(frame.encoded(masked: true))
    }

    private func consumeResponse() async throws -> BrowserEndpointTestResponse {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            lock.lock()
            guard let currentRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                lock.unlock()
                throw BrowserEndpointTestClientError.protocolError("missing response headers")
            }
            let headerData = Data(buffer[..<currentRange.lowerBound])
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                lock.unlock()
                throw BrowserEndpointTestClientError.protocolError("invalid response headers")
            }
            let lines = headerText.components(separatedBy: "\r\n")
            guard let statusLine = lines.first else {
                lock.unlock()
                throw BrowserEndpointTestClientError.protocolError("missing status line")
            }
            let statusParts = statusLine.split(separator: " ")
            guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
                lock.unlock()
                throw BrowserEndpointTestClientError.protocolError("invalid status line")
            }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = String(line[..<colon]).lowercased()
                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
            let contentLength = Int(headers["content-length"] ?? "0") ?? 0
            let totalLength = currentRange.upperBound + contentLength
            if buffer.count < totalLength {
                lock.unlock()
                try await Task.sleep(nanoseconds: 10_000_000)
                continue
            }
            let bodyData = Data(buffer[currentRange.upperBound..<totalLength])
            buffer.removeSubrange(buffer.startIndex..<totalLength)
            lock.unlock()
            return BrowserEndpointTestResponse(
                statusLine: statusLine,
                statusCode: statusCode,
                headers: headers,
                body: String(decoding: bodyData, as: UTF8.self)
            )
        }
        throw BrowserEndpointTestClientError.timedOut
    }
}
