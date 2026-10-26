import SwiftUI

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.035))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.8)
                    }
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = ADTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: 0x04131A))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ADTheme.accentGradient(tint))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                    }
                    .shadow(color: tint.opacity(0.30), radius: 18, y: 10)
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.88))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.065))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.8)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 58
    var tint: Color = .white
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.34, weight: .medium))
            .foregroundStyle(filled ? Color(hex: 0x04131A) : tint.opacity(0.92))
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(filled ? AnyShapeStyle(ADTheme.accentGradient()) : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.13 : 0.065)))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(filled ? 0.22 : 0.12), lineWidth: 0.8)
                    }
                    .shadow(color: filled ? ADTheme.accent.opacity(0.25) : .clear, radius: 14, y: 8)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CapsuleBadge: View {
    let text: String
    var tint: Color = ADTheme.accent
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text.uppercased())
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(tint.opacity(0.11))
                .overlay {
                    Capsule().strokeBorder(tint.opacity(0.24), lineWidth: 0.7)
                }
        }
    }
}

struct StatusDot: View {
    var color: Color
    var pulsing: Bool = false
    @State private var visible = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                Circle().stroke(color.opacity(0.35), lineWidth: 4)
            }
            .opacity(pulsing ? (visible ? 1 : 0.35) : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
            .accessibilityHidden(true)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.3)
            .foregroundStyle(ADTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PressableScale: ViewModifier {
    @State private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
    }
}

struct ModifierChip: View {
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(minWidth: 42, minHeight: 36)
                .foregroundStyle(isOn ? Color(hex: 0x04131A) : Color.white.opacity(0.75))
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(ADTheme.accentGradient()) : AnyShapeStyle(Color.white.opacity(0.06)))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(isOn ? 0.22 : 0.10), lineWidth: 0.7)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var accessibilityName: String {
        switch symbol {
        case "⌘": return "Command"
        case "⌥": return "Option"
        case "⌃": return "Control"
        case "⇧": return "Shift"
        default: return symbol
        }
    }
}
