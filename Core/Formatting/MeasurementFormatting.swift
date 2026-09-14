import Foundation

/// Every user-visible number goes through here, so a locale change is one code path, not
/// a hundred call sites with their own `String(format:)`.
enum Fmt {
    static func distance(
        meters: Double,
        unit: DistanceUnit,
        locale: Locale,
        fractionDigits: Int = 1
    ) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: unit == .kilometers ? .kilometers : .miles)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number
                    .precision(.fractionLength(fractionDigits))
                    .locale(locale)
            )
            .locale(locale)
        )
    }

    /// The bare number, for the oversized hero figure on Home where the unit is a separate,
    /// smaller label.
    ///
    /// Delegates to `DistanceDisplay`, which lives in `Shared/` and is therefore the same
    /// code in the widget extension. Two implementations of "a distance as text" is how the
    /// driving screen and the lock screen came to disagree about the same drive.
    static func distanceValue(
        meters: Double,
        unit: DistanceUnit,
        locale: Locale,
        fractionDigits: Int = 1
    ) -> String {
        DistanceDisplay.value(meters: meters, unit: unit, locale: locale, fractionDigits: fractionDigits)
    }

    static func unitAbbreviation(_ unit: DistanceUnit, locale: Locale) -> String {
        DistanceDisplay.unitAbbreviation(unit, locale: locale)
    }

    static func money(_ amount: Decimal, currencyCode: String, locale: Locale) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    /// `00:27:42` — the running clock in trip mode. Hours are always shown so the field
    /// never changes width mid-drive.
    static func timer(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// `1 h 27 min` — a duration read at a glance, in trip lists and reports.
    static func duration(_ seconds: TimeInterval, locale: Locale) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: seconds >= 3600 ? [.hours, .minutes] : [.minutes],
            width: .abbreviated
        )
        return Duration.seconds(max(0, seconds)).formatted(style.locale(locale))
    }

    /// Up to four decimals, never two flat: an effective rate of 0.7632 shown as 0.76 makes
    /// distance × rate stop matching the amount printed beside it.
    static func rateAmount(_ rate: Decimal, currencyCode: String, locale: Locale) -> String {
        rate.formatted(
            .currency(code: currencyCode).presentation(.narrow).precision(.fractionLength(2...4)).locale(locale)
        )
    }

    static func rate(_ rate: Decimal, currencyCode: String, unit: DistanceUnit, locale: Locale) -> String {
        "\(rateAmount(rate, currencyCode: currencyCode, locale: locale))/\(unitAbbreviation(unit, locale: locale))"
    }
}

extension String {
    /// Falls back when the string is empty, so a joined address of nothing reads as "—"
    /// rather than as a blank row.
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
