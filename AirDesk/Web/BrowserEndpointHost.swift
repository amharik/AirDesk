import Foundation
import Network
import OSLog

struct BrowserEndpointHostConfiguration: Sendable {
    static let defaultPath = "/endpoint"

    var path: String
    var port: UInt16
    var token: String
    var tokenExpiresAt: Date
    var allowedOrigin: String
    var heartbeatInterval: TimeInterval
    var heartbeatTimeout: TimeInterval
    var handshakeTimeout: TimeInterval
    var maximumMessageBytes: Int

    init(
        token: String,
        tokenExpiresAt: Date,
        allowedOrigin: String,
        port: UInt16 = 0,
        path: String = BrowserEndpointHostConfiguration.defaultPath,
        heartbeatInterval: TimeInterval = 15,
        heartbeatTimeout: TimeInterval = 45,
        handshakeTimeout: TimeInterval = 10,
        maximumMessageBytes: Int = 64 * 1024
    ) {
        self.token = token
        self.tokenExpiresAt = tokenExpiresAt
        self.allowedOrigin = allowedOrigin
        self.port = port
        self.path = path
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        self.handshakeTimeout = handshakeTimeout
        self.maximumMessageBytes = maximumMessageBytes
    }
}

struct BrowserEndpointHostAddress: Equatable, Sendable {
    let host: String
    let port: UInt16
    let path: String

    var endpointURL: String {
        "ws://\(host):\(port)\(path)"
    }
}

enum BrowserEndpointHostError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case listenerFailed(String)
    case startTimedOut
    case notRunning

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Invalid browser endpoint host configuration: \(reason)."
        case .listenerFailed(let reason):
            return "The browser endpoint listener failed: \(reason)."
        case .startTimedOut:
            return "The browser endpoint listener did not start in time."
        case .notRunning:
            return "The browser endpoint listener is not running."
        }
    }
}

struct BrowserEndpointRegistration: Equatable, Sendable {
    let connectionId: UUID
    let workspaceId: String
    let displaySessionId: String
    var viewport: BrowserEndpointViewport
    var focusTarget: String?
    var generation: Int
}

enum BrowserEndpointDisplayUpdateKind: String, Equatable, Sendable {
    case viewport = "display.viewport"
    case focus = "display.focus"
}

struct BrowserEndpointDisplayUpdate: Equatable, Sendable {
    let kind: BrowserEndpointDisplayUpdateKind
    let registration: BrowserEndpointRegistration
}

enum BrowserEndpointRegistrationResult {
    case accepted(BrowserEndpointRegistration)
    case rejected(BrowserEndpointWireErrorCode, String)
}

struct BrowserEndpointRegistrationFailure {
    let code: BrowserEndpointWireErrorCode
    let message: String
}

final class BrowserEndpointHost: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "BrowserEndpointHost")
    private let configuration: BrowserEndpointHostConfiguration
    private let policy: BrowserEndpointHandshakePolicy
    private let queue = DispatchQueue(label: "com.airdesk.ios.browser-endpoint", qos: .userInitiated)
    private let lifecycleLock = NSLock()
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var address: BrowserEndpointHostAddress?
    private var connections: [UUID: BrowserEndpointConnection] = [:]
    private var activeRegistrations: [UUID: BrowserEndpointRegistration] = [:]

    var onDisplayRegistered: ((BrowserEndpointRegistration) -> Void)?
    var onDisplayUpdated: ((BrowserEndpointDisplayUpdate) -> Void)?
    var onConnectionClosed: ((UUID) -> Void)?

    init(configuration: BrowserEndpointHostConfiguration) throws {
        guard BrowserEndpointValidation.isValidPath(configuration.path) else {
            throw BrowserEndpointHostError.invalidConfiguration("path")
        }
        guard BrowserEndpointValidation.isValidToken(configuration.token) else {
            throw BrowserEndpointHostError.invalidConfiguration("token")
        }
        let origin = try BrowserEndpointOrigin.parseLoopback(configuration.allowedOrigin)
        guard configuration.heartbeatInterval >= 0 else {
            throw BrowserEndpointHostError.invalidConfiguration("heartbeat interval")
        }
        guard configuration.heartbeatInterval == 0 || configuration.heartbeatTimeout > 0 else {
            throw BrowserEndpointHostError.invalidConfiguration("heartbeat timeout")
        }
        guard configuration.handshakeTimeout > 0 else {
            throw BrowserEndpointHostError.invalidConfiguration("handshake timeout")
        }
        guard (1_024...1_048_576).contains(configuration.maximumMessageBytes) else {
            throw BrowserEndpointHostError.invalidConfiguration("maximum message size")
        }

        self.configuration = configuration
        self.policy = BrowserEndpointHandshakePolicy(
            path: configuration.path,
            token: configuration.token,
            tokenExpiresAt: configuration.tokenExpiresAt,
            allowedOrigin: origin
        )
    }

    var runningPort: UInt16? {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return address?.port
    }

    func start() throws -> BrowserEndpointHostAddress {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        if let address {
            return address
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let requestedPort = configuration.port == 0
            ? NWEndpoint.Port.any
            : (NWEndpoint.Port(rawValue: configuration.port) ?? NWEndpoint.Port.any)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: requestedPort)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw BrowserEndpointHostError.listenerFailed(error.localizedDescription)
        }

        self.listener = listener
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
                if box.complete(.failure(BrowserEndpointHostError.listenerFailed("The listener was cancelled."))) {
                    semaphore.signal()
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)

        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            listener.cancel()
            self.listener = nil
            throw BrowserEndpointHostError.startTimedOut
        }

        guard let result = box.value() else {
            listener.cancel()
            self.listener = nil
            throw BrowserEndpointHostError.listenerFailed("The listener did not report a state.")
        }

        let port: UInt16
        switch result {
        case .success(let value):
            port = value
        case .failure(let error):
            listener.cancel()
            self.listener = nil
            if let hostError = error as? BrowserEndpointHostError {
                throw hostError
            }
            throw BrowserEndpointHostError.listenerFailed(error.localizedDescription)
        }

        guard port > 0 else {
            listener.cancel()
            self.listener = nil
            throw BrowserEndpointHostError.listenerFailed("The listener did not expose a usable port.")
        }

        let address = BrowserEndpointHostAddress(
            host: "127.0.0.1",
            port: port,
            path: configuration.path
        )
        self.address = address
        logger.info("Browser endpoint listening on \(address.endpointURL, privacy: .public)")
        return address
    }

    func stop() {
        lifecycleLock.lock()
        let listener = self.listener
        self.listener = nil
        self.address = nil
        lifecycleLock.unlock()

        listener?.cancel()

        stateLock.lock()
        let connections = Array(self.connections.values)
        self.connections.removeAll()
        self.activeRegistrations.removeAll()
        stateLock.unlock()

        for connection in connections {
            connection.forceCancel()
        }
    }

    func registeredDisplays() -> [BrowserEndpointRegistration] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeRegistrations.values.sorted {
            if $0.workspaceId == $1.workspaceId {
                return $0.displaySessionId < $1.displaySessionId
            }
            return $0.workspaceId < $1.workspaceId
        }
    }

    deinit {
        listener?.cancel()
        stateLock.lock()
        let connections = Array(self.connections.values)
        self.connections.removeAll()
        self.activeRegistrations.removeAll()
        stateLock.unlock()
        for connection in connections {
            connection.forceCancel()
        }
    }

    private func accept(_ networkConnection: NWConnection) {
        lifecycleLock.lock()
        let running = listener != nil
        lifecycleLock.unlock()
        guard running else {
            networkConnection.cancel()
            return
        }

        let id = UUID()
        let connection = BrowserEndpointConnection(
            id: id,
            connection: networkConnection,
            configuration: configuration,
            policy: policy,
            queue: queue,
            register: { [weak self] id, state in
                self?.register(connectionId: id, state: state)
                    ?? .rejected(.invalidState, "Browser endpoint host is unavailable.")
            },
            update: { [weak self] id, kind, state in
                guard let self else {
                    return BrowserEndpointRegistrationFailure(
                        code: .invalidState,
                        message: "Browser endpoint host is unavailable."
                    )
                }
                return self.update(connectionId: id, kind: kind, state: state)
            },
            closed: { [weak self] id in
                self?.closed(connectionId: id)
            }
        )

        stateLock.lock()
        connections[id] = connection
        stateLock.unlock()

        // stop() can race with an in-flight accept. Re-check after publishing the
        // connection so a connection accepted during shutdown is never started.
        lifecycleLock.lock()
        let stillRunning = listener != nil
        lifecycleLock.unlock()
        guard stillRunning else {
            stateLock.lock()
            connections.removeValue(forKey: id)
            stateLock.unlock()
            connection.forceCancel()
            return
        }
        connection.start()
    }

    private func register(
        connectionId: UUID,
        state: BrowserEndpointDisplayState
    ) -> BrowserEndpointRegistrationResult {
        stateLock.lock()
        let previous = activeRegistrations.first {
            $0.value.workspaceId == state.workspaceId &&
                $0.value.displaySessionId == state.displaySessionId
        }
        if let previous, state.generation <= previous.value.generation {
            stateLock.unlock()
            return .rejected(.invalidState, "Display session is already registered.")
        }
        let replacedConnection = previous.flatMap { connections[$0.key] }
        if let previous {
            activeRegistrations.removeValue(forKey: previous.key)
        }
        let registration = BrowserEndpointRegistration(
            connectionId: connectionId,
            workspaceId: state.workspaceId,
            displaySessionId: state.displaySessionId,
            viewport: state.viewport,
            focusTarget: state.focusTarget,
            generation: state.generation
        )
        activeRegistrations[connectionId] = registration
        stateLock.unlock()

        replacedConnection?.forceCancel()
        onDisplayRegistered?(registration)
        return .accepted(registration)
    }

    private func update(
        connectionId: UUID,
        kind: BrowserEndpointMessageKind,
        state: BrowserEndpointDisplayState
    ) -> BrowserEndpointRegistrationFailure? {
        stateLock.lock()
        guard var registration = activeRegistrations[connectionId] else {
            stateLock.unlock()
            return BrowserEndpointRegistrationFailure(
                code: .invalidState,
                message: "Display is not registered."
            )
        }
        guard state.workspaceId == registration.workspaceId else {
            stateLock.unlock()
            return BrowserEndpointRegistrationFailure(
                code: .workspaceMismatch,
                message: "Workspace does not match the registered connection."
            )
        }
        guard state.displaySessionId == registration.displaySessionId else {
            stateLock.unlock()
            return BrowserEndpointRegistrationFailure(
                code: .displaySessionMismatch,
                message: "Display session does not match the registered connection."
            )
        }
        guard state.generation > registration.generation else {
            stateLock.unlock()
            return BrowserEndpointRegistrationFailure(
                code: .protocolError,
                message: "Display generation is stale."
            )
        }

        registration.viewport = state.viewport
        registration.focusTarget = state.focusTarget
        registration.generation = state.generation
        activeRegistrations[connectionId] = registration
        stateLock.unlock()

        let updateKind: BrowserEndpointDisplayUpdateKind = kind == .viewport ? .viewport : .focus
        onDisplayUpdated?(BrowserEndpointDisplayUpdate(kind: updateKind, registration: registration))
        return nil
    }

    private func closed(connectionId: UUID) {
        stateLock.lock()
        connections.removeValue(forKey: connectionId)
        activeRegistrations.removeValue(forKey: connectionId)
        stateLock.unlock()
        onConnectionClosed?(connectionId)
    }

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
}

private final class BrowserEndpointConnection: @unchecked Sendable {
    private enum Phase {
        case handshake
        case awaitingRegistration
        case registered
        case closing
        case closed
    }

    private struct PendingPing {
        let payload: Data
        let deadline: Date
    }

    private let id: UUID
    private let connection: NWConnection
    private let configuration: BrowserEndpointHostConfiguration
    private let policy: BrowserEndpointHandshakePolicy
    private let queue: DispatchQueue
    private let registerHandler: (UUID, BrowserEndpointDisplayState) -> BrowserEndpointRegistrationResult
    private let updateHandler: (UUID, BrowserEndpointMessageKind, BrowserEndpointDisplayState) -> BrowserEndpointRegistrationFailure?
    private let closedHandler: (UUID) -> Void

    private var phase: Phase = .handshake
    private var headerBuffer = Data()
    private var frameBuffer = Data()
    private var fragmentedOpcode: BrowserEndpointFrameOpcode?
    private var fragmentedBuffer = Data()
    private var registration: BrowserEndpointRegistration?
    private var handshakeTimer: DispatchWorkItem?
    private var heartbeatTimer: DispatchSourceTimer?
    private var pendingPing: PendingPing?
    private var pingCounter: UInt8 = 0
    private var isClosed = false

    init(
        id: UUID,
        connection: NWConnection,
        configuration: BrowserEndpointHostConfiguration,
        policy: BrowserEndpointHandshakePolicy,
        queue: DispatchQueue,
        register: @escaping (UUID, BrowserEndpointDisplayState) -> BrowserEndpointRegistrationResult,
        update: @escaping (UUID, BrowserEndpointMessageKind, BrowserEndpointDisplayState) -> BrowserEndpointRegistrationFailure?,
        closed: @escaping (UUID) -> Void
    ) {
        self.id = id
        self.connection = connection
        self.configuration = configuration
        self.policy = policy
        self.queue = queue
        self.registerHandler = register
        self.updateHandler = update
        self.closedHandler = closed
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.teardown()
            default:
                break
            }
        }
        connection.start(queue: queue)
        scheduleHandshakeTimeout()
        receiveHeaders()
    }

    func forceCancel() {
        queue.async {
            guard !self.isClosed else { return }
            if self.phase == .handshake || self.phase == .closing {
                self.teardown()
                return
            }
            self.sendCloseAndCancel(code: 1001, reason: "host-stop")
        }
    }

    private func receiveHeaders() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data {
                self.headerBuffer.append(data)
            }
            if let headerEnd = self.headerBuffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = Data(self.headerBuffer[..<headerEnd.lowerBound])
                let leftover = Data(self.headerBuffer[headerEnd.upperBound...])
                self.headerBuffer.removeAll()
                guard headerData.count <= BrowserEndpointHTTPRequestParser.maximumHeaderBytes else {
                    self.reject(.requestTooLarge)
                    return
                }
                self.processHeaders(headerData, leftover: leftover)
                return
            }
            if self.headerBuffer.count > BrowserEndpointHTTPRequestParser.maximumHeaderBytes {
                self.reject(.requestTooLarge)
                return
            }
            if isComplete || error != nil {
                self.reject(.malformedRequest)
                return
            }
            self.receiveHeaders()
        }
    }

    private func processHeaders(_ data: Data, leftover: Data) {
        do {
            let request = try BrowserEndpointHTTPRequestParser.parse(data)
            let handshake = try BrowserEndpointHandshake.validate(
                request,
                policy: policy,
                now: Date()
            )
            accept(handshake, leftover: leftover)
        } catch let error as BrowserEndpointHandshakeError {
            reject(error)
        } catch let error as BrowserEndpointHTTPRequestError {
            reject(error == .tooLarge ? .requestTooLarge : .malformedRequest)
        } catch {
            reject(.malformedRequest)
        }
    }

    private func accept(_ handshake: BrowserEndpointHandshake, leftover: Data) {
        guard phase == .handshake else { return }
        phase = .awaitingRegistration
        cancelHandshakeTimer()
        let response = handshake.acceptResponseData()
        connection.send(content: response, completion: .contentProcessed { [weak self] error in
            guard let self, !self.isClosed else { return }
            if error != nil {
                self.teardown()
                return
            }
            self.startHeartbeat()
            if !leftover.isEmpty {
                self.frameBuffer.append(leftover)
            }
            do {
                try self.processFrameBuffer()
            } catch let frameError as BrowserEndpointFrameError {
                self.failFrame(frameError)
                return
            } catch {
                self.failFrame(.protocolViolation("Invalid WebSocket frame."))
                return
            }
            if !self.isClosed {
                self.receiveFrames()
            }
        })
    }

    private func reject(_ error: BrowserEndpointHandshakeError) {
        guard phase == .handshake else { return }
        phase = .closing
        cancelHandshakeTimer()
        stopHeartbeat()
        connection.send(content: error.responseData, completion: .contentProcessed { [weak self] _ in
            self?.teardown()
        })
    }

    private func receiveFrames() {
        guard !isClosed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data {
                self.frameBuffer.append(data)
            }
            do {
                try self.processFrameBuffer()
            } catch let frameError as BrowserEndpointFrameError {
                self.failFrame(frameError)
                return
            } catch {
                self.failFrame(.protocolViolation("Invalid WebSocket frame."))
                return
            }
            if isComplete || error != nil {
                self.teardown()
            } else if !self.isClosed {
                self.receiveFrames()
            }
        }
    }

    private func processFrameBuffer() throws {
        while !isClosed {
            guard let frame = try BrowserEndpointFrameParser.parse(
                from: &frameBuffer,
                expectedMasked: true,
                maximumPayload: configuration.maximumMessageBytes
            ) else {
                return
            }
            try handle(frame)
        }
    }

    private func handle(_ frame: BrowserEndpointFrame) throws {
        guard phase != .closing, phase != .closed else { return }
        switch frame.opcode {
        case .ping:
            sendFrame(.pong(frame.payload))
        case .pong:
            pendingPing = nil
        case .close:
            handleCloseFrame(frame.payload)
        case .continuation:
            try handleContinuation(frame)
        case .text:
            try handleDataFrame(frame)
        case .binary:
            throw BrowserEndpointFrameError.unsupportedData
        }
    }

    private func handleDataFrame(_ frame: BrowserEndpointFrame) throws {
        guard fragmentedOpcode == nil else {
            throw BrowserEndpointFrameError.protocolViolation(
                "Received a new data frame while a fragmented message was active."
            )
        }
        guard frame.opcode == .text else {
            throw BrowserEndpointFrameError.unsupportedData
        }
        if frame.fin {
            try deliver(frame.payload, opcode: .text)
        } else {
            fragmentedOpcode = .text
            fragmentedBuffer = frame.payload
            guard fragmentedBuffer.count <= configuration.maximumMessageBytes else {
                throw BrowserEndpointFrameError.messageTooLarge
            }
        }
    }

    private func handleContinuation(_ frame: BrowserEndpointFrame) throws {
        guard fragmentedOpcode == .text else {
            throw BrowserEndpointFrameError.protocolViolation(
                "Continuation frame without a fragmented message."
            )
        }
        guard fragmentedBuffer.count + frame.payload.count <= configuration.maximumMessageBytes else {
            throw BrowserEndpointFrameError.messageTooLarge
        }
        fragmentedBuffer.append(frame.payload)
        if frame.fin {
            let payload = fragmentedBuffer
            fragmentedBuffer.removeAll()
            fragmentedOpcode = nil
            try deliver(payload, opcode: .text)
        }
    }

    private func deliver(_ payload: Data, opcode: BrowserEndpointFrameOpcode) throws {
        guard opcode == .text else {
            throw BrowserEndpointFrameError.unsupportedData
        }
        guard String(data: payload, encoding: .utf8) != nil else {
            throw BrowserEndpointFrameError.invalidUTF8
        }
        handleText(payload)
    }

    private func handleText(_ data: Data) {
        let message: BrowserEndpointMessage
        do {
            message = try BrowserEndpointMessageCodec.parse(data)
        } catch let error as BrowserEndpointMessageError {
            sendDisplayErrorAndClose(
                code: error.wireCode,
                message: error.errorDescription ?? "Invalid browser endpoint message."
            )
            return
        } catch {
            sendDisplayErrorAndClose(code: .protocolError, message: "Invalid browser endpoint message.")
            return
        }

        switch message.kind {
        case .register:
            guard phase == .awaitingRegistration else {
                sendDisplayErrorAndClose(
                    code: .invalidState,
                    message: "Display is already registered."
                )
                return
            }
            switch registerHandler(id, message.state) {
            case .accepted(let registration):
                self.registration = registration
                phase = .registered
                sendFrame(.text(BrowserEndpointMessageCodec.registered(registration)))
            case .rejected(let code, let message):
                sendDisplayErrorAndClose(code: code, message: message)
            }

        case .viewport, .focus:
            guard phase == .registered, let registration else {
                sendDisplayErrorAndClose(code: .invalidState, message: "Display is not registered.")
                return
            }
            guard message.state.workspaceId == registration.workspaceId else {
                sendDisplayErrorAndClose(
                    code: .workspaceMismatch,
                    message: "Workspace does not match the registered connection."
                )
                return
            }
            guard message.state.displaySessionId == registration.displaySessionId else {
                sendDisplayErrorAndClose(
                    code: .displaySessionMismatch,
                    message: "Display session does not match the registered connection."
                )
                return
            }
            if let failure = updateHandler(id, message.kind, message.state) {
                sendDisplayErrorAndClose(code: failure.code, message: failure.message)
            }
        }
    }

    private func handleCloseFrame(_ payload: Data) {
        guard payload.count != 1 else {
            failFrame(.protocolViolation("Invalid WebSocket close frame."))
            return
        }
        if payload.count >= 2 {
            let bytes = Array(payload)
            let code = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            guard Self.isValidCloseCode(code) else {
                failFrame(.protocolViolation("Invalid WebSocket close code."))
                return
            }
            guard String(data: Data(bytes.dropFirst(2)), encoding: .utf8) != nil else {
                failFrame(.invalidUTF8)
                return
            }
        }
        let echo = payload.isEmpty ? BrowserEndpointFrame.close(code: 1000).payload : payload
        sendClosePayloadAndCancel(echo)
    }

    private static func isValidCloseCode(_ code: UInt16) -> Bool {
        switch code {
        case 1000...1003, 1007...1014, 3000...4999:
            return true
        default:
            return false
        }
    }

    private func startHeartbeat() {
        guard configuration.heartbeatInterval > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + configuration.heartbeatInterval,
            repeating: configuration.heartbeatInterval,
            leeway: .milliseconds(25)
        )
        timer.setEventHandler { [weak self] in
            self?.heartbeatFired()
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func heartbeatFired() {
        guard !isClosed else { return }
        if let pendingPing {
            if Date() >= pendingPing.deadline {
                sendCloseAndCancel(code: 1001, reason: "heartbeat-timeout")
            }
            return
        }
        let payload = Data([0x41, pingCounter])
        pingCounter &+= 1
        pendingPing = PendingPing(
            payload: payload,
            deadline: Date().addingTimeInterval(configuration.heartbeatTimeout)
        )
        sendFrame(.ping(payload))
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        pendingPing = nil
    }

    private func scheduleHandshakeTimeout() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .handshake else { return }
            self.reject(.malformedRequest)
        }
        handshakeTimer = work
        queue.asyncAfter(deadline: .now() + configuration.handshakeTimeout, execute: work)
    }

    private func cancelHandshakeTimer() {
        handshakeTimer?.cancel()
        handshakeTimer = nil
    }

    private func sendDisplayErrorAndClose(
        code: BrowserEndpointWireErrorCode,
        message: String
    ) {
        guard !isClosed else { return }
        phase = .closing
        stopHeartbeat()
        let data = BrowserEndpointMessageCodec.error(code: code, message: message)
        sendFrame(.text(data)) { [weak self] in
            self?.sendCloseAndCancel(code: 1008, reason: code.rawValue)
        }
    }

    private func failFrame(_ error: BrowserEndpointFrameError) {
        guard !isClosed else { return }
        sendCloseAndCancel(
            code: error.closeCode,
            reason: error.errorDescription ?? "protocol-error"
        )
    }

    private func sendClosePayloadAndCancel(_ payload: Data) {
        guard !isClosed else { return }
        phase = .closing
        stopHeartbeat()
        sendFrame(BrowserEndpointFrame(opcode: .close, payload: payload)) { [weak self] in
            self?.teardown()
        }
        scheduleCloseFallback()
    }

    private func sendCloseAndCancel(code: UInt16, reason: String) {
        guard !isClosed else { return }
        sendClosePayloadAndCancel(BrowserEndpointFrame.close(code: code, reason: reason).payload)
    }

    private func scheduleCloseFallback() {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.teardown()
        }
    }

    private func sendFrame(
        _ frame: BrowserEndpointFrame,
        completion: (() -> Void)? = nil
    ) {
        guard !isClosed else { return }
        connection.send(
            content: frame.encoded(masked: false),
            completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil {
                    self.teardown()
                } else {
                    completion?()
                }
            }
        )
    }

    private func teardown() {
        guard !isClosed else { return }
        isClosed = true
        phase = .closed
        cancelHandshakeTimer()
        stopHeartbeat()
        connection.stateUpdateHandler = nil
        connection.cancel()
        closedHandler(id)
    }
}
