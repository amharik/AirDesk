import SwiftUI

struct ConnectionGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AirDeskBackground(intensity: 0.6)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        guideCard(
                            icon: "appletv.fill",
                            tint: Color(hex: 0x4A9EFF),
                            title: "AirPlay",
                            subtitle: "Best for Apple TV and supported TVs.",
                            steps: [
                                "In Settings, choose Mirror \(DeviceContext.name) screen for a floating remote, or Extended desktop for independent TV output.",
                                "Open Control Center and choose Screen Mirroring.",
                                "Select your Apple TV and return to AirDesk. The desktop appears on the TV."
                            ],
                            footnote: "Mirror mode shows the desktop full-screen with a collapsible floating remote. Extended mode requires iOS to provide an external-display scene."
                        )
                        guideCard(
                            icon: "airplayvideo",
                            tint: Color(hex: 0x6C7CFF),
                            title: "Google Cast",
                            subtitle: "Best for a TV running the AirDesk receiver.",
                            steps: [
                                "Launch the AirDesk Custom Web Receiver on the TV.",
                                "Keep \(DeviceContext.name) and the TV on the same Wi-Fi network.",
                                "Open Connect, scan for Cast receivers, and select one."
                            ],
                            footnote: "The bundled demo receivers let you explore the flow without a registered Cast app ID."
                        )
                        guideCard(
                            icon: "display",
                            tint: Color(hex: 0x55D6C2),
                            title: "Wired or external display",
                            subtitle: "Best for a direct, low-latency connection.",
                            steps: [
                                "Connect the display with the appropriate adapter.",
                                "AirDesk detects the external display automatically.",
                                "Start a session and the desktop moves to the TV."
                            ],
                            footnote: "\(DeviceContext.name) becomes the controller while the external display renders the Wanix desktop."
                        )
                        previewCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Connection Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ADTheme.accent)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose how to connect")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("AirDesk works with AirPlay, Google Cast, wired displays, and an on-device preview.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(ADTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                AirDeskMark(size: 38)
            }

            HStack(spacing: 8) {
                Label("AirPlay", systemImage: "appletv")
                Circle().fill(ADTheme.textTertiary).frame(width: 2.5, height: 2.5)
                Label("Cast", systemImage: "airplayvideo")
                Circle().fill(ADTheme.textTertiary).frame(width: 2.5, height: 2.5)
                Label("Wired", systemImage: "display")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(ADTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    private func guideCard(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        steps: [String],
        footnote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(ADTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(tint)
                            .frame(width: 20, height: 20)
                            .background {
                                Circle().fill(tint.opacity(0.12))
                            }
                        Text(step)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

            Text(footnote)
                .font(.system(size: 11))
                .foregroundStyle(ADTheme.textTertiary)
                .lineSpacing(2)
                .padding(.top, 1)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8)
                }
        }
    }

    private var previewCard: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ADTheme.violet.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: DeviceContext.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ADTheme.violet)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("No TV nearby?")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Use Preview on this \(DeviceContext.name) to explore the full controller and desktop shell.")
                    .font(.system(size: 12))
                    .foregroundStyle(ADTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ADTheme.violet.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(ADTheme.violet.opacity(0.16), lineWidth: 0.7)
                }
        }
    }
}
