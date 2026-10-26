import SwiftUI

struct ConnectingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        ZStack {
            AirDeskBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 2)
                        .frame(width: 184, height: 184)
                    Circle()
                        .trim(from: 0, to: 0.32)
                        .stroke(
                            AngularGradient(
                                colors: [ADTheme.accent.opacity(0.1), ADTheme.accent, ADTheme.violet],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 184, height: 184)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .shadow(color: ADTheme.accent.opacity(0.4), radius: 16)

                    Circle()
                        .trim(from: 0, to: session.stage.progress)
                        .stroke(ADTheme.accent.opacity(0.22), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 152, height: 152)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 7) {
                        Image(systemName: session.selectedDevice?.iconName ?? "display")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(session.selectedDevice?.name ?? "Display")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(ADTheme.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: 130)
                    }
                }
                .padding(.bottom, 36)

                Text(session.connectionStage.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: session.connectionStage)

                Text(session.connectionStage.detail)
                    .font(.system(size: 15))
                    .foregroundStyle(ADTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 340)
                    .padding(.top, 8)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: session.connectionStage)

                VStack(spacing: 11) {
                    stageRow("Link", symbol: "antenna.radiowaves.left.and.right", threshold: 0.18)
                    stageRow("Session", symbol: "lock.shield", threshold: 0.38)
                    stageRow("Wanix", symbol: "cpu", threshold: 0.66)
                    stageRow("Ready", symbol: "checkmark.circle", threshold: 0.88)
                }
                .frame(maxWidth: 300)
                .padding(.top, 36)

                Spacer(minLength: 20)

                Button {
                    session.cancelConnection()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(minWidth: 120, minHeight: 46)
                        .background {
                            Capsule().fill(Color.white.opacity(0.055))
                                .overlay { Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7) }
                        }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 520)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
        .interactiveDismissDisabled()
    }

    private func stageRow(_ title: String, symbol: String, threshold: Double) -> some View {
        let complete = session.stage.progress >= threshold
        return HStack(spacing: 11) {
            Image(systemName: complete ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(complete ? ADTheme.accent : Color.white.opacity(0.22))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(complete ? Color.white.opacity(0.85) : Color.white.opacity(0.32))
            Spacer()
            if complete {
                Text("DONE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(ADTheme.accent.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(complete ? 0.045 : 0.02))
        }
    }
}
