import SwiftUI

struct ProAccessView: View {
    @EnvironmentObject private var entitlements: EntitlementManager
    @Environment(\.dismiss) private var dismiss

    private let features: [ProFeature] = [
        ProFeature(icon: "terminal.fill", title: "Live Wanix Kernel", detail: "Boot the real wanix.wasm workspace from the CDN."),
        ProFeature(icon: "display", title: "Independent display", detail: "Keep the controller and desktop on separate screens."),
        ProFeature(icon: "network", title: "Self-hosted Puter", detail: "Connect your own Puter origin for a private cloud desktop."),
        ProFeature(icon: "cursorarrow.motionlines", title: "Advanced input", detail: "Pointer tuning and motion controls for precise navigation."),
        ProFeature(icon: "person.2.fill", title: "Family sharing", detail: "Share the annual family plan with your household."),
        ProFeature(icon: "heart.fill", title: "Support AirDesk", detail: "Fund continued work on the open desktop controller.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    statusCard
                    featureGrid
                    productList
                    restoreRow
                    legal
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(AirDeskBackground(intensity: 0.65))
            .navigationTitle("AirDesk Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ADTheme.accent)
                }
            }
            .task {
                await entitlements.refresh()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            AirDeskMark(size: 66)
            VStack(spacing: 7) {
                Text("Your desktop, without limits.")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Wanix Desktop stays free. AirDesk Pro unlocks the live kernel, private origins, and the best display experience.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(ADTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 360)
            }
        }
        .padding(.top, 8)
    }

    private var statusCard: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(statusTint.opacity(0.13))
                    .frame(width: 42, height: 42)
                Image(systemName: entitlements.isPro ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(statusTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(entitlements.status.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    if entitlements.isInGracePeriod {
                        CapsuleBadge(text: "Grace", tint: ADTheme.amber)
                    }
                }
                Text(entitlements.statusDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineSpacing(1.5)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                }
        }
    }

    private var featureGrid: some View {
        VStack(spacing: 10) {
            ForEach(features) { feature in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ADTheme.accent)
                        .frame(width: 24, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(ADTheme.accent.opacity(0.10))
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.90))
                        Text(feature.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(ADTheme.textTertiary)
                            .lineSpacing(1.5)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                }
        }
    }

    private var productList: some View {
        VStack(spacing: 10) {
            HStack {
                SectionLabel(text: "Choose your plan")
                Spacer()
                if entitlements.isLoadingProducts {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(ADTheme.accent)
                }
            }

            ForEach(ProProduct.allCases) { proProduct in
                productRow(proProduct)
            }

            if let error = entitlements.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ADTheme.amber)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ADTheme.amber.opacity(0.9))
                        .lineSpacing(1.5)
                    Spacer(minLength: 0)
                    Button {
                        entitlements.clearError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ADTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func productRow(_ proProduct: ProProduct) -> some View {
        let product = entitlements.product(for: proProduct)
        let isActive = entitlements.activeProductIDs.contains(proProduct.rawValue)
        let isAvailable = product != nil

        return Button {
            guard let product else { return }
            Task { await entitlements.purchase(product) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(proProduct.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        if let badge = proProduct.badge {
                            Text(badge)
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .tracking(0.7)
                                .foregroundStyle(ADTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background { Capsule().fill(ADTheme.accent.opacity(0.10)) }
                        }
                    }
                    Text(proProduct.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ADTheme.textTertiary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                if isActive {
                    CapsuleBadge(text: "Active", tint: ADTheme.accent)
                } else if entitlements.isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(ADTheme.accent)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entitlements.displayPrice(for: proProduct))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(isAvailable ? (proProduct.isSubscription ? "per period" : "one time") : "Unavailable")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(ADTheme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? ADTheme.accent.opacity(0.075) : Color.white.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isActive ? ADTheme.accent.opacity(0.25) : Color.white.opacity(0.09),
                                lineWidth: 0.8
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable || entitlements.isPurchasing || isActive)
    }

    private var restoreRow: some View {
        VStack(spacing: 9) {
            if entitlements.isPro {
                Button {
                    Task { await entitlements.showManageSubscriptions() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "gearshape")
                        Text("Manage subscription")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ADTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await entitlements.restorePurchases() }
            } label: {
                HStack(spacing: 7) {
                    if entitlements.isRestoring {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(ADTheme.textSecondary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(entitlements.isRestoring ? "Restoring…" : "Restore purchases")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(ADTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(entitlements.isRestoring)
        }
    }

    private var legal: some View {
        Text("Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel in your App Store account. Family Sharing is available with the Family Annual plan. Prices are shown in your local App Store currency.")
            .font(.system(size: 9.5))
            .foregroundStyle(ADTheme.textTertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.horizontal, 6)
    }

    private var statusTint: Color {
        switch entitlements.status {
        case .loading: return ADTheme.textTertiary
        case .free: return ADTheme.violet
        case .pro: return ADTheme.accent
        case .gracePeriod: return ADTheme.amber
        }
    }
}

private struct ProFeature: Identifiable {
    let icon: String
    let title: String
    let detail: String

    var id: String { title }
}
