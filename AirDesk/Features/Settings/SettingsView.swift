import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                sessionSection
                cursorSection
                runtimeSection
                castSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AirDeskBackground(intensity: 0.45))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ADTheme.accent)
                }
            }
            .onChange(of: settings.desktopAppearance) { _, _ in
                session.settingsDidChange()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sessionSection: some View {
        Section {
            settingsRow(icon: "display", title: "Display", value: session.selectedDevice?.name ?? "Not connected")
            settingsRow(icon: "rectangle.on.rectangle", title: "Mode", value: session.effectiveMode.title)
            settingsRow(icon: "cpu", title: "Runtime", value: "\(session.runtimeName) · \(session.runtimeState.title)")
            if session.isDemoConnection {
                settingsRow(icon: "testtube.2", title: "This session", value: "Demo / local preview")
            }

            if session.phase == .ready {
                Button {
                    session.openPreview()
                    dismiss()
                } label: {
                    settingAction(icon: "rectangle.inset.filled.and.person.filled", title: "Preview desktop", tint: ADTheme.accent)
                }
                .disabled(!session.canShowPreview)

                Button(role: .destructive) {
                    session.disconnect()
                    dismiss()
                } label: {
                    settingAction(icon: "xmark.circle", title: "Disconnect session", tint: ADTheme.danger)
                }
            }
        } header: {
            sectionHeader("Session")
        } footer: {
            Text("Display and runtime states are reported explicitly. AirDesk never claims readiness before the Wanix runtime confirms it.")
        }
        .listRowBackground(rowBackground)
    }

    private var cursorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Pointer speed", systemImage: "cursorarrow.motionlines")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%.2f×", settings.pointerSensitivity))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ADTheme.accent)
                }
                Slider(value: $settings.pointerSensitivity, in: 0.25...2.0)
                    .tint(ADTheme.accent)
                    .accessibilityLabel("Pointer sensitivity")
                Text("Relative movement. A swipe across the touchpad scales the pointer by this multiplier.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ADTheme.textTertiary)
            }
            .padding(.vertical, 4)

            Toggle(isOn: $settings.pointerAcceleration) {
                settingLabel(icon: "speedometer", title: "Pointer acceleration")
            }
            .tint(ADTheme.accent)

            Toggle(isOn: $settings.naturalScrolling) {
                settingLabel(icon: "arrow.up.and.down", title: "Natural scrolling")
            }
            .tint(ADTheme.accent)

            Toggle(isOn: $settings.hapticsEnabled) {
                settingLabel(icon: "iphone.radiowaves.left.and.right", title: "Haptic feedback")
            }
            .tint(ADTheme.accent)

            Toggle(isOn: $settings.showInteractionHints) {
                settingLabel(icon: "hand.tap", title: "Touchpad hints")
            }
            .tint(ADTheme.accent)
        } header: {
            sectionHeader("Air Cursor")
        } footer: {
            Text("One finger moves. Tap clicks. Double-tap double-clicks. Long press then move drags. Two-finger drag scrolls. Two-finger tap right-clicks.")
        }
        .listRowBackground(rowBackground)
    }

    private var runtimeSection: some View {
        Section {
            ForEach(settings.availableRuntimes) { runtime in
                Button {
                    settings.runtimeChoice = runtime
                    if settings.hapticsEnabled { Haptics.shared.tap() }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(ADTheme.accent.opacity(settings.runtimeChoice == runtime ? 0.2 : 0.08))
                                .frame(width: 34, height: 34)
                            Image(systemName: runtime == .wanixKernel ? "terminal.fill" : "macwindow")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(settings.runtimeChoice == runtime ? ADTheme.accent : ADTheme.textTertiary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(runtime.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text(runtime.badge)
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(ADTheme.textTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background { Capsule().fill(Color.white.opacity(0.06)) }
                            }
                            Text(runtime.subtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(ADTheme.textTertiary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: settings.runtimeChoice == runtime ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(settings.runtimeChoice == runtime ? ADTheme.accent : Color.white.opacity(0.18))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Picker("Desktop appearance", selection: $settings.desktopAppearance) {
                Text("Dark").tag("dark")
                Text("Light").tag("light")
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ADTheme.textTertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Capabilities")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.65))
                    FlowChips(items: session.capabilities.labels)
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Runtime")
        } footer: {
            Text("Runtime changes apply to the next session. Wanix Kernel loads wanix.wasm from the CDN and requires a network connection.")
        }
        .listRowBackground(rowBackground)
    }

    private var castSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ADTheme.violet.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "airplayvideo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ADTheme.violet)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.cast.isDemo ? "Simulated receiver" : "Registered receiver")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(CastConfiguration.hasRegisteredReceiver ? "Receiver application ID configured." : "Google Cast SDK / receiver not configured in this build.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ADTheme.textTertiary)
                }
                Spacer()
                CapsuleBadge(text: environment.cast.isDemo ? "Demo" : "Live", tint: environment.cast.isDemo ? ADTheme.amber : ADTheme.accent)
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Google Cast")
        } footer: {
            Text("The demo receiver exercises the shared controller and input schema on-device. Shipping Cast support requires the official Google Cast iOS Sender SDK and a hosted AirDesk Custom Web Receiver.")
        }
        .listRowBackground(rowBackground)
    }

    private var aboutSection: some View {
        Section {
            settingsRow(icon: "app.badge", title: "AirDesk", value: appVersion)
            settingsRow(icon: "cpu", title: "Runtime", value: session.runtimeName)
            settingsRow(icon: "point.3.connected.trianglepath.dotted", title: "Input protocol", value: "v1 · normalized pointer")
            settingsRow(icon: "lock.shield", title: "Security", value: "Validated bridge · HTTPS runtime")

            Button {
                settings.reset()
            } label: {
                settingAction(icon: "arrow.counterclockwise", title: "Reset controller settings", tint: ADTheme.amber)
            }
        } header: {
            sectionHeader("About")
        } footer: {
            Text("AirDesk runs the Wanix workspace inside a browser sandbox. Keyboard and pointer events are sent to the active desktop surface; they are not logged or stored by AirDesk.")
        }
        .listRowBackground(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.045))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(ADTheme.textTertiary)
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ADTheme.textSecondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.86))
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ADTheme.textTertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func settingLabel(icon: String, title: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.86))
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(ADTheme.textSecondary)
        }
    }

    private func settingAction(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct FlowChips: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ADTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
            }
        }
    }
}
