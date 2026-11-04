import Combine
import Foundation
import UIKit

@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let settings: AppSettings
    let diagnostics: PerformanceMetrics
    let display: DisplayCoordinator
    let cast: CastSessionCoordinator
    let entitlements: EntitlementManager
    let haptics: Haptics
    lazy var session: SessionCoordinator = {
        SessionCoordinator(
            settings: settings,
            diagnostics: diagnostics,
            display: display,
            cast: cast,
            entitlements: entitlements
        )
    }()

    @Published var isSettingsPresented = false
    @Published var isDiagnosticsPresented = false
    @Published var isProPresented = false
    @Published private(set) var workspaceRestoreReport: WorkspaceRestoreReport?
    @Published private(set) var workspaceRestoreError: String?
    @Published private(set) var workspaceHostState: WorkspaceHostState = .active
    @Published private(set) var workspaceLifecycle: WorkspaceLifecycleStore?

    var workspaceStatusPresentation: WorkspaceStatusPresentation? {
        if let workspaceRestoreError {
            return WorkspaceStatusPresentation(
                title: "Workspace unavailable",
                detail: workspaceRestoreError,
                severity: .error
            )
        }
        return workspaceRestoreReport?.presentation ?? workspaceHostState.presentation
    }

    private var workspaceBootstrapper: WorkspaceBootstrapper?
    private var bootstrapped = false
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    private static let externalSSHFixtureKey = "airdesk.debug.externalSSHFixture"
    private var remoteSSHTestServer: RemoteSSHTestServer?
    #endif

    private init() {
        settings = AppSettings()
        diagnostics = PerformanceMetrics()
        display = DisplayCoordinator()
        cast = CastSessionCoordinator()
        entitlements = EntitlementManager()
        haptics = Haptics.shared
    }

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        display.setPresentationMode(settings.displayMode)
        display.onExternalDisplayConnected = { [weak self] container in
            self?.session.externalDisplayDidConnect(container)
        }
        display.onExternalDisplayDisconnected = { [weak self] in
            self?.session.externalDisplayDidDisconnect()
        }
        display.onMirroringChanged = { [weak self] isMirroring in
            self?.session.displayMirroringDidChange(isMirroring)
        }

        settings.$displayMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                Task { @MainActor in
                    self?.display.setPresentationMode(mode)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            session.$phase,
            session.$mode,
            display.$isExternalDisplayConnected,
            cast.$state
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] phase, mode, isExternalConnected, castState in
            Task { @MainActor in
                self?.updateIdleTimer(
                    phase: phase,
                    mode: mode,
                    isExternalConnected: isExternalConnected,
                    castState: castState
                )
            }
        }
        .store(in: &cancellables)

        cast.onInput = { [weak self] event in
            self?.session.castDidReceive(event)
        }

        entitlements.start()
        Haptics.shared.prepare()
        diagnostics.mark("app.launch")
        bootstrapWorkspace()

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let externalFixture = arguments.contains("-AirDeskRemoteSSHExternal")
        let remoteFixture = arguments.contains("-AirDeskRemoteSSHTest")
            || arguments.contains("-AirDeskRemoteSSHReconnectTest")
        if externalFixture {
            UserDefaults.standard.set(true, forKey: Self.externalSSHFixtureKey)
            let environment = ProcessInfo.processInfo.environment
            settings.remoteTerminalEnabled = true
            settings.remoteTerminalHost = environment["AIRDESK_SSH_HOST"] ?? "127.0.0.1"
            settings.remoteTerminalPort = Int(environment["AIRDESK_SSH_PORT"] ?? "") ?? 22
            settings.remoteTerminalUsername = environment["AIRDESK_SSH_USERNAME"] ?? ""
            settings.remoteTerminalHostKey = environment["AIRDESK_SSH_HOST_KEY"] ?? ""
            settings.remoteTerminalStartupCommand = environment["AIRDESK_SSH_STARTUP"] ?? ""
            settings.remoteTerminalPassword = ""
            try? settings.saveRemoteTerminalPassword()
            scheduleAutoDemo(arguments: arguments)
        } else if remoteFixture {
            Task { @MainActor in
                do {
                    let server = try await RemoteSSHTestServer.start(
                        dropFirstSession: arguments.contains("-AirDeskRemoteSSHReconnectTest")
                    )
                    self.remoteSSHTestServer = server
                    self.settings.remoteTerminalEnabled = true
                    self.settings.remoteTerminalHost = "127.0.0.1"
                    self.settings.remoteTerminalPort = server.port
                    self.settings.remoteTerminalUsername = "tester"
                    self.settings.remoteTerminalHostKey = server.hostKeyString
                    self.settings.remoteTerminalStartupCommand = "tmux new -A -s airdesk"
                    self.settings.remoteTerminalPassword = "secret"
                    try? self.settings.saveRemoteTerminalPassword()
                } catch {
                    self.settings.remoteTerminalEnabled = false
                }

                if arguments.contains("-AirDeskAutoDemo") {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    guard self.session.phase == .idle else { return }
                    self.session.beginConnection(to: .previewDevice)
                }
            }
        } else {
            let hadExternalFixture = UserDefaults.standard.bool(forKey: Self.externalSSHFixtureKey)
            if hadExternalFixture {
                UserDefaults.standard.removeObject(forKey: Self.externalSSHFixtureKey)
            }
            if hadExternalFixture || settings.remoteTerminalHost == "127.0.0.1" {
                clearRemoteTerminalSettings()
            }
            scheduleAutoDemo(arguments: arguments)
        }
        NativeSmokeTest.runIfRequested(session: session)
        #endif
    }

    private func bootstrapWorkspace() {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "device.local"
        do {
            let bootstrapper = try WorkspaceBootstrapper.applicationSupport(deviceId: deviceId)
            let report = try bootstrapper.restore(
                owner: WorkspaceOwner(identityId: "person.local", displayName: "Local User"),
                name: "Wanix"
            )
            workspaceBootstrapper = bootstrapper
            workspaceRestoreReport = report
            workspaceHostState = bootstrapper.host.state
            workspaceLifecycle = WorkspaceLifecycleStore(host: bootstrapper.host)
            session.adoptBootWorkspace(
                Workspace(
                    id: report.workspaceId,
                    name: report.workspaceName,
                    runtime: settings.runtimeChoice.title,
                    createdAt: report.createdAt
                )
            )
        } catch {
            workspaceRestoreError = error.localizedDescription
        }
    }

    #if DEBUG
    private func clearRemoteTerminalSettings() {
        settings.remoteTerminalEnabled = false
        settings.remoteTerminalHost = ""
        settings.remoteTerminalHostKey = ""
        settings.remoteTerminalUsername = ""
        settings.remoteTerminalPassword = ""
        try? settings.saveRemoteTerminalPassword()
    }

    private func scheduleAutoDemo(arguments: [String]) {
        guard arguments.contains("-AirDeskAutoDemo") else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard session.phase == .idle else { return }
            session.beginConnection(to: .previewDevice)
        }
    }
    #endif

    private func updateIdleTimer(
        phase: SessionPhase,
        mode: SessionMode,
        isExternalConnected: Bool,
        castState: CastConnectionState
    ) {
        let keepAwake = phase == .ready &&
            (isExternalConnected || mode == .cast || castState == .connected)
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }
}
