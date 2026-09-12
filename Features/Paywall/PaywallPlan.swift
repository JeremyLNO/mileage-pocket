import Foundation
import StoreKit

/// One plan as the paywall draws it.
///
/// The view renders this and nothing else, so there is a single layout whether the prices
/// come from a live StoreKit query or — in DEBUG only — from the bundled StoreKit
/// configuration, which is how the App Store review screenshot gets taken before the app has
/// ever shipped a build the store knows about.
struct PaywallPlan: Identifiable, Equatable {
    let id: String
    let displayPrice: String
    let hasIntroductoryOffer: Bool

    var isAnnual: Bool { ProductIDs.isAnnual(id) }

    init(product: Product) {
        self.id = product.id
        self.displayPrice = product.displayPrice
        self.hasIntroductoryOffer = product.subscription?.introductoryOffer != nil
    }

    init(id: String, displayPrice: String, hasIntroductoryOffer: Bool) {
        self.id = id
        self.displayPrice = displayPrice
        self.hasIntroductoryOffer = hasIntroductoryOffer
    }

    #if DEBUG
    /// Reads the prices out of the StoreKit configuration that ships in the bundle, so the
    /// captured screen shows the amounts actually configured rather than numbers typed into
    /// a view. Never reachable in Release.
    static func fromBundledConfiguration() -> [PaywallPlan] {
        guard let url = Bundle.main.url(forResource: "MileagePocket", withExtension: "storekit"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = root["subscriptionGroups"] as? [[String: Any]]
        else { return [] }

        return groups
            .flatMap { ($0["subscriptions"] as? [[String: Any]]) ?? [] }
            .compactMap { entry in
                guard let id = entry["productID"] as? String,
                      let price = entry["displayPrice"] as? String
                else { return nil }
                let currency = Locale.current.currency?.identifier ?? "USD"
                let formatted = (Decimal(string: price) ?? 0)
                    .formatted(.currency(code: currency))
                return PaywallPlan(
                    id: id,
                    displayPrice: formatted,
                    hasIntroductoryOffer: entry["introductoryOffer"] != nil
                )
            }
            .sorted { lhs, _ in !lhs.isAnnual }
    }
    #endif
}
