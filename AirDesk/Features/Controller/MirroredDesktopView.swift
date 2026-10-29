import SwiftUI

struct MirroredDesktopView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    @State private var isExpanded = true
    @State private var showDeck = false
    @State private var showDisconnectConfirm = false
    @StateObject private var physicalInput = PhysicalInputRouter()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            DesktopSurfaceAnchor(surface: session.desktopSurface)
                .ignoresSafeArea()

            HardwareKeyboardCapture(
                isActive: true,
                onText: { session.sendText($0) },
                onKey: { key, code, modifiers in
                    session.sendKey(key, code: code, eventModifiers: modifiers)
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if isExpanded {
                remotePanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                collapsedButton
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: shouldShowDeck)
        .confirmationDialog("End this desktop session?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                session.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The mirrored desktop will return to its home screen. Your Wanix workspace stays available for the next session.")
        }
        .onAppear {
            configurePhysicalInput()
            physicalInput.start()
            syncInputRouting()
            session.setPreviewKeyboardRouting(false)
        }
        .onDisappear {
            physicalInput.stop()
            session.setNativeInputCaptured(false)
            session.setPreviewKeyboardRouting(true)
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
    }

    private var shouldShowDeck: Bool {
        showDeck && !physicalInput.isRouting
    }

    private var monitorViewport: CGSize {
        let external = environment.display.externalDisplaySize
        if external.width > 0, external.height > 0 {
            return external
        }
        return CGSize(width: 1024, height: 768)
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

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(ADTheme.accent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "airplayvideo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ADTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AIRPLAY MIRRORING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(ADTheme.textSecondary)
                Text(displayDetail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                if settings.hapticsEnabled { Haptics.shared.tap() }
                isExpanded = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 40, height: 40)
                    .background {
                        Circle().fill(Color.white.opacity(0.06))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse remote")
        }
    }

    private var physicalInputStatus: some View {
        Button {
            if settings.hapticsEnabled { Haptics.shared.tap() }
            physicalInput.setCaptured(!physicalInput.isCaptured)
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    if physicalInput.keyboardAvailable {
                        Image(systemName: "keyboard.fill")
                    }
                    if physicalInput.mouseAvailable {
                        Image(systemName: "computermouse.fill")
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                Text(physicalStatusText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                Spacer(minLength: 0)
                Image(systemName: physicalInput.isCaptured ? "hand.tap.fill" : "hand.tap")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(physicalInput.isCaptured ? ADTheme.accent : ADTheme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
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

    private var touchpadRow: some View {
        HStack(alignment: .top, spacing: 10) {
            MacTrackpadView(
                onAction: { action, viewport in
                    session.handleCursor(action, viewport: viewport)
                },
                showsHints: settings.showInteractionHints
            )
            .frame(height: 142)

            VStack(spacing: 8) {
                remoteButton("cursorarrow.click", "Left") {
                    session.handleCursor(.click(count: 1), viewport: monitorViewport)
                }
                remoteButton("cursorarrow.click.2", "Right") {
                    session.handleCursor(.rightClick, viewport: monitorViewport)
                }
                remoteButton("keyboard", "Type", active: shouldShowDeck) {
                    if physicalInput.isRouting {
                        physicalInput.setCaptured(false)
                        showDeck = true
                    } else {
                        showDeck.toggle()
                    }
                    if settings.hapticsEnabled { Haptics.shared.tap() }
                }
            }
            .frame(width: 64)
        }
    }

    private var remotePanel: some View {
        VStack(spacing: 10) {
            header

            if physicalInput.hasPeripherals {
                physicalInputStatus
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
                .frame(height: 340)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                touchpadRow
            }

            footer
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.45), radius: 26, y: -8)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("house", "Dock") {
                session.dockAction()
            }
            footerButton("escape", "Esc") {
                session.sendKey("Escape", code: "Escape")
            }

            Spacer(minLength: 8)

            footerButton("slider.horizontal.3", "Settings") {
                environment.isSettingsPresented = true
            }
            footerButton("xmark.circle", "End", tint: ADTheme.danger) {
                showDisconnectConfirm = true
            }
        }
    }

    private var collapsedButton: some View {
        Button {
            if settings.hapticsEnabled { Haptics.shared.tap() }
            isExpanded = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 12, weight: .semibold))
                Text("REMOTE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show remote controls")
    }

    private var displayDetail: String {
        let size = environment.display.externalDisplaySize
        guard size.width > 0, size.height > 0 else { return "Desktop mirrored to the TV" }
        return "Desktop mirrored to the TV · \(Int(size.width))×\(Int(size.height))"
    }

    private func remoteButton(_ icon: String, _ title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? Color(hex: 0x04131A) : Color.white.opacity(0.80))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(active ? AnyShapeStyle(ADTheme.accentGradient()) : AnyShapeStyle(Color.white.opacity(0.06)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(active ? 0.22 : 0.10), lineWidth: 0.7)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func footerButton(_ icon: String, _ title: String, tint: Color = ADTheme.textSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(tint)
            .frame(minWidth: 54, minHeight: 38)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.7)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
