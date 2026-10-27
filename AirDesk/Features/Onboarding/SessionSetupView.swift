import SwiftUI

struct SessionSetupView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var entitlements: EntitlementManager
    @Environment(\.dismiss) private var dismiss

    let device: DisplayDevice

    private var selectedRuntimeLocked: Bool {
        settings.runtimeChoice.requiresPro && !entitlements.canUse(settings.runtimeChoice)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AirDeskBackground(intensity: 0.65)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        deviceCard
                        runtimeSection
                        sessionSection
                        startSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Session Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ADTheme.textSecondary)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .task {
            await entitlements.refresh()
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ready to connect?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Review the runtime and display route before AirDesk starts the session.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(ADTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                AirDeskMark(size: 38)
            }
        }
        .padding(.top, 4)
    }

    private var deviceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: deviceTint,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                    }
                Image(systemName: device.iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(device.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if device.isDemo {
                        CapsuleBadge(text: "Demo", tint: ADTheme.amber)
                    }
                }
                Text(device.detail)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8)
                }
        }
    }

    private var runtimeSection: some View {
        VStack(spacing: 10) {
            HStack {
                SectionLabel(text: "Runtime")
                Spacer()
                Text(settings.runtimeChoice.requiresNetwork ? "NETWORK" : "OFFLINE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(settings.runtimeChoice.requiresNetwork ? ADTheme.amber : ADTheme.accent)
            }

            VStack(spacing: 8) {
                ForEach(settings.availableRuntimes) { runtime in
                    runtimeRow(runtime)
                }
            }

            if selectedRuntimeLocked {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ADTheme.amber)
                    Text("\(settings.runtimeChoice.title) requires AirDesk Pro. Choose Wanix Desktop or unlock Pro.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ADTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Unlock") {
                        environment.isProPresented = true
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(ADTheme.amber)
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ADTheme.amber.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(ADTheme.amber.opacity(0.18), lineWidth: 0.7)
                        }
                }
            }
        }
    }

    private func runtimeRow(_ runtime: RuntimeChoice) -> some View {
        let isLocked = runtime.requiresPro && !entitlements.canUse(runtime)
        let isSelected = settings.runtimeChoice == runtime

        return Button {
            if isLocked {
                environment.isProPresented = true
                return
            }
            settings.runtimeChoice = runtime
            if settings.hapticsEnabled { Haptics.shared.tap() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(ADTheme.accent.opacity(isSelected ? 0.18 : 0.06))
                        .frame(width: 40, height: 40)
                    Image(systemName: runtime == .wanixKernel ? "terminal.fill" : "macwindow")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? ADTheme.accent : ADTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(runtime.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(runtime.badge)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(ADTheme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background { Capsule().fill(Color.white.opacity(0.06)) }
                        if runtime.requiresPro {
                            Text("PRO")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundStyle(isLocked ? ADTheme.amber : ADTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule().fill((isLocked ? ADTheme.amber : ADTheme.accent).opacity(0.10))
                                }
                        }
                    }
                    Text(runtime.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ADTheme.textTertiary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                Image(systemName: isLocked ? "lock.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 18))
                    .foregroundStyle(isLocked ? ADTheme.amber : (isSelected ? ADTheme.accent : Color.white.opacity(0.18)))
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.065 : 0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(
                                isSelected ? ADTheme.accent.opacity(0.35) : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 1 : 0.7
                            )
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(runtime.title). \(runtime.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sessionSection: some View {
        VStack(spacing: 10) {
            SectionLabel(text: "Session")
            VStack(spacing: 0) {
                setupRow("Display mode", value: device.mode.title)
                Divider().overlay(Color.white.opacity(0.06))
                setupRow("Input route", value: device.kind == .cast ? "Cast channel" : "Local bridge")
                Divider().overlay(Color.white.opacity(0.06))
                setupRow("Workspace", value: session.workspace.name)
            }
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
                    }
            }
        }
    }

    private var startSection: some View {
        VStack(spacing: 10) {
            Button(action: startSession) {
                HStack(spacing: 9) {
                    Image(systemName: selectedRuntimeLocked ? "lock.fill" : "arrow.right.circle.fill")
                    Text(selectedRuntimeLocked ? "Unlock Pro to continue" : "Start session")
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: selectedRuntimeLocked ? ADTheme.amber : ADTheme.accent))
            .disabled(session.phase == .connecting)

            Text(selectedRuntimeLocked
                 ? "Wanix Kernel is a Pro runtime. Wanix Desktop remains available for free."
                 : "AirDesk will start the runtime and hand control to the Air Cursor.")
                .font(.system(size: 11))
                .foregroundStyle(ADTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(.top, 2)
    }

    private func setupRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(ADTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.78))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }

    private var deviceTint: [Color] {
        switch device.kind {
        case .airPlay: return [Color(hex: 0x4A9EFF), Color(hex: 0x1E5FCC)]
        case .wired, .external: return [Color(hex: 0x55D6C2), Color(hex: 0x1A8F86)]
        case .cast: return [Color(hex: 0x6C7CFF), Color(hex: 0x3A3FA8)]
        case .preview: return [Color(hex: 0x8C7CFF), Color(hex: 0x5140B8)]
        }
    }

    private func startSession() {
        guard !selectedRuntimeLocked else {
            environment.isProPresented = true
            return
        }
        if settings.hapticsEnabled { Haptics.shared.tap() }
        session.beginConnection(to: device)
        dismiss()
    }
}
