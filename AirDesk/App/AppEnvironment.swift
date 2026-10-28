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

    private var bootstrapped = false
    private var cancellables = Set<AnyCancellable>()

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

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-AirDeskAutoDemo") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard session.phase == .idle else { return }
                session.beginConnection(to: .previewDevice)
            }
        }
        NativeSmokeTest.runIfRequested(session: session)
        #endif
    }

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
