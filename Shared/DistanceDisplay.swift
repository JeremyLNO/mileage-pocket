import Foundation

/// The one place a distance becomes text.
///
/// It lives in `Shared/` because the app and the widget extension are two processes that
/// must spell the same number the same way. They did not: the app formatted with
/// `.number.precision(...)`, which follows the user's locale, and the Live Activity used
/// `String(format: "%.1f")`, which always writes a dot and rounds by its own rules. On a
/// French phone the driving screen said `1,6 km` while the lock screen — and CarPlay, which
/// shows the same Live Activity — said `1.6 km`.
///
/// Two spellings of one measurement is a small thing that reads as a large one: a driver
/// comparing the two screens concludes that one of them is wrong, and they are right.
enum DistanceDisplay {
    /// The number alone, in the user's unit and locale.
    static func value(meters: Double, unit: DistanceUnit, locale: Locale, fractionDigits: Int = 1) -> String {
        unit.value(fromMeters: meters)
            .formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// "km" / "mi", as the locale abbreviates them.
    static func unitAbbreviation(_ unit: DistanceUnit, locale: Locale) -> String {
        let measurement = Measurement(value: 1, unit: unit == .kilometers ? UnitLength.kilometers : UnitLength.miles)
        let formatted = measurement.formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
        return formatted.replacingOccurrences(of: "1", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Number and unit together, for the surfaces that show one string.
    static func text(meters: Double, unit: DistanceUnit, locale: Locale) -> String {
        "\(value(meters: meters, unit: unit, locale: locale)) \(unitAbbreviation(unit, locale: locale))"
    }
}
