import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class SubscriptionService {
    private(set) var entitlement: Entitlement = .none
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {}

    // No `deinit` cancelling `updatesTask`: the service lives for the whole app session by
    // design, and a `deinit` on a `@MainActor` type cannot touch main-actor state under
    // Swift 6 anyway. `stop()` exists for tests, which do need to tear it down.
    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    var monthly: Product? { products.first { $0.id == ProductIDs.monthly } }
    var annual: Product? { products.first { $0.id == ProductIDs.annual } }

    /// What the annual plan saves against twelve months of the monthly one, computed from
    /// the live StoreKit prices — never a number typed into the UI, which would be wrong in
    /// every storefront but one.
    var annualSavingsPercent: Int? {
        guard let monthly, let annual else { return nil }
        let twelveMonths = monthly.price * 12
        guard twelveMonths > 0, annual.price < twelveMonths else { return nil }
        let ratio = (twelveMonths - annual.price) / twelveMonths * 100
        return Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
    }

    /// The introductory offer on a plan, if the account is still eligible for it.
    func introductoryOffer(for product: Product) -> Product.SubscriptionOffer? {
        product.subscription?.introductoryOffer
    }

    func start() {
        updatesTask?.cancel()
        // Transactions can arrive at any time — an Ask to Buy approval, a renewal, a
        // purchase made on another device — so this listener runs for the app's lifetime,
        // not just around a purchase call.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: ProductIDs.all)
            products = loaded.sorted { lhs, _ in lhs.id == ProductIDs.monthly }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlement()
    }

    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                // An unverified transaction is not a purchase. Never grant on it.
                return false
            }
            await transaction.finish()
            await refreshEntitlement()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var resolved: Entitlement = .none

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            guard ProductIDs.all.contains(transaction.productID) else { continue }
            if let revocation = transaction.revocationDate, revocation <= .now { continue }
            if let expiration = transaction.expirationDate, expiration <= .now { continue }

            let isTrial = transaction.offer?.type == .introductory
            resolved = isTrial
                ? .trial(productID: transaction.productID, expires: transaction.expirationDate)
                : .subscribed(productID: transaction.productID, expires: transaction.expirationDate)
        }

        // A subscription in its billing grace period still has `currentEntitlements`, but a
        // failed renewal that has left grace does not — checking the renewal state is what
        // separates "we are still trying to charge you" from "this has lapsed".
        if resolved == .none, let status = await gracePeriodStatus() {
            resolved = status
        }

        entitlement = resolved
    }

    private func gracePeriodStatus() async -> Entitlement? {
        guard let product = products.first, let subscription = product.subscription else { return nil }
        guard let statuses = try? await subscription.status else { return nil }
        for status in statuses {
            guard case let .verified(renewalInfo) = status.renewalInfo else { continue }
            guard status.state == .inGracePeriod else { continue }
            guard case let .verified(transaction) = status.transaction else { continue }
            return .gracePeriod(productID: renewalInfo.currentProductID, expires: transaction.expirationDate)
        }
        return nil
    }

    func canAccess(_ feature: PremiumFeature) -> Bool {
        // The demo switch exists only in DEBUG; see `DemoMode`.
        entitlement.isActive || DemoMode.pretendsSubscribed
    }
}
