import Foundation
import StoreKit
import UIKit

enum ProProduct: String, CaseIterable, Identifiable, Sendable {
    case monthly = "com.airdesk.pro.monthly"
    case yearly = "com.airdesk.pro.yearly"
    case familyYearly = "com.airdesk.pro.family.yearly"
    case lifetime = "com.airdesk.pro.lifetime"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Annual"
        case .familyYearly: return "Family Annual"
        case .lifetime: return "Lifetime"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly: return "Flexible month-to-month access."
        case .yearly: return "Two months free compared with monthly."
        case .familyYearly: return "One subscription for your family."
        case .lifetime: return "Pay once. Keep Pro forever."
        }
    }

    var fallbackPrice: String {
        switch self {
        case .monthly: return "$2.99"
        case .yearly: return "$19.99"
        case .familyYearly: return "$29.99"
        case .lifetime: return "$49.99"
        }
    }

    var badge: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "BEST VALUE"
        case .familyYearly: return "FAMILY"
        case .lifetime: return "ONE-TIME"
        }
    }

    var isSubscription: Bool {
        self != .lifetime
    }

    var sortOrder: Int {
        switch self {
        case .monthly: return 0
        case .yearly: return 1
        case .familyYearly: return 2
        case .lifetime: return 3
        }
    }
}

enum ProStatus: Equatable {
    case loading
    case free
    case pro
    case gracePeriod

    var title: String {
        switch self {
        case .loading: return "Checking"
        case .free: return "Free"
        case .pro: return "Pro"
        case .gracePeriod: return "Pro · Grace"
        }
    }
}

@MainActor
final class EntitlementManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var status: ProStatus = .loading
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var expirationDate: Date?
    @Published private(set) var willAutoRenew: Bool?
    @Published private(set) var autoRenewPreference: String?
    @Published private(set) var isInGracePeriod = false
    @Published private(set) var lastRefresh = Date.distantPast

    private var updatesTask: Task<Void, Never>?
    private var started = false

    var isPro: Bool {
        status == .pro || status == .gracePeriod
    }

    var canUseProFeatures: Bool {
        isPro
    }

    func canUse(_ runtime: RuntimeChoice) -> Bool {
        !runtime.requiresPro || isPro
    }

    var activePlanName: String? {
        activeProductIDs
            .compactMap(ProProduct.init(rawValue:))
            .sorted { $0.sortOrder < $1.sortOrder }
            .first?
            .title
    }

    var statusDetail: String {
        switch status {
        case .loading:
            return "Checking your App Store purchase."
        case .free:
            return "Wanix Desktop is free. Pro unlocks the live kernel and advanced display features."
        case .pro:
            if let expirationDate {
                if willAutoRenew == false {
                    return "Active until \(expirationDate.formatted(date: .abbreviated, time: .omitted)). Auto-renew is off."
                }
                return "Active until \(expirationDate.formatted(date: .abbreviated, time: .omitted))."
            }
            return "Lifetime access is active."
        case .gracePeriod:
            if let expirationDate {
                return "Payment needs attention. Pro stays active until \(expirationDate.formatted(date: .abbreviated, time: .omitted))."
            }
            return "Payment needs attention. Pro is temporarily active."
        }
    }

    func start() {
        guard !started else { return }
        started = true

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(update: result)
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: ProProduct.allCases.map(\.rawValue))
            products = fetched.sorted { lhs, rhs in
                let left = ProProduct(rawValue: lhs.id)?.sortOrder ?? .max
                let right = ProProduct(rawValue: rhs.id)?.sortOrder ?? .max
                return left < right
            }
        } catch {
            errorMessage = "Could not load AirDesk Pro products. Check your connection and try again."
        }
    }

    func product(for proProduct: ProProduct) -> Product? {
        products.first { $0.id == proProduct.rawValue }
    }

    func displayPrice(for proProduct: ProProduct) -> String {
        product(for: proProduct)?.displayPrice ?? proProduct.fallbackPrice
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await refreshEntitlements()
                await transaction.finish()
            case .pending:
                errorMessage = "The purchase is pending approval. Pro will activate after it is approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "The purchase could not be completed. \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Purchases could not be restored. \(error.localizedDescription)"
        }
    }

    func showManageSubscriptions() async {
        guard let scene = activeWindowScene else {
            errorMessage = "Subscriptions can only be managed while AirDesk is open."
            return
        }

        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            errorMessage = "Subscriptions could not be opened. \(error.localizedDescription)"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func handle(update result: VerificationResult<Transaction>) async {
        guard let transaction = try? verified(result) else { return }
        guard ProProduct(rawValue: transaction.productID) != nil else {
            await transaction.finish()
            return
        }

        await refreshEntitlements()
        await transaction.finish()
    }

    private func refreshEntitlements() async {
        var activeIDs = Set<String>()
        var latestExpiration: Date?
        var gracePeriod = false
        var autoRenew: Bool?
        var renewalPreference: String?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard ProProduct(rawValue: transaction.productID) != nil else { continue }
            if let expiration = transaction.expirationDate, expiration <= Date() {
                continue
            }

            activeIDs.insert(transaction.productID)
            if let expiration = transaction.expirationDate,
               expiration > (latestExpiration ?? .distantPast) {
                latestExpiration = expiration
            }
        }

        if let groupID = subscriptionGroupID {
            do {
                let statuses = try await Product.SubscriptionInfo.status(for: groupID)
                for subscriptionStatus in statuses {
                    guard let transaction = try? verified(subscriptionStatus.transaction) else { continue }
                    guard ProProduct(rawValue: transaction.productID) != nil else { continue }

                    switch subscriptionStatus.state {
                    case .subscribed:
                        activeIDs.insert(transaction.productID)
                    case .inGracePeriod:
                        activeIDs.insert(transaction.productID)
                        gracePeriod = true
                    case .inBillingRetryPeriod, .expired, .revoked:
                        break
                    default:
                        break
                    }

                    guard subscriptionStatus.state == .subscribed || subscriptionStatus.state == .inGracePeriod else {
                        continue
                    }

                    if let renewal = try? verified(subscriptionStatus.renewalInfo) {
                        autoRenew = renewal.willAutoRenew
                        renewalPreference = renewal.autoRenewPreference
                        if subscriptionStatus.state == .inGracePeriod,
                           let graceExpiration = renewal.gracePeriodExpirationDate,
                           graceExpiration > (latestExpiration ?? .distantPast) {
                            latestExpiration = graceExpiration
                        }
                    }

                    if let expiration = transaction.expirationDate,
                       expiration > (latestExpiration ?? .distantPast) {
                        latestExpiration = expiration
                    }
                }
            } catch {
                // Entitlements from Transaction.currentEntitlements remain valid.
            }
        }

        activeProductIDs = activeIDs
        expirationDate = latestExpiration
        isInGracePeriod = gracePeriod
        willAutoRenew = autoRenew
        autoRenewPreference = renewalPreference

        if activeIDs.isEmpty {
            status = .free
        } else if gracePeriod {
            status = .gracePeriod
        } else {
            status = .pro
        }

        lastRefresh = Date()
    }

    private var subscriptionGroupID: String? {
        products.compactMap { $0.subscription?.subscriptionGroupID }.first
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}
