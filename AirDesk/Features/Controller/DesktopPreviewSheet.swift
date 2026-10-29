import SwiftUI

struct DesktopPreviewSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var isKeyboardActive = false
    @State private var keyboardFocusToken = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if session.canShowPreview {
                DesktopPreviewSurface(surface: session.desktopSurface)
                    .ignoresSafeArea()
            } else {
                AirDeskBackground(intensity: 0.7)
                    .ignoresSafeArea()

                unavailable
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            topBar
                .padding(.horizontal, 16)
                .padding(.top, 10)

            PreviewKeyboardCapture(
                isActive: isKeyboardActive,
                focusRequest: keyboardFocusToken,
                onText: { session.sendText($0) },
                onBackspace: { session.sendKey("Backspace", code: "Backspace") },
                onReturn: { session.sendKey("Enter", code: "Enter") }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .statusBarHidden(true)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.large])
        .onChange(of: session.previewKeyboardShowRequest) { _, _ in
            keyboardFocusToken += 1
            isKeyboardActive = true
        }
        .onChange(of: session.previewKeyboardDismissRequest) { _, _ in
            isKeyboardActive = false
        }
        .onAppear {
            environment.diagnostics.mark("preview.present")
            session.setNativeInputCaptured(false)
            session.setPreviewKeyboardRouting(true)
        }
        .onDisappear {
            isKeyboardActive = false
            session.setPreviewKeyboardRouting(false)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                AirDeskMark(size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Desktop Preview")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 5) {
                        StatusDot(color: ADTheme.accent)
                        Text("LIVE")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(ADTheme.accent)
                        Text("· \(session.selectedDevice?.name ?? "Wanix") · \(session.effectiveMode.title)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(ADTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
                    }
            }
            .allowsHitTesting(false)

            Spacer(minLength: 0)

            Button {
                print("[AirDeskDebug] keyboard button tapped")
                keyboardFocusToken += 1
                isKeyboardActive = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isKeyboardActive ? ADTheme.accent : Color.white.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        isKeyboardActive ? ADTheme.accent.opacity(0.6) : Color.white.opacity(0.12),
                                        lineWidth: 0.7
                                    )
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show keyboard")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preview")
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
            Text("The desktop is rendering on the active display. Close this preview and use the Air Cursor.")
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
