import Foundation

enum CameraCaptureState: Equatable {
    case idle
    case starting
    case running
    case stopped
    case cancelled
    case failed
}

struct CameraCaptureMetrics: Equatable {
    var receivedFrames = 0
    var admittedFrames = 0
    var droppedFrames = 0
    var oversizedFrames = 0
    var totalBytes = 0
}

final class CameraFrameStream: AsyncSequence {
    typealias Element = CameraFrame

    enum YieldResult {
        case enqueued
        case dropped
        case terminated
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let stream: CameraFrameStream

        mutating func next() async throws -> CameraFrame? {
            try await stream.next()
        }
    }

    private enum Termination {
        case finished
        case failed(Error)
    }

    private enum NextOutcome {
        case frame(CameraFrame)
        case termination(Termination)
    }

    private let lock = NSLock()
    private let limit: Int
    private var buffer: [CameraFrame] = []
    private var waiters: [CheckedContinuation<CameraFrame?, Error>] = []
    private var termination: Termination?

    init(maxBufferedFrames: Int) {
        self.limit = Swift.max(1, maxBufferedFrames)
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(stream: self)
    }

    @discardableResult
    func yield(_ frame: CameraFrame) -> YieldResult {
        lock.lock()
        guard termination == nil else {
            lock.unlock()
            return .terminated
        }
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume(returning: frame)
            return .enqueued
        }
        guard buffer.count < limit else {
            lock.unlock()
            return .dropped
        }
        buffer.append(frame)
        lock.unlock()
        return .enqueued
    }

    func finish(throwing error: Error? = nil) {
        lock.lock()
        guard termination == nil else {
            lock.unlock()
            return
        }
        termination = error.map(Termination.failed) ?? .finished
        buffer.removeAll(keepingCapacity: false)
        let waiters = self.waiters
        self.waiters.removeAll(keepingCapacity: false)
        lock.unlock()

        for waiter in waiters {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume(returning: nil)
            }
        }
    }

    private func next() async throws -> CameraFrame? {
        if let outcome = pollNext() {
            switch outcome {
            case .frame(let frame):
                return frame
            case .termination(let termination):
                return try result(for: termination)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            register(continuation)
        }
    }

    private func pollNext() -> NextOutcome? {
        lock.lock()
        defer { lock.unlock() }
        if !buffer.isEmpty {
            return .frame(buffer.removeFirst())
        }
        if let termination {
            return .termination(termination)
        }
        return nil
    }

    private func register(_ continuation: CheckedContinuation<CameraFrame?, Error>) {
        lock.lock()
        if !buffer.isEmpty {
            let frame = buffer.removeFirst()
            lock.unlock()
            continuation.resume(returning: frame)
            return
        }
        if let termination {
            lock.unlock()
            switch termination {
            case .finished:
                continuation.resume(returning: nil)
            case .failed(let error):
                continuation.resume(throwing: error)
            }
            return
        }
        waiters.append(continuation)
        lock.unlock()
    }

    private func result(for termination: Termination) throws -> CameraFrame? {
        switch termination {
        case .finished:
            return nil
        case .failed(let error):
            throw error
        }
    }
}

@MainActor
final class CameraCaptureStreamController {
    static let capabilityURI = CapabilityCatalog.cameraCapUri
    static let captureOperation = "capture"

    private let agent: DeviceAgent
    private let source: any CameraCaptureSource
    private let nowMillis: () -> Int64
    private let stream: CameraFrameStream
    private var leaseSubscription: DeviceAgentSubscription?
    private var maximumFrameBytes = 0

    private(set) var state: CameraCaptureState = .idle
    private(set) var activeLease: DeviceAgentLease?
    private(set) var metrics = CameraCaptureMetrics()

    var frames: CameraFrameStream {
        stream
    }

    var isRunning: Bool {
        state == .running
    }

    init(
        agent: DeviceAgent,
        source: any CameraCaptureSource,
        maxBufferedFrames: Int = 2,
        nowMillis: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.agent = agent
        self.source = source
        self.nowMillis = nowMillis
        self.stream = CameraFrameStream(maxBufferedFrames: maxBufferedFrames)
    }

    func start(
        request: DeviceAgentCapabilityRequest,
        configuration: CameraCaptureConfiguration = .standard
    ) async throws {
        guard state == .idle else {
            throw state == .running || state == .starting
                ? CameraCaptureError.alreadyRunning
                : CameraCaptureError.finished
        }
        try configuration.validate()
        guard request.capUri == Self.capabilityURI else {
            throw CameraCaptureError.invalidRequest("capability URI")
        }
        guard request.operations.contains(Self.captureOperation) else {
            throw CameraCaptureError.invalidRequest("capture operation")
        }

        state = .starting
        maximumFrameBytes = configuration.maximumFrameBytes
        metrics = CameraCaptureMetrics()

        let lease: DeviceAgentLease
        do {
            lease = try agent.requestCapability(request)
        } catch {
            state = .idle
            throw Self.map(error)
        }
        activeLease = lease

        do {
            leaseSubscription = try agent.subscribe(eventType: "lease") { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.handleLeaseEvent(event)
                }
            }
        } catch {
            releaseLease()
            state = .idle
            throw Self.map(error)
        }

        do {
            try validateSource()
            try await source.start(configuration: configuration) { [weak self] frame in
                self?.handleFrame(frame)
            }
            guard state == .starting else { return }
            state = .running
        } catch {
            let typed = Self.map(error)
            leaseSubscription?.cancel()
            leaseSubscription = nil
            await source.stop()
            releaseLease()
            if state == .starting {
                state = .idle
            }
            throw typed
        }
    }

    func stop() async {
        guard state == .running || state == .starting else { return }
        state = .stopped
        leaseSubscription?.cancel()
        leaseSubscription = nil
        releaseLease()
        stream.finish()
        await source.stop()
    }

    func cancel() async {
        switch state {
        case .running, .starting:
            state = .cancelled
            leaseSubscription?.cancel()
            leaseSubscription = nil
            releaseLease()
            stream.finish(throwing: CameraCaptureError.cancelled)
            await source.stop()
        case .idle:
            state = .cancelled
            stream.finish(throwing: CameraCaptureError.cancelled)
        case .stopped, .cancelled, .failed:
            break
        }
    }

    private func validateSource() throws {
        guard source.isAvailable else {
            throw CameraCaptureError.cameraUnavailable
        }
        switch source.permissionStatus {
        case .authorized:
            break
        case .notDetermined:
            throw CameraCaptureError.permissionNotDetermined
        case .denied:
            throw CameraCaptureError.permissionDenied(CapabilityCatalog.cameraPermission)
        case .restricted:
            throw CameraCaptureError.permissionRestricted
        }
    }

    private func handleFrame(_ frame: CameraFrame) {
        guard state == .starting || state == .running else { return }
        guard let lease = activeLease else {
            fail(.authorizationRevoked)
            return
        }

        metrics.receivedFrames += 1
        metrics.totalBytes += frame.bytes.count

        guard frame.bytes.count <= maximumFrameBytes else {
            metrics.oversizedFrames += 1
            return
        }
        guard nowMillis() < lease.expiresAtEpochMillis else {
            fail(.leaseExpired)
            return
        }
        guard agent.activeLeases().contains(where: { $0.leaseId == lease.leaseId }) else {
            fail(.authorizationRevoked)
            return
        }

        switch stream.yield(frame) {
        case .enqueued:
            metrics.admittedFrames += 1
        case .dropped:
            metrics.droppedFrames += 1
        case .terminated:
            break
        @unknown default:
            metrics.droppedFrames += 1
        }
    }

    private func handleLeaseEvent(_ event: DeviceAgentEvent) {
        guard let lease = activeLease, event.leaseId == lease.leaseId else { return }
        switch event.action {
        case "revoked", "released":
            fail(.authorizationRevoked)
        default:
            break
        }
    }

    private func fail(_ error: CameraCaptureError) {
        guard state == .running || state == .starting else { return }
        state = .failed
        leaseSubscription?.cancel()
        leaseSubscription = nil
        releaseLease()
        stream.finish(throwing: error)
        let source = self.source
        Task { await source.stop() }
    }

    private func releaseLease() {
        guard let lease = activeLease else { return }
        activeLease = nil
        try? agent.releaseCapability(leaseId: lease.leaseId)
    }

    private static func map(_ error: Error) -> CameraCaptureError {
        if let error = error as? CameraCaptureError {
            return error
        }
        if let error = error as? DeviceAgentError {
            return CameraCaptureError(deviceAgentError: error)
        }
        return .sourceFailure(error.localizedDescription)
    }
}
