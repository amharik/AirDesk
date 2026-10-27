import SwiftUI

struct SessionRecoveryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator

    var body: some View {
        ZStack {
            AirDeskBackground(intensity: 0.7)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    detailCard
                    actions
                }
                .padding(.horizontal, 22)
                .padding(.top, 30)
                .padding(.bottom, 34)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(ADTheme.danger.opacity(0.10))
                    .frame(width: 86, height: 86)
                Circle()
                    .strokeBorder(ADTheme.danger.opacity(0.24), lineWidth: 1)
                    .frame(width: 86, height: 86)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(ADTheme.danger)
            }

            Text(title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(ADTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            if let device = session.selectedDevice {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 40, height: 40)
                        Image(systemName: device.iconName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ADTheme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Text("\(session.effectiveMode.title) · \(session.runtimeName)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(ADTheme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    CapsuleBadge(text: session.runtimeState.title, tint: ADTheme.danger)
                }
                .padding(13)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(spacing: 9) {
                detailRow("Stage", session.stage.title)
                detailRow("Session", session.sessionId.isEmpty ? "Inactive" : session.sessionId)
                detailRow("Recovery", recoveryDetail)
            }
            .padding(13)
        }
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                session.retry()
            } label: {
                Label("Retry session", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                session.disconnect()
            } label: {
                Label("Change display", systemImage: "display")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                environment.isDiagnosticsPresented = true
            } label: {
                Label("Open diagnostics", systemImage: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ADTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private var title: String {
        session.recoveryAttempts > 0 ? "Desktop could not be restored" : "Couldn't start the session"
    }

    private var message: String {
        if let error = session.lastError, !error.isEmpty {
            return error
        }
        return "The desktop did not report readiness. Retry the session or choose another display."
    }

    private var recoveryDetail: String {
        guard session.recoveryAttempts > 0 else { return "Not started" }
        return "\(session.recoveryAttempts) of \(session.recoveryMaximumAttempts) attempts"
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ADTheme.textTertiary)
                .lineLimit(1)
        }
    }
}
