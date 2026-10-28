import SwiftUI

struct MirroredDesktopView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    @State private var isExpanded = true
    @State private var keyboardRequested = false
    @State private var showDisconnectConfirm = false
    @State private var touchpadSize: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            DesktopSurfaceAnchor(surface: session.desktopSurface)
                .ignoresSafeArea()

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
        .animation(.easeInOut(duration: 0.2), value: keyboardRequested)
        .confirmationDialog("End this desktop session?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                keyboardRequested = false
                session.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The mirrored desktop will return to its home screen. Your Wanix workspace stays available for the next session.")
        }
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

    private var touchpad: some View {
        GeometryReader { proxy in
            AirCursorView(
                onAction: { action in
                    session.handleCursor(action, viewport: proxy.size)
                },
                showsHints: settings.showInteractionHints
            )
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8)
                    }
            }
            .onAppear { touchpadSize = proxy.size }
            .onChange(of: proxy.size) { _, size in touchpadSize = size }
        }
        .frame(height: 142)
    }

    private var remotePanel: some View {
        VStack(spacing: 10) {
            header

            HStack(alignment: .top, spacing: 10) {
                touchpad

                VStack(spacing: 8) {
                    remoteButton("cursorarrow.click", "Left") {
                        session.handleCursor(.click(count: 1), viewport: touchpadSize)
                    }
                    remoteButton("cursorarrow.click.2", "Right") {
                        session.handleCursor(.rightClick, viewport: touchpadSize)
                    }
                    remoteButton("keyboard", "Type", active: keyboardRequested) {
                        keyboardRequested.toggle()
                        if keyboardRequested && settings.hapticsEnabled { Haptics.shared.tap() }
                    }
                }
                .frame(width: 64)
            }

            if keyboardRequested {
                KeyboardBar(
                    onDone: { keyboardRequested = false },
                    onInsert: { session.sendText($0) },
                    onBackspace: { session.sendKey("Backspace", code: "Backspace") },
                    onReturn: { session.sendKey("Enter", code: "Enter") }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
