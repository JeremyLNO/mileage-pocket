import Foundation

/// One country as the app needs it: code, localised name, flag, and the defaults its
/// region implies.
struct CountryInfo: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let flag: String
    let currencyCode: String
    let distanceUnit: DistanceUnit

    var id: String { code }
}

/// Every country in the world, derived from ISO data rather than a hand-written list — the
/// app has to work everywhere, and a curated list is a list that will be missing someone's
/// country on launch day.
enum CountryCatalog {
    static func all(locale: Locale = .current) -> [CountryInfo] {
        Locale.Region.isoRegions
            .filter { $0.identifier.count == 2 && $0.identifier.allSatisfy(\.isLetter) }
            .filter { $0.continent != nil }
            .compactMap { info(for: $0.identifier, locale: locale) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func info(for code: String, locale: Locale = .current) -> CountryInfo? {
        let code = code.uppercased()
        guard code.count == 2, let name = locale.localizedString(forRegionCode: code) else { return nil }
        return CountryInfo(
            code: code,
            name: name,
            flag: flag(for: code),
            currencyCode: currencyCode(for: code),
            distanceUnit: distanceUnit(for: code)
        )
    }

    /// The device's own region, which is right far more often than any default we could pick.
    static func detectedCountryCode(locale: Locale = .current) -> String {
        locale.region?.identifier.uppercased() ?? "US"
    }

    static func currencyCode(for code: String) -> String {
        Locale(identifier: "en_\(code.uppercased())").currency?.identifier ?? "USD"
    }

    /// Miles where the road signs say miles — the US and the UK — kilometres elsewhere.
    static func distanceUnit(for code: String) -> DistanceUnit {
        let system = Locale(identifier: "en_\(code.uppercased())").measurementSystem
        return (system == .us || system == .uk) ? .miles : .kilometers
    }

    /// Regional-indicator flag. Purely cosmetic: every row also carries the country's name,
    /// so a font without flag glyphs loses nothing but decoration.
    static func flag(for code: String) -> String {
        let base: UInt32 = 0x1F1E6
        var result = ""
        for scalar in code.uppercased().unicodeScalars {
            guard let value = UnicodeScalar(base + scalar.value - UnicodeScalar("A").value) else { continue }
            result.unicodeScalars.append(value)
        }
        return result
    }
}
