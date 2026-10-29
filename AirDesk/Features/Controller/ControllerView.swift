import SwiftUI
import UIKit

struct ControllerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    @State private var showDeck = true
    @State private var showDisconnectConfirm = false
    @StateObject private var physicalInput = PhysicalInputRouter()

    var body: some View {
        ZStack {
            AirDeskBackground(intensity: 0.55)

            HardwareKeyboardCapture(
                isActive: !session.isPreviewPresented,
                onText: { session.sendText($0) },
                onKey: { key, code, modifiers in
                    session.sendKey(key, code: code, eventModifiers: modifiers)
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                statusBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                if let notice = session.notice {
                    noticeBanner(notice)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if session.runtimeState == .recovering {
                    recoveryBanner
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                if physicalInput.hasPeripherals {
                    physicalInputStatus
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                if shouldShowDeck {
                    MacInputDeck(
                        activeModifiers: session.modifiers,
                        onCursor: { action, viewport in
                            session.handleCursor(action, viewport: viewport)
                        },
                        onKey: { key, code, modifiers in
                            session.sendKey(key, code: code, eventModifiers: modifiers)
                        },
                        onText: { text, modifiers in
                            session.sendText(text, eventModifiers: modifiers)
                        },
                        onModifier: { session.toggleModifier($0) },
                        onClearModifiers: { session.clearModifiers() }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    inputPlaceholder
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                }

                bottomToolbar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }

            if isUITestProbe {
                Text(session.debugJSLog)
                    .font(.system(size: 6, design: .monospaced))
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .accessibilityIdentifier("JSLogProbe")
            }
        }
        .animation(.easeInOut(duration: 0.22), value: shouldShowDeck)
        .animation(.easeInOut(duration: 0.2), value: session.notice)
        .animation(.easeInOut(duration: 0.2), value: session.runtimeState)
        .confirmationDialog("End this desktop session?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                session.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The display will return to its home screen. Your Wanix workspace stays available for the next session.")
        }
        .onAppear {
            Haptics.shared.prepare()
            configurePhysicalInput()
            physicalInput.start()
            syncInputRouting()
            session.setPreviewKeyboardRouting(false)
        }
        .onDisappear {
            physicalInput.stop()
            session.setNativeInputCaptured(false)
            session.setPreviewKeyboardRouting(false)
        }
        .onChange(of: environment.display.externalDisplaySize) { _, _ in
            updatePhysicalViewport()
        }
        .onChange(of: physicalInput.hasPeripherals) { _, _ in
            syncInputRouting()
        }
        .onChange(of: physicalInput.isCaptured) { _, _ in
            syncInputRouting()
        }
        .onChange(of: session.isPreviewPresented) { _, presented in
            if presented {
                session.setPreviewKeyboardRouting(true)
            } else {
                session.setPreviewKeyboardRouting(false)
                syncInputRouting()
            }
        }
    }

    private var isUITestProbe: Bool {
        ProcessInfo.processInfo.arguments.contains("-AirDeskUITestProbe")
    }

    private var shouldShowDeck: Bool {
        showDeck && !physicalInput.isRouting
    }

    private var monitorViewport: CGSize {
        let external = environment.display.externalDisplaySize
        if external.width > 0, external.height > 0 {
            return external
        }
        let screen = UIScreen.main.bounds.size
        return screen.width > 0 && screen.height > 0 ? screen : CGSize(width: 1024, height: 768)
    }

    private func configurePhysicalInput() {
        updatePhysicalViewport()
        physicalInput.keyboardRoutingEnabled = false
        physicalInput.onCursor = { action, viewport in
            session.handleCursor(action, viewport: viewport)
        }
        physicalInput.onText = { text, modifiers in
            session.sendText(text, eventModifiers: modifiers)
        }
        physicalInput.onKey = { key, code, modifiers in
            session.sendKey(key, code: code, eventModifiers: modifiers)
        }
        physicalInput.onRoutingChanged = { routing in
            session.setNativeInputCaptured(routing)
        }
    }

    private func updatePhysicalViewport() {
        physicalInput.viewport = monitorViewport
    }

    private func syncInputRouting() {
        updatePhysicalViewport()
        session.setNativeInputCaptured(physicalInput.isRouting)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    StatusDot(color: statusColor, pulsing: session.runtimeState == .recovering || session.runtimeState == .preparing)
                    Text(session.selectedDevice?.name ?? "Wanix Desktop")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if session.isDemoConnection {
                        CapsuleBadge(text: "Demo", tint: ADTheme.amber)
                    }
                }
                Text("\(session.effectiveMode.title) · \(session.runtimeName) · \(session.runtimeState.title)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if environment.diagnostics.lastLatency > 0 {
                Text("\(Int(environment.diagnostics.lastLatency)) ms")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ADTheme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.white.opacity(0.045))
                    }
                    .accessibilityLabel("Last input acknowledgement \(Int(environment.diagnostics.lastLatency)) milliseconds")
            }

            Menu {
                Button {
                    session.openPreview()
                } label: {
                    Label("Preview Desktop", systemImage: "rectangle.inset.filled.and.person.filled")
                }
                .disabled(!session.canShowPreview)

                Button {
                    environment.isSettingsPresented = true
                } label: {
                    Label("Session Settings", systemImage: "slider.horizontal.3")
                }

                Button {
                    environment.isDiagnosticsPresented = true
                } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }

                Divider()

                Button(role: .destructive) {
                    showDisconnectConfirm = true
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7) }
                    }
            }
            .accessibilityLabel("Session menu")
        }
    }

    private var statusColor: Color {
        if session.isDemoConnection { return ADTheme.amber }
        switch session.runtimeState {
        case .ready: return ADTheme.accent
        case .preparing, .loading, .recovering: return ADTheme.amber
        case .failed: return ADTheme.danger
        default: return ADTheme.textTertiary
        }
    }

    private var physicalInputStatus: some View {
        Button {
            if settings.hapticsEnabled { Haptics.shared.tap() }
            physicalInput.setCaptured(!physicalInput.isCaptured)
        } label: {
            HStack(spacing: 9) {
                HStack(spacing: 5) {
                    if physicalInput.keyboardAvailable {
                        Image(systemName: "keyboard.fill")
                    }
                    if physicalInput.mouseAvailable {
                        Image(systemName: "computermouse.fill")
                    }
                }
                .font(.system(size: 11, weight: .semibold))

                Text(physicalStatusText)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.5)

                Image(systemName: physicalInput.isCaptured ? "hand.tap.fill" : "hand.tap")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(physicalInput.isCaptured ? ADTheme.accent : ADTheme.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(physicalInput.isCaptured ? ADTheme.accent.opacity(0.12) : Color.white.opacity(0.045))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                physicalInput.isCaptured ? ADTheme.accent.opacity(0.30) : Color.white.opacity(0.08),
                                lineWidth: 0.7
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(physicalInput.isCaptured ? "Physical input captured. Tap to release." : "Physical input released. Tap to capture.")
    }

    private var physicalStatusText: String {
        let devices: String
        if physicalInput.keyboardAvailable && physicalInput.mouseAvailable {
            devices = "MOUSE + KEYBOARD"
        } else if physicalInput.mouseAvailable {
            devices = "MOUSE"
        } else {
            devices = "KEYBOARD"
        }
        return physicalInput.isCaptured
            ? "\(devices) CAPTURED · TAP TO RELEASE"
            : "\(devices) RELEASED · TAP TO CAPTURE"
    }

    private var inputPlaceholder: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: physicalInput.isRouting ? "computermouse.fill" : "keyboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(physicalInput.isRouting ? ADTheme.accent : ADTheme.textTertiary)

            Text(physicalInput.isRouting ? "Physical input is controlling the desktop" : "Input deck hidden")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            Text(physicalInput.isRouting
                 ? "Move the pointer with the mouse and type on the keyboard. Tap the status capsule above to release input and return to the on-screen deck."
                 : "Bring back the MacBook-style keyboard and trackpad deck.")
                .font(.system(size: 12.5))
                .foregroundStyle(ADTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .lineSpacing(2)

            if !physicalInput.isRouting {
                Button {
                    showDeck = true
                    if settings.hapticsEnabled { Haptics.shared.tap() }
                } label: {
                    Label("Show input deck", systemImage: "keyboard")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x04131A))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background { Capsule().fill(ADTheme.accentGradient()) }
                }
                .buttonStyle(ToolbarPressStyle())
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                }
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                clickHalf(title: "Left", icon: "cursorarrow.click", tint: ADTheme.accent) {
                    session.handleCursor(.click(count: 1), viewport: monitorViewport)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 0.8, height: 30)
                clickHalf(title: "Right", icon: "cursorarrow.click.2", tint: ADTheme.accent) {
                    session.handleCursor(.rightClick, viewport: monitorViewport)
                }
            }
            .frame(height: 60)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.7)
                    }
            }

            toolButton(icon: "keyboard", title: "Input", active: shouldShowDeck) {
                if physicalInput.isRouting {
                    physicalInput.setCaptured(false)
                    showDeck = true
                } else {
                    showDeck.toggle()
                }
                if settings.hapticsEnabled { Haptics.shared.tap() }
            }
            toolButton(icon: "escape", title: "Esc") {
                session.sendKey("Escape", code: "Escape")
            }
            toolButton(icon: "house", title: "Dock") {
                session.dockAction()
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func clickHalf(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.white.opacity(0.86))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarPressStyle())
        .accessibilityLabel("\(title) click")
    }

    private func toolButton(icon: String, title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? Color(hex: 0x04131A) : Color.white.opacity(0.78))
            .frame(width: 56, height: 60)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(active ? AnyShapeStyle(ADTheme.accentGradient()) : AnyShapeStyle(Color.white.opacity(0.055)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(active ? 0.22 : 0.11), lineWidth: 0.7)
                    }
            }
        }
        .buttonStyle(ToolbarPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func noticeBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ADTheme.accent)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                session.dismissNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ADTheme.textTertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background {
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.7))
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7) }
        }
    }

    private var recoveryBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.mini)
                .tint(ADTheme.amber)
            Text(session.recoveryAttempts > 0
                ? "Restoring the desktop process… Attempt \(session.recoveryAttempts) of \(session.recoveryMaximumAttempts)"
                : "Restoring the desktop process…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ADTheme.amber)
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(ADTheme.amber.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(ADTheme.amber.opacity(0.18), lineWidth: 0.7)
                }
        }
    }
}

struct ToolbarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
