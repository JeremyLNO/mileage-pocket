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

    /// Two StoreKit signals, each answering what the other cannot.
    ///
    /// `Transaction.currentEntitlements` is the authority on ownership: it drops a refunded
    /// or expired purchase, which `Product.SubscriptionInfo.Status` does not — the test
    /// session leaves a refunded subscription reporting `.subscribed` with no revocation
    /// date. But `currentEntitlements` cannot express a billing grace period, where the user
    /// still deserves service while Apple retries the card. So: ownership decides, and the
    /// renewal state is consulted only when ownership says nothing.
    func refreshEntitlement() async {
        var resolved = await entitlementFromCurrentEntitlements()
        if resolved == .none, let grace = await gracePeriodEntitlement() {
            resolved = grace
        }
        entitlement = resolved
    }

    private func gracePeriodEntitlement() async -> Entitlement? {
        guard let subscription = products.first?.subscription else { return nil }
        guard let statuses = try? await subscription.status else { return nil }

        for status in statuses {
            guard case let .verified(transaction) = status.transaction else { continue }
            guard ProductIDs.all.contains(transaction.productID) else { continue }
            guard status.state == .inGracePeriod else { continue }
            return Self.entitlement(
                for: status.state,
                productID: transaction.productID,
                expires: transaction.expirationDate,
                isTrial: transaction.offer?.type == .introductory
            )
        }
        return nil
    }

    /// Whether a transaction still grants anything. Refunded money or a passed expiry both
    /// end access, whatever else StoreKit reports.
    ///
    /// Extracted because `SKTestSession.refundTransaction` does not actually revoke an
    /// auto-renewable entitlement — the session keeps reporting the purchase as owned — so a
    /// StoreKit-driven test of this guard cannot fail and therefore proves nothing.
    static func grantsAccess(revokedAt: Date?, expiresAt: Date?, now: Date = .now) -> Bool {
        if let revokedAt, revokedAt <= now { return false }
        if let expiresAt, expiresAt <= now { return false }
        return true
    }

    /// Pure mapping from a renewal state to what the user may do, extracted so every branch
    /// can be tested: StoreKit's test session cannot be made to produce an expired
    /// auto-renewing subscription on demand, and an untested branch here is a paywall that
    /// either never opens or never closes.
    ///
    /// - Returns: `nil` when this status grants nothing.
    static func entitlement(
        for state: Product.SubscriptionInfo.RenewalState,
        productID: String,
        expires: Date?,
        isTrial: Bool
    ) -> Entitlement? {
        switch state {
        case .subscribed:
            return isTrial ? .trial(productID: productID, expires: expires) : .subscribed(productID: productID, expires: expires)
        case .inGracePeriod:
            // Billing failed, Apple is still retrying, and the user keeps service meanwhile.
            return .gracePeriod(productID: productID, expires: expires)
        case .inBillingRetryPeriod, .expired, .revoked:
            // Grace has run out, the subscription lapsed, or the purchase was refunded.
            return nil
        default:
            return nil
        }
    }

    private func entitlementFromCurrentEntitlements() async -> Entitlement {
        var resolved: Entitlement = .none
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            guard ProductIDs.all.contains(transaction.productID) else { continue }
            guard Self.grantsAccess(revokedAt: transaction.revocationDate, expiresAt: transaction.expirationDate) else { continue }

            let isTrial = transaction.offer?.type == .introductory
            resolved = isTrial
                ? .trial(productID: transaction.productID, expires: transaction.expirationDate)
                : .subscribed(productID: transaction.productID, expires: transaction.expirationDate)
        }
        return resolved
    }

    func canAccess(_ feature: PremiumFeature) -> Bool {
        // The demo switch exists only in DEBUG; see `DemoMode`.
        entitlement.isActive || DemoMode.pretendsSubscribed
    }
}
