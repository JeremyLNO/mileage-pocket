import Foundation

/// Turns "which country, which mode, which date" into the rule to apply.
///
/// The one rule that matters here: asking for the official rate in a country with no
/// verified pack does not produce an invented figure — it produces the custom rule, and the
/// UI says so.
final class CountryRuleEngine: Sendable {
    private let store: RulePackStore

    init(store: RulePackStore) {
        self.store = store
    }

    func hasOfficialRule(for countryCode: String, on date: Date = .now) -> Bool {
        store.pack(country: countryCode, on: date) != nil
    }

    func availableCountries() -> Set<String> { store.availableCountries() }

    func officialPack(for countryCode: String, on date: Date = .now) -> RulePack? {
        store.pack(country: countryCode, on: date)
    }

    /// The exact version a trip was saved under, so its arithmetic can be re-run without
    /// moving it onto a newer scale.
    func pack(country: String, version: String) -> RulePack? {
        store.pack(country: country, version: version)
    }

    func hasCumulativeScale(country: String) -> Bool {
        store.hasCumulativePack(country: country)
    }

    func rule(
        countryCode: String,
        mode: RateMode,
        customRate: Decimal?,
        customCurrency: String?,
        unit: DistanceUnit,
        date: Date = .now
    ) -> MileageRule {
        if mode == .official, let pack = store.pack(country: countryCode, on: date) {
            return DeclarativeMileageRule(pack: pack)
        }
        // Falls through for: an explicitly chosen custom/employer rate, and for a country
        // with no official scale — where inventing one would be worse than asking the user.
        return CustomRateRule(
            countryCode: countryCode.uppercased(),
            currencyCode: customCurrency ?? store.pack(country: countryCode, on: date)?.currencyCode ?? "EUR",
            distanceUnit: unit,
            ratePerUnit: customRate ?? 0,
            mode: mode == .employer ? .employer : .custom
        )
    }

    /// The mode that will actually be used, which is what Settings should display: asking
    /// for `official` where none exists really means `custom`.
    func effectiveMode(requested: RateMode, countryCode: String, on date: Date = .now) -> RateMode {
        if requested == .official && !hasOfficialRule(for: countryCode, on: date) {
            return .custom
        }
        return requested
    }
}
