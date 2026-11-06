import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var entitlements: EntitlementManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                proSection
                sessionSection
                if let workspaceLifecycle = environment.workspaceLifecycle {
                    WorkspaceApplicationsSection(store: workspaceLifecycle)
                }
                remoteTerminalSection
                displaySection
                browserEndpointSection
                cursorSection
                runtimeSection
                fabricSection
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
            .task {
                await entitlements.refresh()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var proSection: some View {
        Section {
            Button {
                environment.isProPresented = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(proTint.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: entitlements.isPro ? "checkmark.seal.fill" : "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(proTint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("AirDesk Pro")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                            CapsuleBadge(text: entitlements.status.title, tint: proTint)
                        }
                        Text(entitlements.statusDetail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(ADTheme.textTertiary)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(1.5)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ADTheme.textTertiary)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if entitlements.isPro {
                Button {
                    Task { await entitlements.showManageSubscriptions() }
                } label: {
                    settingAction(icon: "gearshape", title: "Manage subscription", tint: ADTheme.textSecondary)
                }
            } else {
                Button {
                    Task { await entitlements.restorePurchases() }
                } label: {
                    settingAction(
                        icon: "arrow.clockwise",
                        title: entitlements.isRestoring ? "Restoring purchases…" : "Restore purchases",
                        tint: ADTheme.textSecondary
                    )
                }
                .disabled(entitlements.isRestoring)
            }
        } header: {
            sectionHeader("Membership")
        } footer: {
            Text("Wanix Desktop is free forever. Pro unlocks the live Wanix Kernel and advanced display features.")
        }
        .listRowBackground(rowBackground)
    }

    private var proTint: Color {
        switch entitlements.status {
        case .loading: return ADTheme.textTertiary
        case .free: return ADTheme.violet
        case .pro: return ADTheme.accent
        case .gracePeriod: return ADTheme.amber
        }
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

    private var remoteTerminalSection: some View {
        Section {
            NavigationLink {
                RemoteTerminalSettingsView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(ADTheme.accent.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "network")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ADTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SSH remote terminal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(settings.remoteTerminalEnabled
                             ? "\(settings.remoteTerminalProfile.destination) · \(session.remoteTerminalStatus)"
                             : "Using the local Wanix shell")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ADTheme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    CapsuleBadge(
                        text: settings.remoteTerminalEnabled ? "SSH" : "Local",
                        tint: settings.remoteTerminalEnabled ? ADTheme.accent : ADTheme.textTertiary
                    )
                }
                .padding(.vertical, 2)
            }
        } header: {
            sectionHeader("Terminal transport")
        } footer: {
            Text("Attach the Terminal app to a remote PTY over pinned SSH and keep long-running work inside tmux. Credentials stay in the Keychain.")
        }
        .listRowBackground(rowBackground)
    }

    private var displaySection: some View {
        Section {
            Picker("Display output", selection: $settings.displayMode) {
                ForEach(DisplayPresentationMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: settings.displayMode.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ADTheme.textTertiary)
                    .padding(.top, 2)
                Text(settings.displayMode.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineSpacing(1.5)
            }
            .padding(.vertical, 2)

            if environment.display.isMirroring {
                Label("AirPlay mirroring active", systemImage: "airplayvideo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ADTheme.accent)
            }
        } header: {
            sectionHeader("Display output")
        } footer: {
            Text("Mirror \(DeviceContext.name) uses AirPlay Screen Mirroring from Control Center and shows the desktop with a floating remote. Extended desktop requires an external-display scene and keeps the controller on \(DeviceContext.name).")
        }
        .listRowBackground(rowBackground)
    }

    private var browserEndpointSection: some View {
        Section {
            BrowserEndpointControls(
                service: environment.browserEndpoint,
                enabled: $settings.browserEndpointEnabled
            )
        } header: {
            sectionHeader("Browser presentation")
        } footer: {
            Text("The loopback host only accepts the configured local asset origin. A production browser presentation page is not bundled yet.")
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
                let isLocked = runtime.requiresPro && !entitlements.canUse(runtime)
                let isSelected = settings.runtimeChoice == runtime && !isLocked

                Button {
                    if isLocked {
                        environment.isProPresented = true
                        return
                    }
                    settings.runtimeChoice = runtime
                    if settings.hapticsEnabled { Haptics.shared.tap() }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(ADTheme.accent.opacity(isSelected ? 0.2 : 0.08))
                                .frame(width: 34, height: 34)
                            Image(systemName: runtime == .wanixKernel ? "terminal.fill" : "macwindow")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSelected ? ADTheme.accent : ADTheme.textTertiary)
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
                        Spacer()
                        Image(systemName: isLocked ? "lock.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                            .font(.system(size: 17))
                            .foregroundStyle(isLocked ? ADTheme.amber : (isSelected ? ADTheme.accent : Color.white.opacity(0.18)))
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

    private var fabricSection: some View {
        Section {
            NavigationLink {
                FabricSettingsView(fabric: environment.fabric)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(ADTheme.accent.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ADTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Iroh fabric")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(fabricDetail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(ADTheme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    CapsuleBadge(
                        text: environment.fabric.state.title,
                        tint: environment.fabric.state == .connected ? ADTheme.accent : ADTheme.textTertiary
                    )
                }
                .padding(.vertical, 2)
            }
        } header: {
            sectionHeader("Native transport")
        } footer: {
            Text("Iroh provides the native peer data plane. WebSocket remains available for browser runtimes and as a fallback.")
        }
        .listRowBackground(rowBackground)
    }

    private var fabricDetail: String {
        guard settings.fabricEnabled else { return "Disabled" }
        if let path = environment.fabric.selectedPath {
            return path.isRelay ? "\(path.rttMs) ms · relayed" : "\(path.rttMs) ms · direct"
        }
        return environment.fabric.isConnected ? "Connected" : "Waiting for peer"
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
                    Text(CastConfiguration.hasRegisteredReceiver ? "Receiver application ID configured." : "Receiver application ID not configured; using simulated devices.")
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
            Text("The Google Cast SDK is linked. Real receivers require a registered application ID and a hosted AirDesk Custom Web Receiver; without them AirDesk uses the on-device demo receiver.")
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

private struct BrowserEndpointControls: View {
    @ObservedObject var service: BrowserEndpointService
    @Binding var enabled: Bool
    @State private var copied = false

    var body: some View {
        Toggle(isOn: $enabled) {
            Label {
                Text("Browser endpoint host")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.86))
            } icon: {
                Image(systemName: "safari")
                    .foregroundStyle(ADTheme.textSecondary)
            }
        }
        .tint(ADTheme.accent)

        if enabled || service.state != .stopped {
            HStack(spacing: 11) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ADTheme.textSecondary)
                    .frame(width: 20)
                Text("Host status")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.86))
                Spacer(minLength: 10)
                CapsuleBadge(
                    text: service.state.title,
                    tint: service.state == .running ? ADTheme.accent : ADTheme.textTertiary
                )
            }

            if let endpointURL = service.endpointURL {
                Button {
                    UIPasteboard.general.string = endpointURL.absoluteString
                    copied = true
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(copied ? "Endpoint copied" : "Copy endpoint URL")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ADTheme.accent)
                            Spacer()
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ADTheme.accent)
                        }
                        Text(endpointURL.absoluteString)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(ADTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        if let lastError = service.lastError {
            Text(lastError)
                .font(.system(size: 11.5))
                .foregroundStyle(ADTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WorkspaceApplicationsSection: View {
    @ObservedObject var store: WorkspaceLifecycleStore

    var body: some View {
        Section {
            if let error = store.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ADTheme.danger)
                        .padding(.top, 2)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ADTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }

            if store.instances.isEmpty {
                Text("No workspace applications are installed.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ADTheme.textTertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(store.instances) { instance in
                    row(instance)
                }
            }
        } header: {
            Text("WORKSPACE APPLICATIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(ADTheme.textTertiary)
        } footer: {
            Text("Observed state comes from the runtime provider. Checkpoint only succeeds when the application supports an app-cooperative checkpoint; AirDesk never snapshots a process or JavaScript heap.")
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private func row(_ instance: WorkspaceApplicationInstancePresentation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint(instance.observedState).opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon(instance.observedState))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint(instance.observedState))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(instance.applicationName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text(instance.applicationVersion)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(ADTheme.textTertiary)
                }
                Text(detail(instance))
                    .font(.system(size: 11))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineLimit(2)
                if let lastError = instance.lastError {
                    Text(lastError)
                        .font(.system(size: 10.5))
                        .foregroundStyle(ADTheme.danger)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)

            if store.busyInstanceId == instance.id {
                ProgressView()
                    .tint(ADTheme.accent)
            } else {
                Menu {
                    Button {
                        Task { await store.start(instance.id) }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(!instance.canStart)

                    Button {
                        Task { await store.suspend(instance.id) }
                    } label: {
                        Label("Suspend", systemImage: "pause.fill")
                    }
                    .disabled(!instance.canSuspend)

                    Button {
                        Task { await store.checkpoint(instance.id) }
                    } label: {
                        Label("Checkpoint", systemImage: "checkmark.seal")
                    }
                    .disabled(!instance.canCheckpoint)

                    Button {
                        Task { await store.resume(instance.id) }
                    } label: {
                        Label("Resume", systemImage: "forward.fill")
                    }
                    .disabled(!instance.canResume)

                    Button(role: .destructive) {
                        Task { await store.stop(instance.id) }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(!instance.canStop)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(ADTheme.textSecondary)
                }
                .disabled(store.busyInstanceId != nil)
            }

            CapsuleBadge(
                text: instance.observedState.title,
                tint: tint(instance.observedState)
            )
        }
        .padding(.vertical, 2)
    }

    private func detail(_ instance: WorkspaceApplicationInstancePresentation) -> String {
        var parts = ["Desired \(instance.desiredState.title)"]
        if let provider = instance.runtimeProviderId {
            parts.append(provider)
        }
        if instance.observedState == .suspendedCheckpointed {
            parts.append("Cooperative checkpoint")
        }
        return parts.joined(separator: " · ")
    }

    private func tint(_ state: WorkspaceObservedState) -> Color {
        switch state {
        case .starting: return ADTheme.amber
        case .running: return ADTheme.accent
        case .suspended, .suspendedCheckpointed: return ADTheme.violet
        case .stopped: return ADTheme.textTertiary
        case .failed, .unavailable: return ADTheme.danger
        }
    }

    private func icon(_ state: WorkspaceObservedState) -> String {
        switch state {
        case .starting: return "hourglass"
        case .running: return "play.fill"
        case .suspended: return "pause.fill"
        case .suspendedCheckpointed: return "checkmark.seal.fill"
        case .stopped: return "stop.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle.fill"
        }
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
