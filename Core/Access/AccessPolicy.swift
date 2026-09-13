import Foundation

/// The free period a new install gets before the paywall appears.
struct FreeAccessPeriod: Equatable, Sendable {
    static let duration: TimeInterval = 3 * 24 * 3600

    let startedAt: Date

    var endsAt: Date { startedAt.addingTimeInterval(Self.duration) }

    /// Active up to, but not including, the instant it ends.
    func isActive(now: Date = .now) -> Bool { now < endsAt }

    /// Whole days left, rounded up, so the last partial day still reads as "1 day left"
    /// rather than "0".
    func daysRemaining(now: Date = .now) -> Int {
        guard isActive(now: now) else { return 0 }
        return max(1, Int((endsAt.timeIntervalSince(now) / 86_400).rounded(.up)))
    }
}

/// Who may do what.
///
/// Kept as a pure function of (feature, entitlement, free period) so every combination is
/// testable without StoreKit, a clock, or a keychain — this is the rule the whole paywall
/// rests on, and it must not be inferred from three `if`s spread across views.
enum AccessPolicy {
    static func allows(_ feature: PremiumFeature, entitlement: Entitlement, freePeriodActive: Bool) -> Bool {
        if entitlement.isActive { return true }
        // Exporting a report is the product being sold, so it is never part of the free
        // period — unlike reading, which is never gated at all.
        if feature == .exportReport { return false }
        return freePeriodActive
    }
}
