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
    static func distanceValue(
        meters: Double,
        unit: DistanceUnit,
        locale: Locale,
        fractionDigits: Int = 1
    ) -> String {
        let value = unit.value(fromMeters: meters)
        return value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    static func unitAbbreviation(_ unit: DistanceUnit, locale: Locale) -> String {
        let measurement = Measurement(value: 1, unit: unit == .kilometers ? UnitLength.kilometers : UnitLength.miles)
        let formatted = measurement.formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
        return formatted.replacingOccurrences(of: "1", with: "").trimmingCharacters(in: .whitespaces)
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

    static func rate(_ rate: Decimal, currencyCode: String, unit: DistanceUnit, locale: Locale) -> String {
        let amount = rate.formatted(
            .currency(code: currencyCode).presentation(.narrow).precision(.fractionLength(2...3)).locale(locale)
        )
        return "\(amount)/\(unitAbbreviation(unit, locale: locale))"
    }
}
