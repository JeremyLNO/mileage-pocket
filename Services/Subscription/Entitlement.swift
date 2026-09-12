import Foundation

/// What the user is currently entitled to, derived from StoreKit and nothing else.
///
/// There is deliberately no locally stored trial: a date written by the app is a date the
/// user can reset. The 3-day trial is an App Store introductory offer, and StoreKit is the
/// only source of truth for whether it is running.
enum Entitlement: Equatable, Sendable {
    case none
    case trial(productID: String, expires: Date?)
    case subscribed(productID: String, expires: Date?)
    case gracePeriod(productID: String, expires: Date?)

    var isActive: Bool {
        switch self {
        case .none: return false
        case .trial, .subscribed, .gracePeriod: return true
        }
    }

    var productID: String? {
        switch self {
        case .none: return nil
        case let .trial(productID, _), let .subscribed(productID, _), let .gracePeriod(productID, _):
            return productID
        }
    }

    var expirationDate: Date? {
        switch self {
        case .none: return nil
        case let .trial(_, expires), let .subscribed(_, expires), let .gracePeriod(_, expires):
            return expires
        }
    }
}

/// The features that require an active subscription.
///
/// Two things are deliberately absent and stay available forever: **reading** your own trip
/// history, and the **Delete all data** / plain data dump in Settings. A person's own record
/// must not be held hostage by a lapsed payment.
///
/// Report exports — PDF and CSV alike — are premium: they are the product.
enum PremiumFeature: String, Sendable, CaseIterable {
    case startTrip
    case manualTrip
    case exportReport
    case multipleVehicles
}
