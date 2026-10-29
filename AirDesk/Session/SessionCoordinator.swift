import CoreGraphics
import Foundation
import OSLog
import UIKit

enum SessionPhase: String, Equatable, Sendable {
    case idle
    case connecting
    case ready
    case failed
}

enum ConnectionStage: String, Equatable, Sendable {
    case idle
    case discovering
    case pairing
    case launching
    case verifying
    case ready

    var title: String {
        switch self {
        case .idle: return "Preparing"
        case .discovering: return "Looking for the display"
        case .pairing: return "Establishing the session"
        case .launching: return "Launching Wanix"
        case .verifying: return "Verifying the desktop"
        case .ready: return "Desktop ready"
        }
    }

    var detail: String {
        switch self {
        case .idle: return "Getting things ready."
        case .discovering: return "Confirming the selected display is reachable."
        case .pairing: return "Negotiating the display and input channel."
        case .launching: return "Starting the desktop runtime and workspace."
        case .verifying: return "Waiting for the runtime to report readiness."
        case .ready: return "The Air Cursor is ready."
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0.05
        case .discovering: return 0.18
        case .pairing: return 0.38
        case .launching: return 0.66
        case .verifying: return 0.88
        case .ready: return 1
        }
    }
}

enum CursorAction: Equatable {
    case move(dx: CGFloat, dy: CGFloat)
    case click(count: Int)
    case rightClick
    case dragBegan
    case dragEnded
    case scroll(dx: CGFloat, dy: CGFloat)
    case cancel
}

@MainActor
final class SessionCoordinator: ObservableObject {
    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var stage: ConnectionStage = .idle
    @Published private(set) var selectedDevice: DisplayDevice?
    @Published private(set) var mode: SessionMode = .preview
    @Published private(set) var profile: DisplayProfile = .preview
    @Published private(set) var runtimeState: RuntimeState = .idle
    @Published private(set) var runtimeName = "Wanix"
    @Published private(set) var capabilities: RuntimeCapabilities = .wanixDesktop
    @Published private(set) var lastError: String?
    @Published private(set) var notice: String?
    @Published private(set) var sessionId = ""
    @Published private(set) var sessionGeneration = 0
    @Published private(set) var workspace: Workspace = .default
    @Published private(set) var modifiers: Set<InputModifier> = []
    private(set) var isDragging = false
    @Published private(set) var isDemoConnection = false
    @Published private(set) var isExternalConnected = false
    @Published private(set) var recoveryAttempts = 0
    @Published var isPreviewPresented = false
    @Published private(set) var previewKeyboardShowRequest = 0
    @Published private(set) var previewKeyboardDismissRequest = 0
    @Published private(set) var debugJSLog = ""

    var recoveryMaximumAttempts: Int { recovery.maximumAttempts }

    let desktopSurface: DesktopSurface
    let dispatcher: InputDispatcher
    private let inputTransport: SessionInputTransport
    private let host: SurfaceRuntimeHost
    private let endpointFactory: @MainActor (DisplayProfile) -> (any RuntimeEndpoint)?
    private let settings: AppSettings
    private let diagnostics: PerformanceMetrics
    private let display: DisplayCoordinator
    private let cast: CastSessionCoordinator
    private let entitlements: EntitlementManager
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "Session")

    private var endpoint: (any RuntimeEndpoint)?
    private var runtime: (any DesktopRuntime)?
    private var stopTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var pointer = PointerState()
    private var recovery = SessionRecovery()
    private var nativeInputCaptured = false
    private var previewKeyboardRouting = false

    init(
        settings: AppSettings,
        diagnostics: PerformanceMetrics,
        display: DisplayCoordinator,
        cast: CastSessionCoordinator,
        entitlements: EntitlementManager,
        endpointFactory: (@MainActor (DisplayProfile) -> (any RuntimeEndpoint)?)? = nil
    ) {
        let surface = DesktopSurface()
        self.settings = settings
        self.diagnostics = diagnostics
        self.display = display
        self.cast = cast
        self.entitlements = entitlements
        self.desktopSurface = surface
        self.dispatcher = InputDispatcher()
        self.inputTransport = SessionInputTransport()
        self.host = SurfaceRuntimeHost(surface: surface)
        self.endpointFactory = endpointFactory ?? { profile in
            switch profile.runtime {
            case .castReceiver:
                return CastRuntimeEndpoint(cast: cast)
            case .phone:
                return LocalRuntimeEndpoint(
                    host: SurfaceRuntimeHost(surface: surface),
                    runtimeFactory: {
                        RuntimeFactory.make(
                            choice: settings.runtimeChoice,
                            appearance: settings.desktopAppearance
                        )
                    }
                )
            case .androidDevice, .remote:
                return nil
            }
        }

        isExternalConnected = display.isExternalDisplayConnected
        inputTransport.cast = cast
        cast.addControlObserver { [weak self] message in
            self?.handleCastControl(message)
        }
        dispatcher.transport = inputTransport
        dispatcher.onEventSent = { [weak self] event in
            self?.diagnostics.recordSent(event)
        }

        desktopSurface.onMessage = { [weak self] message in
            self?.handleBridgeMessage(message)
        }
        desktopSurface.onReady = { [weak self] in
            guard let self, self.phase == .ready else { return }
            self.runtimeState = .ready
            self.pushInputRouting()
        }
        desktopSurface.onFailure = { [weak self] error in
            guard let self else { return }
            if let surfaceError = error as? DesktopSurfaceError, surfaceError == .processTerminated, self.phase == .ready {
                self.beginRecovery()
            }
        }
    }

    var isBusy: Bool {
        phase == .connecting
    }

    var canUseDesktopControls: Bool {
        phase == .ready && (runtimeState == .ready || runtimeState == .recovering)
    }

    var canShowPreview: Bool {
        guard phase == .ready else { return false }
        if display.hasExternalDisplay { return false }
        if effectiveMode == .mirrored { return false }
        if mode == .cast { return false }
        return true
    }

    var effectiveMode: SessionMode {
        DisplayModeResolver.effectiveMode(
            current: mode,
            hasExternalDisplay: display.hasExternalDisplay,
            isMirroring: display.isMirroring
        )
    }

    var connectionStage: ConnectionStage {
        phase == .ready ? .ready : stage
    }

    var sessionSummary: String {
        guard phase != .idle else { return "No active session" }
        return "\(effectiveMode.shortTitle) · \(runtimeName) · \(runtimeState.title)"
    }

    func beginConnection(to device: DisplayDevice) {
        guard phase != .connecting else { return }
        recoveryTask?.cancel()
        recoveryTask = nil
        connectTask?.cancel()
        connectTask = nil
        prepareForNewSession()
        selectedDevice = device
        lastError = nil
        notice = nil

        let requestedRuntime = settings.runtimeChoice
        if requestedRuntime.requiresPro && !entitlements.canUse(requestedRuntime) {
            settings.runtimeChoice = .wanixDesktop
            setNotice("\(requestedRuntime.title) requires AirDesk Pro. Using Wanix Desktop for this session.")
        }

        phase = .connecting
        stage = .discovering
        sessionId = Self.makeSessionId()
        sessionGeneration += 1
        workspace = .default

        do {
            let resolved = try DisplayProfileResolver.resolve(
                mode: resolvedMode(for: device),
                device: device
            )
            mode = resolved.mode
            profile = resolved
        } catch {
            phase = .failed
            stage = .idle
            lastError = friendlyMessage(for: error)
            return
        }

        inputTransport.route = profile.input == .castChannel ? .cast : .endpoint
        isDemoConnection = device.isDemo || device.kind == .preview
        isExternalConnected = display.isExternalDisplayConnected
        runtimeName = settings.runtimeChoice.title
        capabilities = settings.runtimeChoice == .wanixKernel ? .wanixKernel : .wanixDesktop
        diagnostics.beginSession(sessionId)
        diagnostics.mark("session.connect.\(device.kind.rawValue)")

        let chosenDevice = device
        connectTask = Task { [weak self] in
            await self?.performConnection(chosenDevice)
        }
    }

    func cancelConnection() {
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryAttempts = 0
        connectTask?.cancel()
        connectTask = nil
        dispatcher.endSession()
        stopRuntime()
        desktopSurface.onStateChange = nil
        phase = .idle
        stage = .idle
        selectedDevice = nil
        runtimeState = .idle
        mode = .preview
        profile = .preview
        inputTransport.route = .endpoint
        isDemoConnection = false
        isPreviewPresented = false
        sessionId = ""
        lastError = nil
        diagnostics.endSession()
        desktopSurface.returnHome()
    }

    func disconnect() {
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryAttempts = 0
        connectTask?.cancel()
        connectTask = nil
        dispatcher.endSession()
        stopRuntime()
        desktopSurface.returnHome()
        display.detach(surface: desktopSurface)
        phase = .idle
        stage = .idle
        selectedDevice = nil
        runtimeState = .idle
        mode = .preview
        profile = .preview
        inputTransport.route = .endpoint
        isDemoConnection = false
        isPreviewPresented = false
        sessionId = ""
        lastError = nil
        notice = nil
        modifiers.removeAll()
        isDragging = false
        pointer.center()
        recovery.reset()
        diagnostics.endSession()
    }

    func retry() {
        guard let device = selectedDevice else { return }
        recovery.reset()
        recoveryAttempts = 0
        beginConnection(to: device)
    }

    func dismissError() {
        lastError = nil
        if phase == .failed, selectedDevice == nil {
            phase = .idle
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    func openPreview() {
        guard phase == .ready else { return }
        if display.hasExternalDisplay {
            setNotice("The desktop is already on the external display.")
            return
        }
        if effectiveMode == .mirrored {
            setNotice("The desktop is already visible in AirPlay mirroring mode.")
            return
        }
        if mode == .cast {
            setNotice("The Cast receiver is rendering this desktop on the display.")
            return
        }
        isPreviewPresented = true
        diagnostics.mark("preview.open")
    }

    func closePreview() {
        isPreviewPresented = false
        if display.hasExternalDisplay {
            display.present(surface: desktopSurface)
        } else {
            desktopSurface.returnHome()
        }
    }

    func externalDisplayDidConnect(_ container: UIView) {
        _ = container
        isExternalConnected = true
        guard phase == .ready else { return }
        guard selectedDevice?.kind != .cast, selectedDevice?.kind != .preview else { return }
        setMode(.extended)
        isPreviewPresented = false
        display.present(surface: desktopSurface)
        setNotice("Extended desktop connected.")
        diagnostics.mark("display.connected")
    }

    func externalDisplayDidDisconnect() {
        isExternalConnected = false
        guard phase == .ready else { return }
        desktopSurface.returnHome()
        if mode == .extended {
            setMode(fallbackMode())
        }
        setNotice("Display disconnected. The session is preserved.")
        diagnostics.mark("display.disconnected")
    }

    func displayMirroringDidChange(_ isMirroring: Bool) {
        isExternalConnected = display.isExternalDisplayConnected
        guard phase == .ready else { return }
        guard selectedDevice?.kind != .cast, selectedDevice?.kind != .preview else { return }

        if isMirroring {
            setMode(.mirrored)
            isPreviewPresented = false
            desktopSurface.returnHome()
            setNotice("AirPlay mirroring connected. Open Preview to show the desktop on the TV.")
            diagnostics.mark("display.mirroring.connected")
        } else {
            if mode == .mirrored {
                setMode(fallbackMode())
            }
            desktopSurface.returnHome()
            setNotice("AirPlay mirroring ended. The session is preserved.")
            diagnostics.mark("display.mirroring.disconnected")
        }
    }

    func handleCursor(_ action: CursorAction, viewport: CGSize) {
        guard canUseDesktopControls else { return }
        pointer.sensitivity = settings.pointerSensitivity
        pointer.accelerationEnabled = settings.pointerAcceleration

        switch action {
        case .move(let dx, let dy):
            let point = pointer.move(delta: CGSize(width: dx, height: dy), viewport: viewport)
            dispatcher.move(to: point)
        case .click(let count):
            dispatcher.click(button: 0, count: count)
            if settings.hapticsEnabled { Haptics.shared.click() }
        case .rightClick:
            dispatcher.click(button: 1, count: 1)
            if settings.hapticsEnabled { Haptics.shared.click() }
        case .dragBegan:
            dispatcher.pointerDown(button: 0)
            isDragging = true
            if settings.hapticsEnabled { Haptics.shared.dragStart() }
        case .dragEnded:
            dispatcher.pointerUp(button: 0)
            isDragging = false
        case .scroll(let dx, let dy):
            let (sx, sy) = PointerState.scrollDelta(
                dx: Double(dx),
                dy: Double(dy),
                naturalScrolling: settings.naturalScrolling
            )
            dispatcher.scroll(dx: sx, dy: sy)
            if settings.hapticsEnabled { Haptics.shared.scrollTick() }
        case .cancel:
            dispatcher.cancelAllInput()
            isDragging = false
        }
    }

    func sendKey(_ key: String, code: String? = nil, eventModifiers: Set<InputModifier>? = nil) {
        print("[AirDeskDebug] sendKey \(key) canUse=\(canUseDesktopControls)")
        guard canUseDesktopControls else { return }
        dispatcher.tapKey(key, code: code, modifiers: eventModifiers ?? modifiers)
        if settings.hapticsEnabled { Haptics.shared.tap() }
    }

    func sendText(_ text: String, eventModifiers: Set<InputModifier>? = nil) {
        print("[AirDeskDebug] sendText \(text.debugDescription) canUse=\(canUseDesktopControls)")
        guard canUseDesktopControls, !text.isEmpty else { return }
        let activeModifiers = eventModifiers ?? modifiers
        if activeModifiers.isEmpty {
            dispatcher.textInput(text)
        } else {
            for character in text {
                let key = String(character)
                dispatcher.keyDown(key, modifiers: activeModifiers)
                dispatcher.keyUp(key, modifiers: activeModifiers)
            }
        }
    }

    func toggleModifier(_ modifier: InputModifier) {
        if modifiers.contains(modifier) {
            modifiers.remove(modifier)
        } else {
            modifiers.insert(modifier)
        }
        if settings.hapticsEnabled { Haptics.shared.tap() }
    }

    func clearModifiers() {
        modifiers.removeAll()
    }

    func dockAction() {
        guard canUseDesktopControls else { return }
        desktopSurface.sendControl(type: "action", payload: ["action": "dock"])
        if settings.hapticsEnabled { Haptics.shared.tap() }
    }

    func setNativeInputCaptured(_ captured: Bool) {
        if nativeInputCaptured != captured, captured {
            previewKeyboardDismissRequest += 1
        }
        nativeInputCaptured = captured
        pushInputRouting()
    }

    func setPreviewKeyboardRouting(_ enabled: Bool) {
        previewKeyboardRouting = enabled
        pushInputRouting()
    }

    private func pushInputRouting() {
        desktopSurface.sendControl(type: "inputMode", payload: ["captured": nativeInputCaptured])
        desktopSurface.sendControl(type: "previewInput", payload: ["enabled": previewKeyboardRouting])
    }

    func openDiagnosticsAction() {
        AppEnvironment.shared.isDiagnosticsPresented = true
    }



    func castDidReceive(_ event: InputEvent) {
        guard phase == .ready else { return }
        if isDemoConnection {
            desktopSurface.send(event)
        }
    }

    func settingsDidChange() {
        if let endpoint {
            endpoint.sendControl(.appearance(settings.desktopAppearance))
        } else {
            desktopSurface.sendControl(
                type: "appearance",
                payload: ["appearance": settings.desktopAppearance]
            )
        }
    }

    func sceneBecameActive() {
        guard phase == .ready else { return }
        if let endpoint {
            endpoint.sendControl(.resume)
            return
        }
        Task { [weak self] in
            guard let self, let runtime = self.runtime else { return }
            try? await runtime.resume()
        }
    }

    func sceneWillResignActive() {
        guard phase == .ready else { return }
        if let endpoint {
            endpoint.sendControl(.suspend)
            return
        }
        Task { [weak self] in
            await self?.runtime?.suspend()
        }
    }

    private func performConnection(_ device: DisplayDevice) async {
        if let stopTask {
            await stopTask.value
            self.stopTask = nil
        }

        let activeSessionId = sessionId
        let activeProfile = profile

        do {
            stage = .discovering
            try await pause(0.40)

            stage = .pairing
            if activeProfile.runtime == .castReceiver {
                let castDevice = CastDevice(
                    id: device.id,
                    name: device.name,
                    model: device.isDemo ? "AirDesk Demo Receiver" : "Cast device",
                    isDemo: device.isDemo
                )
                try await cast.connect(to: castDevice)
            } else {
                try await pause(0.55)
            }
            try Task.checkCancellation()

            inputTransport.route = activeProfile.input == .castChannel ? .cast : .endpoint

            runtimeState = .preparing
            stage = .launching
            let context = RuntimeContext(
                sessionId: activeSessionId,
                generation: sessionGeneration,
                workspace: workspace,
                appearance: settings.desktopAppearance
            )

            if let endpoint = endpointFactory(activeProfile) {
                self.endpoint = endpoint
                inputTransport.endpoint = endpoint
                endpoint.onStateChange = { [weak self] state in
                    guard let self, self.sessionId == activeSessionId else { return }
                    self.runtimeState = state
                }
                runtimeName = endpoint.identifier
                capabilities = endpoint.capabilities

                try await endpoint.start(context: context)
                try Task.checkCancellation()
                guard self.sessionId == activeSessionId, self.phase == .connecting else {
                    throw CancellationError()
                }

                runtimeName = endpoint.identifier
                capabilities = endpoint.capabilities
                runtimeState = endpoint.state
            } else {
                host.workspace = workspace
                host.sessionId = activeSessionId
                host.generation = sessionGeneration
                let runtime = RuntimeFactory.make(
                    choice: settings.runtimeChoice,
                    appearance: settings.desktopAppearance
                )
                runtime.onStateChange = { [weak self] state in
                    guard let self, self.sessionId == activeSessionId else { return }
                    self.runtimeState = state
                }
                self.runtime = runtime
                capabilities = runtime.capabilities
                runtimeName = runtime.identifier

                try await runtime.prepare(in: host)
                try Task.checkCancellation()
                try await runtime.loadWorkspace(workspace)
                try Task.checkCancellation()
                runtimeState = runtime.state
            }

            stage = .verifying
            try await pause(0.35)

            if display.hasExternalDisplay, activeProfile.mode != .cast {
                setMode(.extended)
                display.present(surface: desktopSurface)
            } else if activeProfile.mode != .cast {
                desktopSurface.attachHomeIfNeeded()
            }

            dispatcher.startSession(
                id: activeSessionId,
                generation: sessionGeneration,
                viewport: desktopSurface.lastViewport
            )
            pointer.center()
            dispatcher.move(to: pointer.position)
            dispatcher.flushPendingMove()

            phase = .ready
            stage = .ready
            recovery.reset()
            recoveryAttempts = 0
            diagnostics.mark("session.ready")
            logger.info("Session ready: \(self.sessionId, privacy: .public)")
            if settings.hapticsEnabled { Haptics.shared.tap() }
        } catch is CancellationError {
            return
        } catch {
            logger.error("Session failed: \(String(describing: error), privacy: .public)")
            phase = .failed
            stage = .idle
            runtimeState = .failed
            lastError = friendlyMessage(for: error)
            diagnostics.mark("session.failed")
            if settings.hapticsEnabled { Haptics.shared.error() }
            stopRuntime()
            inputTransport.route = .endpoint
            desktopSurface.returnHome()
        }
    }

    private func beginRecovery() {
        guard phase == .ready, recoveryTask == nil, selectedDevice != nil else { return }
        runtimeState = .recovering
        setNotice("Desktop process restarted. Restoring the workspace…")
        diagnostics.mark("session.recovery.begin")
        recoveryTask = Task { [weak self] in
            await self?.performRecovery()
        }
    }

    private func performRecovery() async {
        while recovery.canRetry {
            guard let delay = recovery.beginAttempt() else { break }
            recoveryAttempts = recovery.attempts
            diagnostics.mark("session.recovery.attempt.\(recovery.attempts)")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard phase == .ready, runtimeState == .recovering, let device = selectedDevice else {
                recoveryTask = nil
                return
            }
            recoveryTask = nil
            beginConnection(to: device)
            return
        }

        recoveryTask = nil
        guard !Task.isCancelled, phase == .ready else { return }
        phase = .failed
        stage = .idle
        runtimeState = .failed
        lastError = "The desktop process stopped repeatedly. Reconnect to restore the workspace."
        inputTransport.route = .endpoint
        desktopSurface.returnHome()
        diagnostics.mark("session.recovery.failed")
        if settings.hapticsEnabled { Haptics.shared.error() }
    }

    private func prepareForNewSession() {
        dispatcher.endSession()
        stopRuntime()
        desktopSurface.returnHome()
        isPreviewPresented = false
        modifiers.removeAll()
        isDragging = false
        pointer.center()
        runtimeState = .idle
    }

    private func resolvedMode(for device: DisplayDevice) -> SessionMode {
        DisplayModeResolver.resolvedMode(
            for: device.kind,
            hasExternalDisplay: display.hasExternalDisplay,
            isMirroring: display.isMirroring
        )
    }

    private func fallbackMode() -> SessionMode {
        DisplayModeResolver.fallbackMode(
            for: selectedDevice?.kind,
            hasExternalDisplay: display.hasExternalDisplay,
            isMirroring: display.isMirroring
        )
    }

    private func setMode(_ newMode: SessionMode) {
        guard mode != newMode else { return }
        mode = newMode

        guard let device = selectedDevice else {
            profile = .preview
            inputTransport.route = .endpoint
            return
        }

        do {
            profile = try DisplayProfileResolver.resolve(mode: newMode, device: device)
        } catch {
            profile = .preview
            lastError = friendlyMessage(for: error)
        }
        inputTransport.route = profile.input == .castChannel ? .cast : .endpoint
    }

    private func stopRuntime() {
        let endpoint = self.endpoint
        let runtime = self.runtime
        let hadEndpoint = endpoint != nil
        self.endpoint = nil
        self.runtime = nil
        inputTransport.endpoint = nil

        stopTask = Task {
            await endpoint?.stop()
            await runtime?.shutdown()
        }
        if !hadEndpoint, selectedDevice?.kind == .cast {
            cast.disconnect()
        }
    }

    private func handleBridgeMessage(_ message: BridgeMessage) {
        switch message.type {
        case "ack":
            if let seq = message.seq {
                diagnostics.recordAck(seq: seq)
            }
        case "action":
            switch message.action {
            case "preview": openPreview()
            case "disconnect": disconnect()
            case "diagnostics": openDiagnosticsAction()
            case "keyboard":
                print("[AirDeskDebug] bridge keyboard show")
                previewKeyboardShowRequest += 1
            case "keyboardDismiss":
                print("[AirDeskDebug] bridge keyboard dismiss")
                previewKeyboardDismissRequest += 1
            default: break
            }
        case "log":
            let text = message.message ?? ""
            print("[AirDeskDebug] js: \(text)")
            if ProcessInfo.processInfo.arguments.contains("-AirDeskUITestProbe") {
                let combined = debugJSLog.isEmpty ? text : debugJSLog + " | " + text
                debugJSLog = String(combined.suffix(500))
            }
        case "notice":
            if let text = message.message, !text.isEmpty {
                setNotice(String(text.prefix(180)))
            }
        case "error":
            if let text = message.message, !text.isEmpty {
                setNotice(String(text.prefix(180)))
            }
        default:
            break
        }
    }

    private func setNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private func handleCastControl(_ message: CastControlMessage) {
        guard message.sessionId == sessionId, message.generation == sessionGeneration else { return }

        switch message.type {
        case .ack:
            if let seq = message.lastAcceptedInputSeq {
                diagnostics.recordAck(seq: seq)
            }
        case .notice:
            if let text = message.message, !text.isEmpty {
                setNotice(String(text.prefix(180)))
            }
        case .error:
            if let text = message.message, !text.isEmpty {
                lastError = String(text.prefix(180))
            }
        default:
            break
        }
    }

    private func pause(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try Task.checkCancellation()
    }

    private func friendlyMessage(for error: Error) -> String {
        if let surfaceError = error as? DesktopSurfaceError {
            switch surfaceError {
            case .readyTimeout:
                return "The Wanix desktop did not report readiness. Check the network and try again."
            case .remoteRuntimeNotConfigured:
                return "This runtime needs a configured remote URL before it can launch."
            case .processTerminated:
                return "The desktop process stopped unexpectedly. Retry to restore the workspace."
            case .missingResource(let name):
                return "A required desktop resource is missing: \(name)."
            case .navigationFailed:
                return "The desktop could not load. Check the display connection and try again."
            }
        }
        if let profileError = error as? DisplayProfileError {
            return profileError.localizedDescription
        }
        if let castError = error as? CastAdapterError {
            return castError.localizedDescription
        }
        return error.localizedDescription
    }

    private static func makeSessionId() -> String {
        "ads-" + UUID().uuidString.prefix(8).lowercased()
    }
}

