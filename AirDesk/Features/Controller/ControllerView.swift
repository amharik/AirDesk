import SwiftUI
import UIKit

struct ControllerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    @State private var keyboardRequested = false
    @State private var showDisconnectConfirm = false
    @State private var touchpadSize: CGSize = .zero

    var body: some View {
        ZStack {
            AirDeskBackground(intensity: 0.55)

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

                if keyboardRequested {
                    keyboardModeCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                } else {
                    touchpad
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, 10)
                }

                if keyboardRequested {
                    KeyboardBar(
                        onDone: { keyboardRequested = false },
                        onInsert: { session.sendText($0) },
                        onBackspace: { session.sendKey("Backspace", code: "Backspace") },
                        onReturn: { session.sendKey("Enter", code: "Enter") }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    modifierRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    bottomToolbar
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: keyboardRequested)
        .animation(.easeInOut(duration: 0.2), value: session.notice)
        .animation(.easeInOut(duration: 0.2), value: session.runtimeState)
        .confirmationDialog("End this desktop session?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                keyboardRequested = false
                session.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The display will return to its home screen. Your Wanix workspace stays available for the next session.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            if keyboardRequested {
                keyboardRequested = false
            }
        }
        .onAppear {
            Haptics.shared.prepare()
        }
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

    private var touchpad: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.072),
                                Color.white.opacity(0.028),
                                Color.white.opacity(0.055)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [ADTheme.accent.opacity(0.055), .clear],
                            center: .topLeading,
                            startRadius: 20,
                            endRadius: max(proxy.size.width, proxy.size.height) * 0.8
                        )
                    )

                Circle()
                    .fill(ADTheme.accent.opacity(0.05))
                    .frame(width: proxy.size.width * 0.7)
                    .blur(radius: 60)
                    .offset(x: -proxy.size.width * 0.2, y: -proxy.size.height * 0.3)

                AirCursorView(
                    onAction: { action in
                        session.handleCursor(action, viewport: proxy.size)
                    },
                    showsHints: settings.showInteractionHints
                )

                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: session.isDragging ? "cursorarrow.motionlines" : "cursorarrow")
                                .font(.system(size: 10, weight: .bold))
                            Text(session.isDragging ? "DRAGGING" : "AIR CURSOR")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.9)
                        }
                        .foregroundStyle(session.isDragging ? ADTheme.accent : ADTheme.textTertiary)
                        Spacer()
                        if !session.isExternalConnected && session.effectiveMode == .extended {
                            Text("DISPLAY LOST")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(ADTheme.amber)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    Spacer()
                }
                .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                session.isDragging ? ADTheme.accent.opacity(0.55) : Color.white.opacity(0.13),
                                Color.white.opacity(0.045)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: session.isDragging ? 1.5 : 0.9
                    )
                    .allowsHitTesting(false)
                    .shadow(color: session.isDragging ? ADTheme.accent.opacity(0.20) : .clear, radius: 18)
            }
            .onAppear { touchpadSize = proxy.size }
            .onChange(of: proxy.size) { _, newSize in touchpadSize = newSize }
        }
        .accessibilityElement(children: .contain)
    }

    private var modifierRow: some View {
        HStack(spacing: 8) {
            Text("MODIFIERS")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(ADTheme.textTertiary)
            ForEach(InputModifier.allCases) { modifier in
                ModifierChip(
                    symbol: modifier.symbol,
                    isOn: session.modifiers.contains(modifier),
                    action: { session.toggleModifier(modifier) }
                )
            }
            if !session.modifiers.isEmpty {
                Button {
                    session.clearModifiers()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ADTheme.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear modifiers")
            }
            Spacer()
        }
        .frame(height: 36)
    }

    private var bottomToolbar: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                clickHalf(title: "Left", icon: "cursorarrow.click", tint: ADTheme.accent) {
                    session.handleCursor(.click(count: 1), viewport: touchpadSize)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 0.8, height: 30)
                clickHalf(title: "Right", icon: "cursorarrow.click.2", tint: ADTheme.accent) {
                    session.handleCursor(.rightClick, viewport: touchpadSize)
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

            toolButton(icon: "keyboard", title: "Type", active: keyboardRequested) {
                keyboardRequested.toggle()
                if keyboardRequested { Haptics.shared.tap() }
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

    private var keyboardModeCard: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ADTheme.accent)
                    Text("KEYBOARD INPUT")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(ADTheme.textSecondary)
                }
                Spacer()
                CapsuleBadge(text: session.runtimeName, tint: ADTheme.accent)
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("Typing to the desktop")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Use the system keyboard below. The shortcut row sends special keys and modifiers to Wanix.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ADTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)

            if !session.modifiers.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(session.modifiers).sorted { $0.rawValue < $1.rawValue }) { modifier in
                        Text("\(modifier.symbol) \(modifier.rawValue)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ADTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background { Capsule().fill(ADTheme.accent.opacity(0.10)) }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                }
        }
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
