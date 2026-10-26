import Foundation

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

        display.onExternalDisplayConnected = { [weak self] container in
            self?.session.externalDisplayDidConnect(container)
        }
        display.onExternalDisplayDisconnected = { [weak self] in
            self?.session.externalDisplayDidDisconnect()
        }

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
        #endif
    }
}
