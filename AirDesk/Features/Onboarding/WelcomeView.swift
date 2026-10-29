import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showConnection: Bool
    @State private var animateHero = false
    @State private var showGuide = false

    var body: some View {
        ZStack {
            AirDeskBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    brandHeader
                        .padding(.top, 10)

                    DisplayHero(animate: animateHero)
                        .frame(maxWidth: 560)
                        .padding(.top, 20)

                    VStack(spacing: 12) {
                        Text("Your desktop,\nacross the room.")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .tracking(-1.2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                            .lineSpacing(-2)

                        Text("Turn \(DeviceContext.name) into a precision Air Cursor for a Wanix desktop on your TV. Move, click, scroll, and type from the couch.")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(ADTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .frame(maxWidth: 460)
                    }
                    .padding(.top, 26)

                    featureStrip
                        .padding(.top, 24)

                    VStack(spacing: 12) {
                        Button {
                            showConnection = true
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "airplayvideo")
                                Text("Connect Display")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            environment.session.beginConnection(to: DisplayDevice.previewDevice)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: DeviceContext.symbolName)
                                Text("Preview on this \(DeviceContext.name)")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(maxWidth: 460)
                    .padding(.top, 30)

                    Button {
                        showGuide = true
                    } label: {
                        Label("How connection works", systemImage: "questionmark.circle")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(ADTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    HStack(spacing: 14) {
                        Label("AirPlay", systemImage: "appletv")
                        Circle().fill(ADTheme.textTertiary).frame(width: 2.5, height: 2.5)
                        Label("Wired", systemImage: "display")
                        Circle().fill(ADTheme.textTertiary).frame(width: 2.5, height: 2.5)
                        Label("Google Cast", systemImage: "airplayvideo")
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ADTheme.textTertiary)
                    .padding(.top, 22)

                    Text("Wanix runtime · macOS-style workspace · Native controller")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ADTheme.textTertiary)
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showGuide) {
            ConnectionGuideView()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                animateHero = true
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            AirDeskMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("AirDesk")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("WIRELESS DESKTOP CONTROLLER")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(ADTheme.textTertiary)
            }
            Spacer()
            CapsuleBadge(text: "Wanix", tint: ADTheme.accent, icon: "cpu")
        }
        .frame(maxWidth: 560)
    }

    private var featureStrip: some View {
        HStack(spacing: 8) {
            feature(icon: "rectangle.on.rectangle", title: "Big screen", tint: ADTheme.accent)
            feature(icon: "cursorarrow.motionlines", title: "Air Cursor", tint: ADTheme.violet)
            feature(icon: "keyboard", title: "Type", tint: ADTheme.amber)
        }
        .frame(maxWidth: 460)
    }

    private func feature(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
                }
        }
    }
}

struct DisplayHero: View {
    var animate: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    MiniDesktop()
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        }
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [Color.white.opacity(0.10), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .shadow(color: ADTheme.accent.opacity(0.18), radius: 40, y: 24)
                }
                .padding(7)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(white: 0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        }
                }

                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 74, height: 5)
                    .padding(.top, 5)
                Ellipse()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 150, height: 12)
                    .blur(radius: 7)
                    .padding(.top, -2)
            }
            .padding(.trailing, 42)
            .offset(y: animate ? -5 : 5)
            .animation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: animate)

            PhoneMockup()
                .frame(width: 118, height: 224)
                .offset(x: -4, y: 2)
                .rotationEffect(.degrees(-3))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 16)
        }
        .frame(height: 292)
    }
}

struct MiniDesktop: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.071, blue: 0.13),
                        Color(red: 0.09, green: 0.22, blue: 0.28),
                        Color(red: 0.18, green: 0.11, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(ADTheme.accent.opacity(0.30))
                    .frame(width: width * 0.55)
                    .blur(radius: 34)
                    .offset(x: -width * 0.25, y: -height * 0.15)
                Circle()
                    .fill(ADTheme.violet.opacity(0.28))
                    .frame(width: width * 0.45)
                    .blur(radius: 38)
                    .offset(x: width * 0.28, y: height * 0.28)

                VStack(spacing: 0) {
                    HStack(spacing: width * 0.018) {
                        Circle().fill(Color.white.opacity(0.85)).frame(width: width * 0.014)
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.65)).frame(width: width * 0.055, height: height * 0.022)
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.35)).frame(width: width * 0.042, height: height * 0.022)
                        Spacer()
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.4)).frame(width: width * 0.045, height: height * 0.022)
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.4)).frame(width: width * 0.045, height: height * 0.022)
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.4)).frame(width: width * 0.045, height: height * 0.022)
                    }
                    .padding(.horizontal, width * 0.028)
                    .frame(height: height * 0.09)
                    .background(Color.black.opacity(0.35))

                    HStack(spacing: width * 0.02) {
                        MiniWindow(title: "Terminal", tint: ADTheme.accent, width: width * 0.35, height: height * 0.55, terminal: true)
                            .offset(y: height * 0.02)
                        VStack(spacing: height * 0.025) {
                            MiniWindow(title: "Welcome", tint: .white, width: width * 0.26, height: height * 0.32, terminal: false)
                            MiniWindow(title: "Workbench", tint: ADTheme.violet, width: width * 0.26, height: height * 0.24, terminal: false)
                        }
                        .offset(y: -height * 0.02)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, width * 0.035)
                    .padding(.vertical, height * 0.04)

                    HStack(spacing: width * 0.012) {
                        ForEach(Array([ADTheme.accent, ADTheme.violet, ADTheme.amber, Color.white.opacity(0.75), Color.white.opacity(0.35)].enumerated()), id: \.offset) { item in
                            RoundedRectangle(cornerRadius: width * 0.008, style: .continuous)
                                .fill(item.element.opacity(0.8))
                                .frame(width: width * 0.034, height: width * 0.034)
                        }
                    }
                    .padding(.horizontal, width * 0.02)
                    .padding(.vertical, width * 0.01)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.016, style: .continuous))
                    .padding(.bottom, height * 0.035)

                    Spacer().frame(height: 0)
                }
            }
        }
    }
}

struct MiniWindow: View {
    let title: String
    let tint: Color
    let width: CGFloat
    let height: CGFloat
    let terminal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2.5) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 3.5, height: 3.5)
                Circle().fill(Color(red: 1, green: 0.75, blue: 0.30)).frame(width: 3.5, height: 3.5)
                Circle().fill(Color(red: 0.30, green: 0.82, blue: 0.40)).frame(width: 3.5, height: 3.5)
                Text(title)
                    .font(.system(size: 4.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.leading, 2)
                Spacer()
            }
            .padding(.horizontal, 5)
            .frame(height: 10)
            .background(Color.black.opacity(0.30))

            VStack(alignment: .leading, spacing: 3) {
                if terminal {
                    ForEach(Array(["wanix ~ % neofetch", "OS  Wanix 0.4", "WM  Desktop", "GPU Browser", "wanix ~ % _"].enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 4, weight: .medium, design: .monospaced))
                            .foregroundStyle(item.offset == 0 || item.offset == 4 ? tint : Color.white.opacity(0.45))
                    }
                } else {
                    RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.7)).frame(width: width * 0.4, height: 3)
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.18 - Double(index) * 0.02))
                            .frame(width: width * (0.8 - Double(index) * 0.1), height: 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .background(Color.black.opacity(terminal ? 0.42 : 0.24))
        }
        .frame(width: width, height: height)
        .background(Color(red: 0.10, green: 0.11, blue: 0.135).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
    }
}

struct PhoneMockup: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
                    .fill(Color(red: 0.035, green: 0.043, blue: 0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    }

                VStack(spacing: height * 0.025) {
                    Capsule()
                        .fill(Color.black)
                        .frame(width: width * 0.26, height: height * 0.012)
                        .padding(.top, height * 0.018)

                    HStack(spacing: width * 0.02) {
                        Circle().fill(ADTheme.accent).frame(width: width * 0.03, height: width * 0.03)
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.55)).frame(width: width * 0.28, height: height * 0.011)
                        Spacer()
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.25)).frame(width: width * 0.12, height: height * 0.011)
                    }
                    .padding(.horizontal, width * 0.09)

                    ZStack {
                        RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.035)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.8)
                            }

                        VStack(spacing: height * 0.018) {
                            Image(systemName: "cursorarrow")
                                .font(.system(size: width * 0.18, weight: .light))
                                .foregroundStyle(ADTheme.accent.opacity(0.7))
                            Text("AIR CURSOR")
                                .font(.system(size: width * 0.035, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(Color.white.opacity(0.28))
                        }

                        Circle()
                            .stroke(ADTheme.accent.opacity(0.35), lineWidth: 1)
                            .frame(width: width * 0.36, height: width * 0.36)
                            .blur(radius: 0.5)
                    }
                    .padding(.horizontal, width * 0.075)
                    .frame(maxHeight: .infinity)

                    HStack(spacing: width * 0.055) {
                        ForEach(["cursorarrow.click", "cursorarrow.click.2", "keyboard", "escape", "house"], id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: width * 0.052, weight: .medium))
                                .foregroundStyle(Color.white.opacity(icon == "keyboard" ? 0.95 : 0.55))
                                .frame(width: width * 0.11, height: width * 0.11)
                                .background {
                                    Circle().fill(icon == "keyboard" ? ADTheme.accent.opacity(0.9) : Color.white.opacity(0.07))
                                }
                                .foregroundStyle(icon == "keyboard" ? Color(hex: 0x04131A) : Color.white.opacity(0.55))
                        }
                    }
                    .padding(.bottom, height * 0.03)
                }
            }
        }
    }
}

extension DisplayDevice {
    static let previewDevice = DisplayDevice(
        id: DisplayDevice.previewID,
        name: "This \(DeviceContext.name)",
        detail: "Live Wanix desktop preview",
        kind: .preview,
        mode: .preview,
        isDemo: true
    )
}
