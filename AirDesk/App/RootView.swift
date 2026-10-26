import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch environment.session.phase {
            case .connecting:
                ConnectingView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            case .ready:
                ControllerView()
                    .transition(.opacity)
            case .failed:
                OnboardingView(startAtConnection: true)
                    .transition(.opacity)
            case .idle:
                OnboardingView()
                    .transition(.opacity)
            }

            DesktopSurfaceAnchor(surface: environment.session.desktopSurface)
                .frame(width: 2, height: 2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.28), value: environment.session.phase)
        .environmentObject(environment.session)
        .environmentObject(environment.settings)
        .environmentObject(environment.cast)
        .sheet(isPresented: $environment.isSettingsPresented) {
            SettingsView()
                .environmentObject(environment)
                .environmentObject(environment.settings)
                .environmentObject(environment.session)
        }
        .sheet(isPresented: $environment.isDiagnosticsPresented) {
            DiagnosticsView()
                .environmentObject(environment)
                .environmentObject(environment.session)
                .environmentObject(environment.diagnostics)
        }
        .sheet(isPresented: $environment.session.isPreviewPresented, onDismiss: {
            environment.session.closePreview()
        }) {
            DesktopPreviewSheet()
                .environmentObject(environment)
                .environmentObject(environment.session)
                .environmentObject(environment.settings)
        }
        .onChange(of: environment.settings.desktopAppearance) { _, _ in
            environment.session.settingsDidChange()
        }
        .preferredColorScheme(.dark)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment
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
