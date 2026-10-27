import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var cast: CastSessionCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var entitlements: EntitlementManager
    @State private var appeared = false
    @State private var showGuide = false
    @State private var pendingDevice: DisplayDevice?

    var body: some View {
        ZStack {
            AirDeskBackground(intensity: 0.8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    if let error = session.lastError {
                        errorBanner(error)
                    }
                    displaySection
                    castSection
                    previewSection
                    compatibilityNote
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            guard !appeared else { return }
            appeared = true
            try? await Task.sleep(nanoseconds: 250_000_000)
            cast.startDiscovery()
        }
        .onDisappear {
            cast.stopDiscovery()
        }
        .sheet(isPresented: $showGuide) {
            ConnectionGuideView()
        }
        .sheet(item: $pendingDevice) { device in
            SessionSetupView(device: device)
                .environmentObject(environment)
                .environmentObject(session)
                .environmentObject(settings)
                .environmentObject(entitlements)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose a display")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("AirDesk will launch a Wanix desktop and switch to the Air Cursor.")
                        .font(.system(size: 14))
                        .foregroundStyle(ADTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Button {
                    showGuide = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11, weight: .bold))
                        Text("GUIDE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                    }
                    .foregroundStyle(ADTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(ADTheme.accent.opacity(0.10))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open connection guide")
            }
        }
        .padding(.top, 8)
    }

    private var displaySection: some View {
        VStack(spacing: 10) {
            SectionLabel(text: "Displays")
            VStack(spacing: 8) {
                if environment.display.hasExternalDisplay {
                    DeviceRow(
                        device: externalDevice,
                        action: { prepare(externalDevice) }
                    )
                }
                DeviceRow(
                    device: demoAirPlayDevice,
                    action: { prepare(demoAirPlayDevice) }
                )
            }
        }
    }

    private var castSection: some View {
        VStack(spacing: 10) {
            HStack {
                SectionLabel(text: "Google Cast")
                Spacer()
                Button {
                    cast.startDiscovery()
                    if environment.settings.hapticsEnabled { Haptics.shared.tap() }
                } label: {
                    HStack(spacing: 5) {
                        if cast.state == .discovering {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(ADTheme.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(cast.state == .discovering ? "SCANNING" : "SCAN")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                    }
                    .foregroundStyle(ADTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(ADTheme.accent.opacity(0.10))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan for Google Cast devices")
            }

            VStack(spacing: 8) {
                ForEach(castDevices) { device in
                    DeviceRow(device: device, action: { prepare(device) })
                }

                if castDevices.isEmpty {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 42, height: 42)
                            Image(systemName: "airplayvideo")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(ADTheme.textTertiary)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cast.state == .discovering ? "Searching the local network…" : "No Cast receivers found")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                            Text("Use a receiver running the AirDesk Custom Web Receiver.")
                                .font(.system(size: 12))
                                .foregroundStyle(ADTheme.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.025))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                            }
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(spacing: 10) {
            SectionLabel(text: "This device")
            DeviceRow(
                device: DisplayDevice.previewDevice,
                action: { prepare(DisplayDevice.previewDevice) }
            )
        }
    }

    private var compatibilityNote: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ADTheme.accent)
                Text("About display modes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            Text("Extended desktop requires a supported external display. AirPlay screen mirroring does not create a separate desktop — AirDesk labels the active mode instead of promising independent output.")
                .font(.system(size: 12))
                .foregroundStyle(ADTheme.textSecondary)
                .lineSpacing(2)
            Text("This build includes demo receivers so the full controller can be explored without a TV. Real Google Cast requires the Google Cast SDK and a registered AirDesk receiver; real AirPlay output is provided by the system.")
                .font(.system(size: 12))
                .foregroundStyle(ADTheme.textTertiary)
                .lineSpacing(2)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
                }
        }
        .padding(.top, 4)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ADTheme.amber)
                .font(.system(size: 16))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 7) {
                Text("Couldn't start the session")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(ADTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    if let device = session.selectedDevice {
                        Button("Retry") { retry(device) }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ADTheme.accent)
                    }
                    Button("Dismiss") { session.dismissError() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ADTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ADTheme.amber.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(ADTheme.amber.opacity(0.22), lineWidth: 0.8)
                }
        }
    }

    private var externalDevice: DisplayDevice {
        DisplayDevice(
            id: "display.external",
            name: environment.display.externalDisplayName.isEmpty ? "External display" : environment.display.externalDisplayName,
            detail: "Connected · \(Int(environment.display.externalDisplaySize.width))×\(Int(environment.display.externalDisplaySize.height))",
            kind: .external,
            mode: .extended,
            isDemo: false
        )
    }

    private var demoAirPlayDevice: DisplayDevice {
        DisplayDevice(
            id: DisplayDevice.demoAppleTV,
            name: "Living Room TV",
            detail: "Apple TV · AirPlay mirroring",
            kind: .airPlay,
            mode: .mirrored,
            isDemo: true
        )
    }

    private var castDevices: [DisplayDevice] {
        cast.devices.map { device in
            DisplayDevice(
                id: device.id,
                name: device.name,
                detail: "\(device.model) · \(cast.isDemo ? "Demo receiver" : "Google Cast")",
                kind: .cast,
                mode: .cast,
                isDemo: device.isDemo || cast.isDemo
            )
        }
    }

    private func prepare(_ device: DisplayDevice) {
        if environment.settings.hapticsEnabled { Haptics.shared.tap() }
        pendingDevice = device
    }

    private func retry(_ device: DisplayDevice) {
        if environment.settings.hapticsEnabled { Haptics.shared.tap() }
        session.beginConnection(to: device)
    }
}

struct DeviceRow: View {
    let device: DisplayDevice
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: iconColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                        }
                    Image(systemName: device.iconName)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if device.isDemo {
                            Text("DEMO")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(ADTheme.amber)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(ADTheme.amber.opacity(0.12))
                                }
                        }
                    }
                    Text(device.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(ADTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(device.statusText.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(ADTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(ADTheme.accent.opacity(0.10))
                    }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
            .padding(11)
            .background {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Color.white.opacity(pressed ? 0.08 : 0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(Color.white.opacity(pressed ? 0.16 : 0.09), lineWidth: 0.8)
                    }
            }
            .scaleEffect(pressed ? 0.985 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.16)) { pressed = false } }
        )
        .accessibilityLabel("\(device.name). \(device.detail). \(device.statusText)")
        .accessibilityHint("Opens session setup")
    }

    private var iconColors: [Color] {
        switch device.kind {
        case .airPlay: return [Color(hex: 0x4A9EFF), Color(hex: 0x1E5FCC)]
        case .wired, .external: return [Color(hex: 0x55D6C2), Color(hex: 0x1A8F86)]
        case .cast: return [Color(hex: 0x6C7CFF), Color(hex: 0x3A3FA8)]
        case .preview: return [Color(hex: 0x8C7CFF), Color(hex: 0x5140B8)]
        }
    }
}
