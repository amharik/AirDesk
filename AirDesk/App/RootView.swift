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

            VStack {
                if let status = environment.workspaceStatusPresentation {
                    WorkspaceStatusBanner(presentation: status)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                Spacer()
            }
            .allowsHitTesting(false)
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
        .modifier(PreviewPresenter())
        .onChange(of: settings.desktopAppearance) { _, _ in
            session.settingsDidChange()
        }
        .preferredColorScheme(.dark)
    }
}

private struct PreviewPresenter: ViewModifier {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    @ViewBuilder
    func body(content: Content) -> some View {
        if DeviceContext.isPad {
            content.fullScreenCover(isPresented: $session.isPreviewPresented, onDismiss: {
                session.closePreview()
            }) {
                preview
            }
        } else {
            content.sheet(isPresented: $session.isPreviewPresented, onDismiss: {
                session.closePreview()
            }) {
                preview
            }
        }
    }

    private var preview: some View {
        DesktopPreviewSheet()
            .environmentObject(environment)
            .environmentObject(session)
            .environmentObject(settings)
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

private struct WorkspaceStatusBanner: View {
    let presentation: WorkspaceStatusPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(presentation.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ADTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 0.8)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch presentation.severity {
        case .info: return ADTheme.accent
        case .warning: return ADTheme.amber
        case .error: return .red
        }
    }

    private var icon: String {
        switch presentation.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
