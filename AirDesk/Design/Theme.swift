import SwiftUI

enum ADTheme {
    static let accent = Color(red: 0.373, green: 0.890, blue: 0.784)
    static let accentDeep = Color(red: 0.180, green: 0.690, blue: 0.720)
    static let violet = Color(red: 0.545, green: 0.478, blue: 0.980)
    static let amber = Color(red: 0.976, green: 0.702, blue: 0.353)
    static let danger = Color(red: 0.965, green: 0.361, blue: 0.365)

    static let ink = Color(red: 0.031, green: 0.043, blue: 0.063)
    static let inkElevated = Color(red: 0.055, green: 0.071, blue: 0.098)
    static let surface = Color.white.opacity(0.055)
    static let surfaceStrong = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.10)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.025, green: 0.035, blue: 0.055),
            Color(red: 0.043, green: 0.049, blue: 0.078),
            Color(red: 0.024, green: 0.031, blue: 0.047)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func accentGradient(_ color: Color = accent) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.95), accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct AirDeskBackground: View {
    var intensity: Double = 1

    var body: some View {
        ZStack {
            ADTheme.background
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Circle()
                        .fill(ADTheme.accent.opacity(0.20 * intensity))
                        .frame(width: size.width * 0.85)
                        .blur(radius: 90)
                        .offset(x: -size.width * 0.32, y: -size.height * 0.30)
                    Circle()
                        .fill(ADTheme.violet.opacity(0.22 * intensity))
                        .frame(width: size.width * 0.72)
                        .blur(radius: 110)
                        .offset(x: size.width * 0.38, y: -size.height * 0.10)
                    Circle()
                        .fill(ADTheme.accentDeep.opacity(0.14 * intensity))
                        .frame(width: size.width * 0.9)
                        .blur(radius: 120)
                        .offset(x: size.width * 0.10, y: size.height * 0.55)
                }
            }
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.30)],
                        center: .center,
                        startRadius: 120,
                        endRadius: 620
                    )
                )
        }
        .ignoresSafeArea()
    }
}

struct AirDeskMark: View {
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ADTheme.accent, ADTheme.accentDeep, ADTheme.violet.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            AirDeskGlyph()
                .stroke(Color.white.opacity(0.94), style: StrokeStyle(lineWidth: max(1.6, size * 0.065), lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.56, height: size * 0.46)
        }
        .frame(width: size, height: size)
        .shadow(color: ADTheme.accent.opacity(0.35), radius: size * 0.28, x: 0, y: size * 0.12)
        .accessibilityHidden(true)
    }
}

struct AirDeskGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.02, y: h * 0.76))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.30),
            control1: CGPoint(x: w * 0.16, y: h * 0.80),
            control2: CGPoint(x: w * 0.30, y: h * 0.30)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.98, y: h * 0.76),
            control1: CGPoint(x: w * 0.70, y: h * 0.30),
            control2: CGPoint(x: w * 0.84, y: h * 0.80)
        )
        path.move(to: CGPoint(x: w * 0.18, y: h * 0.90))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.62),
            control1: CGPoint(x: w * 0.27, y: h * 0.92),
            control2: CGPoint(x: w * 0.36, y: h * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.82, y: h * 0.90),
            control1: CGPoint(x: w * 0.64, y: h * 0.62),
            control2: CGPoint(x: w * 0.73, y: h * 0.92)
        )
        return path
    }
}
