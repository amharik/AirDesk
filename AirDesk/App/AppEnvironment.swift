import Combine
import CryptoKit
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
    let fabric: IrohFabricPeer
    let browserEndpoint: BrowserEndpointService
    let capabilityCatalog: CapabilityCatalog
    let deviceIdentityStore: DeviceIdentityStore
    let identity: DeviceIdentity?
    let identityError: String?
    let deviceRegistry: DeviceRegistry?
    let deviceRegistryError: String?
    lazy var session: SessionCoordinator = {
        SessionCoordinator(
            settings: settings,
            diagnostics: diagnostics,
            display: display,
            cast: cast,
            entitlements: entitlements,
            fabric: fabric
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
    private(set) var workspaceSyncRuntime: WorkspaceSyncRuntime?
    private var workspaceBootstrapKey: SymmetricKey?
    private var pendingKeyGrants: [String: Data] = [:]
    private var bootstrapped = false
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    private static let externalSSHFixtureKey = "airdesk.debug.externalSSHFixture"
    private var remoteSSHTestServer: RemoteSSHTestServer?
    #endif

    private init() {
        let store = DeviceIdentityStore()
        var loadedIdentity: DeviceIdentity?
        var identityLoadError: String?
        do {
            loadedIdentity = try store.loadOrCreate()
        } catch {
            identityLoadError = error.localizedDescription
        }

        var registry: DeviceRegistry?
        var registryLoadError: String?
        do {
            registry = try DeviceRegistry.applicationSupport()
        } catch {
            registryLoadError = error.localizedDescription
        }

        deviceIdentityStore = store
        identity = loadedIdentity
        identityError = identityLoadError
        deviceRegistry = registry
        deviceRegistryError = registryLoadError
        capabilityCatalog = CapabilityCatalog(
            providerDeviceId: loadedIdentity?.deviceId ?? ""
        )

        settings = AppSettings()
        diagnostics = PerformanceMetrics()
        display = DisplayCoordinator()
        cast = CastSessionCoordinator()
        entitlements = EntitlementManager()
        haptics = Haptics.shared
        fabric = IrohFabricPeer()
        browserEndpoint = BrowserEndpointService()
    }

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        browserEndpoint.surfaceImageProvider = { [weak self] in
            guard let self,
                  let snapshot = await self.session.desktopSurface.captureBrowserSnapshot() else {
                return nil
            }
            return BrowserEndpointSurfaceImage(
                jpegData: snapshot.jpegData,
                width: snapshot.width,
                height: snapshot.height
            )
        }

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

        fabric.onInputEvent = { [weak self] event in
            self?.session.fabricDidReceive(event)
        }
        fabric.onMovementFrame = { [weak self] frame in
            self?.session.fabricDidReceive(frame)
        }
        fabric.onPeerConnected = { [weak self] remoteEndpointID in
            self?.session.fabricPeerDidConnect(remoteEndpointID)
            self?.workspaceSyncRuntime?.peerDidConnect()
            self?.sendPendingWorkspaceKeyGrant(to: remoteEndpointID)
            self?.sendPendingWorkspaceKeyRotation(to: remoteEndpointID)
        }
        fabric.onPeerDisconnected = { [weak self] remoteEndpointID in
            self?.session.fabricPeerDidDisconnect(remoteEndpointID)
        }
        fabric.$paths
            .receive(on: RunLoop.main)
            .sink { [weak self] paths in
                Task { @MainActor in
                    self?.session.fabricPathsDidChange(paths)
                }
            }
            .store(in: &cancellables)
        fabric.onSyncEnvelope = { [weak self] data in
            guard let self else { return }
            if (try? WorkspaceSyncKeyRotationCrypto.decode(data)) != nil {
                self.handleWorkspaceKeyRotation(data)
            } else if (try? WorkspaceSyncKeyGrantCrypto.decode(data)) != nil {
                self.handleWorkspaceKeyGrant(data)
            } else {
                self.workspaceSyncRuntime?.handleEnvelope(data)
            }
        }

        settings.$fabricEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                Task { @MainActor in
                    guard let self else { return }
                    if enabled {
                        await self.fabric.start(relayPolicy: self.settings.fabricRelayPolicy)
                    } else {
                        await self.fabric.stop()
                    }
                    self.session.fabricSettingsDidChange()
                }
            }
            .store(in: &cancellables)

        settings.$fabricInputForwardingEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.session.fabricSettingsDidChange()
            }
            .store(in: &cancellables)

        settings.$browserEndpointEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyBrowserEndpointSettings()
                }
            }
            .store(in: &cancellables)

        fabric.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.session.fabricSettingsDidChange()
            }
            .store(in: &cancellables)

        session.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self, phase == .ready,
                      let remoteEndpointID = self.fabric.remoteEndpointID else { return }
                self.session.fabricPeerDidConnect(remoteEndpointID)
            }
            .store(in: &cancellables)

        if settings.fabricEnabled {
            Task { @MainActor in
                await fabric.start(relayPolicy: settings.fabricRelayPolicy)
                session.fabricSettingsDidChange()
            }
        }

        entitlements.start()
        Haptics.shared.prepare()
        diagnostics.mark("app.launch")
        bootstrapWorkspace()

        if settings.browserEndpointEnabled {
            applyBrowserEndpointSettings()
        }

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

    func applyBrowserEndpointSettings() {
        guard settings.browserEndpointEnabled else {
            browserEndpoint.stop()
            return
        }

        do {
            let directory = try DesktopSurface.bundledDirectory()
            let baseURL = try LocalAssetServer.shared.start(rootDirectory: directory)
            try browserEndpoint.start(
                allowedOrigin: baseURL.absoluteString,
                presentationBaseURL: baseURL,
                workspaceId: workspaceRestoreReport?.workspaceId ?? "workspace.local"
            )
        } catch {
            browserEndpoint.markFailed(error)
        }
    }

    func applyFabricSettings() async {
        let policy = settings.fabricRelayPolicy
        if settings.fabricEnabled {
            if fabric.state == .stopped || fabric.state == .failed {
                await fabric.start(relayPolicy: policy)
            } else if fabric.relayPolicyLabel != policy.diagnosticsLabel {
                await fabric.stop()
                await fabric.start(relayPolicy: policy)
            }
        } else {
            await fabric.stop()
        }
        session.fabricSettingsDidChange()
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
            configureWorkspaceSyncIfAvailable(bootstrapper: bootstrapper, report: report)
        } catch {
            workspaceRestoreError = error.localizedDescription
        }
    }

    func activateWorkspaceSync(key: SymmetricKey) throws {
        guard let workspaceBootstrapper,
              let report = workspaceRestoreReport else {
            throw WorkspaceSyncControllerError.workspaceMissing
        }
        let keyStore = KeychainWorkspaceSyncKeyStore()
        try keyStore.saveKey(key, workspaceId: report.workspaceId)
        let state = try keyStore.loadState(workspaceId: report.workspaceId)
        try keyStore.saveState(state, workspaceId: report.workspaceId)
        try installWorkspaceSync(
            key: key,
            bootstrapper: workspaceBootstrapper,
            report: report
        )
    }

    @discardableResult
    func revokePairedDevice(deviceId: String) throws -> PairedPeerRecord {
        guard let deviceRegistry else {
            throw DeviceRegistryError.peerNotFound(deviceId)
        }
        let record = try deviceRegistry.revoke(
            deviceId: deviceId,
            reason: "Revoked from Settings"
        )
        try workspaceSyncRuntime?.revokeSender(deviceId)
        try rotateWorkspaceSyncKey(revoking: deviceId)
        return record
    }

    func activateWorkspaceSync(
        pairingKeys: PairingKeySchedule.Keys,
        hostDeviceId: String
    ) throws {
        guard let report = workspaceRestoreReport else {
            throw WorkspaceSyncControllerError.workspaceMissing
        }
        let key = try WorkspaceSyncCrypto.derivePairingKey(
            secret: pairingKeys.transport.bytes
        )
        workspaceBootstrapKey = key
        try activateWorkspaceSync(key: key)
        try workspaceSyncRuntime?.setRotationIssuerDeviceId(hostDeviceId)
    }

    func activateWorkspaceSyncForHost(
        pairingKeys: PairingKeySchedule.Keys,
        remoteEndpointID: String
    ) throws {
        guard let workspaceBootstrapper,
              let report = workspaceRestoreReport else {
            throw WorkspaceSyncControllerError.workspaceMissing
        }
        let bootstrapKey = try WorkspaceSyncCrypto.derivePairingKey(
            secret: pairingKeys.transport.bytes
        )
        let keyStore = KeychainWorkspaceSyncKeyStore()
        let storedKey = try keyStore.loadKey(workspaceId: report.workspaceId)
        if let storedKey {
            if workspaceSyncRuntime == nil {
                try installWorkspaceSync(
                    key: storedKey,
                    bootstrapper: workspaceBootstrapper,
                    report: report
                )
            }
        } else {
            try keyStore.saveKey(bootstrapKey, workspaceId: report.workspaceId)
            let state = try keyStore.loadState(workspaceId: report.workspaceId)
            try keyStore.saveState(state, workspaceId: report.workspaceId)
            try installWorkspaceSync(
                key: bootstrapKey,
                bootstrapper: workspaceBootstrapper,
                report: report
            )
        }
        guard let runtime = workspaceSyncRuntime else {
            throw WorkspaceSyncControllerError.workspaceMissing
        }
        try runtime.setRotationIssuerDeviceId(nil)
        let grant = try WorkspaceSyncKeyGrantCrypto.grant(
            currentKey: runtime.currentKey,
            bootstrapKey: bootstrapKey,
            workspaceId: report.workspaceId,
            issuerDeviceId: workspaceBootstrapper.host.deviceId,
            generation: runtime.keyGeneration
        )
        let data = try JSONEncoder().encode(grant)
        if fabric.sendSync(data, to: remoteEndpointID) {
            try? runtime.markRotationSent(for: remoteEndpointID)
        } else {
            pendingKeyGrants[remoteEndpointID] = data
        }
    }

    private func configureWorkspaceSyncIfAvailable(
        bootstrapper: WorkspaceBootstrapper,
        report: WorkspaceRestoreReport
    ) {
        let keyStore = KeychainWorkspaceSyncKeyStore()
        guard let key = try? keyStore.loadKey(workspaceId: report.workspaceId) else {
            return
        }
        try? installWorkspaceSync(key: key, bootstrapper: bootstrapper, report: report)
    }

    private func installWorkspaceSync(
        key: SymmetricKey,
        bootstrapper: WorkspaceBootstrapper,
        report: WorkspaceRestoreReport
    ) throws {
        let runtime = try WorkspaceSyncRuntime(
            key: key,
            workspaceId: report.workspaceId,
            senderDeviceId: bootstrapper.host.deviceId,
            hostEpoch: bootstrapper.host.hostEpoch ?? 1,
            host: bootstrapper.host,
            fabric: fabric,
            stateURL: bootstrapper.store.syncStateURL,
            keyStore: KeychainWorkspaceSyncKeyStore(),
            backend: settings.coreSelection(for: .sync).active
        )
        workspaceSyncRuntime = runtime
        try runtime.publishLocalSnapshot()
        runtime.peerDidConnect()
    }

    private func rotateWorkspaceSyncKey(revoking deviceId: String) throws {
        guard let runtime = workspaceSyncRuntime, let deviceRegistry else { return }
        let endpoints = deviceRegistry.peers
            .filter { $0.trustState == .trusted && $0.deviceId != deviceId }
            .compactMap(\.endpointId)
        _ = try runtime.rotateKey(for: endpoints)
        try runtime.publishLocalSnapshot()
        for endpointId in endpoints {
            sendPendingWorkspaceKeyRotation(to: endpointId)
        }
    }

    private func sendPendingWorkspaceKeyGrant(to endpointId: String) {
        guard let data = pendingKeyGrants[endpointId] else { return }
        if fabric.sendSync(data, to: endpointId) {
            pendingKeyGrants.removeValue(forKey: endpointId)
            try? workspaceSyncRuntime?.markRotationSent(for: endpointId)
        }
    }

    private func handleWorkspaceKeyGrant(_ data: Data) {
        guard let runtime = workspaceSyncRuntime,
              let bootstrapKey = workspaceBootstrapKey,
              let issuerDeviceId = runtime.rotationIssuerDeviceId,
              let deviceRegistry,
              let message = try? WorkspaceSyncKeyGrantCrypto.decode(data),
              message.issuerDeviceId == issuerDeviceId,
              deviceRegistry.isTrusted(deviceId: issuerDeviceId) else {
            return
        }
        do {
            if try runtime.acceptKeyGrant(
                message,
                bootstrapKey: bootstrapKey,
                expectedIssuerDeviceId: issuerDeviceId
            ) {
                try runtime.publishLocalSnapshot()
            }
        } catch {
            // A stale or unauthenticated grant must not disturb the active key.
        }
    }

    private func sendPendingWorkspaceKeyRotation(to endpointId: String) {
        guard let runtime = workspaceSyncRuntime,
              let deviceRegistry,
              deviceRegistry.peers.contains(where: {
                  $0.endpointId == endpointId && $0.trustState == .trusted
              }),
              let data = runtime.pendingRotation(for: endpointId) else {
            return
        }
        if fabric.sendSync(data, to: endpointId) {
            try? runtime.markRotationSent(for: endpointId)
        }
    }

    private func handleWorkspaceKeyRotation(_ data: Data) {
        guard let runtime = workspaceSyncRuntime,
              let issuerDeviceId = runtime.rotationIssuerDeviceId,
              let deviceRegistry,
              let message = try? WorkspaceSyncKeyRotationCrypto.decode(data),
              message.issuerDeviceId == issuerDeviceId,
              deviceRegistry.isTrusted(deviceId: issuerDeviceId) else {
            return
        }
        do {
            if try runtime.acceptRotation(
                message,
                expectedIssuerDeviceId: issuerDeviceId
            ) {
                try runtime.publishLocalSnapshot()
            }
        } catch {
            // A stale or unauthenticated rotation must not disturb the active key.
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
