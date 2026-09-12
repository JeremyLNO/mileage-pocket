import Foundation

/// The result of applying a rule to one trip. Everything the app needs to freeze onto the
/// `Trip` so that it never has to be recomputed — and so a report generated next year still
/// prints the rule that was actually applied.
struct MileageCalculation: Equatable, Sendable {
    let amount: Decimal
    /// The effective rate, i.e. `amount / distance` in the rule's own unit. For a tiered
    /// scheme this is the blended rate, which is what belongs in the report row.
    let rate: Decimal
    let currencyCode: String
    let ruleVersion: String
    let unit: DistanceUnit
    /// False whenever the figure comes from a user-entered rate rather than a verified
    /// official scale. The UI and the PDF both say so — an estimate is never dressed up as
    /// a regulation.
    let isOfficial: Bool

    static func zero(currencyCode: String, unit: DistanceUnit) -> MileageCalculation {
        MileageCalculation(amount: 0, rate: 0, currencyCode: currencyCode, ruleVersion: "none", unit: unit, isOfficial: false)
    }
}

protocol MileageRule: Sendable {
    var countryCode: String { get }
    var currencyCode: String { get }
    var distanceUnit: DistanceUnit { get }
    var version: String { get }
    var isOfficial: Bool { get }
    /// Human-readable description of the applied rule, printed in the report footer.
    var summary: String { get }
    var sourceURL: URL? { get }

    /// - Parameter yearlyDistanceMeters: distance already driven in the same tax year
    ///   before this trip. Tiered scales are cumulative, so a trip that straddles the
    ///   threshold has to be split across bands.
    func calculate(
        distanceMeters: Double,
        vehicle: Vehicle?,
        date: Date,
        yearlyDistanceMeters: Double
    ) -> MileageCalculation
}

/// A flat, user-defined rate. Used for the `custom` and `employer` modes, and for every
/// country with no verified official scale — which is the honest default rather than a
/// guess.
struct CustomRateRule: MileageRule {
    let countryCode: String
    let currencyCode: String
    let distanceUnit: DistanceUnit
    let ratePerUnit: Decimal
    let mode: RateMode

    var version: String { mode == .employer ? "employer" : "custom" }
    var isOfficial: Bool { false }
    var summary: String {
        mode == .employer ? "Employer rate" : "Custom rate"
    }
    var sourceURL: URL? { nil }

    func calculate(
        distanceMeters: Double,
        vehicle: Vehicle?,
        date: Date,
        yearlyDistanceMeters: Double
    ) -> MileageCalculation {
        let distance = Decimal(distanceUnit.value(fromMeters: max(0, distanceMeters)))
        let amount = MileageRounding.money(distance * ratePerUnit)
        return MileageCalculation(
            amount: amount,
            rate: ratePerUnit,
            currencyCode: currencyCode,
            ruleVersion: version,
            unit: distanceUnit,
            isOfficial: false
        )
    }
}

enum MileageRounding {
    /// Money is rounded once, at the end, to two places — never per band, which would drift
    /// a tiered calculation by a cent or two against the authority's own figure.
    static func money(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    /// Rates keep more places: 0.647 €/km is a real published figure, and rounding it to
    /// two would change every French calculation.
    static func rate(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 5, .plain)
        return result
    }
}
