import Foundation
import OSLog

@MainActor
final class CastRuntimeEndpoint: RuntimeEndpoint {
    let location: RuntimeLocation = .castReceiver
    private let cast: CastSessionCoordinator
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "CastRuntime")

    private(set) var identifier = "Cast receiver"
    private(set) var state: RuntimeState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    private(set) var capabilities: RuntimeCapabilities = .wanixDesktop
    var onStateChange: ((RuntimeState) -> Void)?

    private var sessionId = ""
    private var generation = 0
    private var workspace: Workspace = .default
    private var device: CastDevice?
    private var observerToken: UUID?
    private var resumeTask: Task<Void, Never>?
    private var isStopping = false
    private(set) var lastAcceptedInputSeq = 0

    init(cast: CastSessionCoordinator) {
        self.cast = cast
    }

    func start(context: RuntimeContext) async throws {
        if state != .idle, state != .stopped {
            await stop()
        }

        guard let connectedDevice = cast.connectedDevice else {
            state = .failed
            throw CastAdapterError.notConnected
        }

        isStopping = false
        sessionId = context.sessionId
        generation = context.generation
        workspace = context.workspace
        device = connectedDevice
        lastAcceptedInputSeq = 0
        state = .preparing
        identifier = "Cast receiver"
        capabilities = .wanixDesktop

        observerToken = cast.addControlObserver { [weak self] message in
            self?.handleControl(message)
        }
        cast.onConnectionStateChange = { [weak self] state in
            self?.handleConnectionState(state)
        }

        let start = CastControlMessage.sessionStart(
            sessionId: context.sessionId,
            generation: context.generation,
            workspace: context.workspace.name,
            appearance: context.appearance
        )
        guard let validatedStart = try? start.validated() else {
            state = .failed
            throw CastProtocolError.invalidField
        }
        cast.sendControl(validatedStart)

        do {
            let ready = try await cast.waitForReady(
                sessionId: context.sessionId,
                generation: context.generation
            )
            applyReady(ready)
        } catch {
            state = .failed
            throw error
        }
    }

    func send(_ event: InputEvent) {
        guard acceptsInput else { return }
        guard event.sessionId == sessionId, (event.generation ?? 0) == generation else { return }
        cast.send(event)
    }

    func sendControl(_ control: RuntimeControl) {
        switch control {
        case .workspace(let workspace):
            self.workspace = workspace
            guard let message = try? CastControlMessage.workspace(
                sessionId: sessionId,
                generation: generation,
                workspace: workspace.name
            ).validated() else { return }
            cast.sendControl(message)
        case .appearance(let appearance):
            guard let message = try? CastControlMessage.appearance(
                sessionId: sessionId,
                generation: generation,
                appearance: appearance
            ).validated() else { return }
            cast.sendControl(message)
        case .suspend, .resume:
            break
        case .shutdown:
            Task { [weak self] in
                await self?.stop()
            }
        }
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        resumeTask?.cancel()
        resumeTask = nil
        cast.onConnectionStateChange = nil

        if let observerToken {
            cast.removeControlObserver(observerToken)
            self.observerToken = nil
        }

        if !sessionId.isEmpty, cast.connectedDevice != nil,
           let end = try? CastControlMessage.sessionEnd(
               sessionId: sessionId,
               generation: generation
           ).validated() {
            cast.sendControl(end)
        }

        cast.disconnect()
        state = .stopped
        sessionId = ""
        device = nil
    }

    private func applyReady(_ ready: CastControlMessage) {
        identifier = "Cast \(ready.receiverVersion ?? CastProtocol.receiverVersion)"
        capabilities = Self.capabilities(from: ready)
        lastAcceptedInputSeq = ready.lastAcceptedInputSeq ?? 0
        state = .ready
        logger.info("Cast receiver ready at \(ready.width ?? 0, privacy: .public)x\(ready.height ?? 0, privacy: .public)")
    }

    private func handleControl(_ message: CastControlMessage) {
        guard message.sessionId == sessionId, message.generation == generation else { return }

        switch message.type {
        case .ready:
            applyReady(message)
        case .state:
            guard let receiverState = message.state.flatMap(RuntimeState.init(rawValue:)) else { return }
            state = receiverState
        case .ack:
            if let seq = message.lastAcceptedInputSeq {
                lastAcceptedInputSeq = max(lastAcceptedInputSeq, seq)
            }
        case .error:
            state = .failed
        default:
            break
        }
    }

    private func handleConnectionState(_ connection: CastConnectionState) {
        guard !isStopping, connection == .idle, !sessionId.isEmpty else { return }
        guard state == .ready || state == .recovering else { return }
        beginResume()
    }

    private func beginResume() {
        guard resumeTask == nil, let device else { return }
        state = .recovering
        resumeTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 1...3 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 750_000_000)
                guard !Task.isCancelled, !self.isStopping else { return }

                do {
                    try await self.cast.connect(to: device)
                    guard let resume = try? CastControlMessage.sessionResume(
                        sessionId: self.sessionId,
                        generation: self.generation,
                        lastAckedInputSeq: self.lastAcceptedInputSeq
                    ).validated() else { throw CastProtocolError.invalidField }
                    self.cast.sendControl(resume)
                    let ready = try await self.cast.waitForReady(
                        sessionId: self.sessionId,
                        generation: self.generation
                    )
                    self.applyReady(ready)
                    self.resumeTask = nil
                    return
                } catch {
                    continue
                }
            }
            guard !Task.isCancelled, !self.isStopping else { return }
            self.state = .failed
            self.resumeTask = nil
        }
    }

    private static func capabilities(from ready: CastControlMessage) -> RuntimeCapabilities {
        let reported = ready.capabilities ?? .desktop
        let persistence = ready.persistence ?? ""
        return RuntimeCapabilities(
            desktopWindows: reported.desktopWindows,
            terminal: reported.desktopWindows && reported.keyboard,
            filesystem: false,
            workbench: reported.desktopWindows,
            browser: false,
            persistentStorage: ["opfs", "indexeddb", "indexedDB"].contains(persistence),
            liveKernel: false,
            taskExecution: false
        )
    }
}
