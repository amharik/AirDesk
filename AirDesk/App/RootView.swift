import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var entitlements: EntitlementManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch session.phase {
            case .connecting:
                ConnectingView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            case .ready:
                if session.effectiveMode == .mirrored {
                    MirroredDesktopView()
                        .transition(.opacity)
                } else {
                    ControllerView()
                        .transition(.opacity)
                }
            case .failed:
                if session.selectedDevice != nil {
                    SessionRecoveryView()
                        .transition(.opacity)
                } else {
                    OnboardingView(startAtConnection: true)
                        .transition(.opacity)
                }
            case .idle:
                OnboardingView()
                    .transition(.opacity)
            }

            if session.phase != .ready || session.effectiveMode != .mirrored {
                DesktopSurfaceAnchor(surface: session.desktopSurface)
                    .frame(width: 2, height: 2)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: session.phase)
        .sheet(isPresented: $environment.isSettingsPresented) {
            SettingsView()
                .environmentObject(environment)
                .environmentObject(settings)
                .environmentObject(session)
                .environmentObject(entitlements)
        }
        .sheet(isPresented: $environment.isProPresented) {
            ProAccessView()
                .environmentObject(entitlements)
        }
        .sheet(isPresented: $environment.isDiagnosticsPresented) {
            DiagnosticsView()
                .environmentObject(environment)
                .environmentObject(session)
                .environmentObject(environment.diagnostics)
        }
        .sheet(isPresented: $session.isPreviewPresented, onDismiss: {
            session.closePreview()
        }) {
            DesktopPreviewSheet()
                .environmentObject(environment)
                .environmentObject(session)
                .environmentObject(settings)
        }
        .onChange(of: settings.desktopAppearance) { _, _ in
            session.settingsDidChange()
        }
        .preferredColorScheme(.dark)
    }
}

struct OnboardingView: View {
    let startAtConnection: Bool

    @State private var showConnection: Bool

    init(startAtConnection: Bool = false) {
        self.startAtConnection = startAtConnection
        _showConnection = State(initialValue: startAtConnection)
    }

    var body: some View {
        NavigationStack {
            WelcomeView(showConnection: $showConnection)
                .navigationDestination(isPresented: $showConnection) {
                    ConnectionView()
                }
        }
        .tint(ADTheme.accent)
    }
}
