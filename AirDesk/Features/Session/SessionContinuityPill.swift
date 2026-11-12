import SwiftUI

struct SessionContinuityPill: View {
    @EnvironmentObject private var session: SessionCoordinator

    var body: some View {
        let presentation = session.sessionContinuity
        if presentation.isVisible {
            HStack(spacing: 9) {
                Image(systemName: presentation.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint(for: presentation.tone))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !presentation.detail.isEmpty {
                        Text(presentation.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(ADTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if let latency = presentation.latencyMilliseconds {
                    Text("\(latency) ms")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint(for: presentation.tone))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background {
                            Capsule()
                                .fill(tint(for: presentation.tone).opacity(0.14))
                        }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.80))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(tint(for: presentation.tone).opacity(0.30), lineWidth: 0.8)
                    }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: presentation))
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private func tint(for tone: SessionContinuityTone) -> Color {
        switch tone {
        case .neutral: return ADTheme.textSecondary
        case .positive: return ADTheme.accent
        case .warning: return ADTheme.amber
        case .critical: return ADTheme.danger
        }
    }

    private func accessibilityLabel(for presentation: SessionContinuityPresentation) -> String {
        var label = "\(presentation.title). \(presentation.detail)"
        if let latency = presentation.latencyMilliseconds {
            label += " \(latency) milliseconds."
        }
        return label
    }
}
