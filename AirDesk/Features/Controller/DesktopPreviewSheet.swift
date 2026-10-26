import SwiftUI

struct DesktopPreviewSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var touchpadSize: CGSize = .zero

    var body: some View {
        ZStack {
            AirDeskBackground(intensity: 0.7)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    topBar

                    if session.canShowPreview {
                        previewSurface
                        liveHint
                        miniTouchpad
                        miniControls
                    } else {
                        unavailable
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .onAppear {
            environment.diagnostics.mark("preview.present")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            AirDeskMark(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Desktop Preview")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(session.selectedDevice?.name ?? "Wanix") · \(session.effectiveMode.title)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ADTheme.textTertiary)
            }
            Spacer()
            HStack(spacing: 5) {
                StatusDot(color: ADTheme.accent)
                Text("LIVE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(ADTheme.accent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background { Capsule().fill(ADTheme.accent.opacity(0.10)) }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background { Circle().fill(Color.white.opacity(0.07)) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preview")
        }
        .padding(.top, 6)
    }

    private var previewSurface: some View {
        ZStack {
            Color.black
            DesktopPreviewSurface(surface: session.desktopSurface)
                .aspectRatio(16 / 9, contentMode: .fit)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 26, y: 16)
    }

    private var liveHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ADTheme.accent)
            Text("Drag the mini touchpad to control the live desktop. In extended mode, this surface moves to the TV.")
                .font(.system(size: 11.5))
                .foregroundStyle(ADTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var miniTouchpad: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.8)
                    }
                AirCursorView(
                    onAction: { action in
                        session.handleCursor(action, viewport: proxy.size)
                    },
                    showsHints: false
                )
                VStack {
                    HStack {
                        Text("AIR CURSOR")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .tracking(0.9)
                            .foregroundStyle(ADTheme.textTertiary)
                        Spacer()
                        Text("TAP · DRAG · SCROLL")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(ADTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 13)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            .onAppear { touchpadSize = proxy.size }
        }
        .frame(height: 168)
    }

    private var miniControls: some View {
        HStack(spacing: 10) {
            Button {
                session.handleCursor(.click(count: 1), viewport: touchpadSize)
            } label: {
                Label("Left Click", systemImage: "cursorarrow.click")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                            }
                    }
            }
            .buttonStyle(ToolbarPressStyle())

            Button {
                session.handleCursor(.rightClick, viewport: touchpadSize)
            } label: {
                Label("Right Click", systemImage: "cursorarrow.click.2")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                            }
                    }
            }
            .buttonStyle(ToolbarPressStyle())

            Button {
                session.sendKey("Escape", code: "Escape")
            } label: {
                Text("ESC")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 58, height: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.7)
                            }
                    }
            }
            .buttonStyle(ToolbarPressStyle())
        }
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: session.displayModeUnavailableIcon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ADTheme.textTertiary)
            Text("Preview unavailable")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("The desktop is rendering on the active display. Close this sheet and use the Air Cursor.")
                .font(.system(size: 13))
                .foregroundStyle(ADTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

extension SessionCoordinator {
    var displayModeUnavailableIcon: String {
        effectiveMode == .cast ? "airplayvideo" : "rectangle.on.rectangle"
    }
}
