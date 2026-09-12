import Foundation

/// RFC 4180 CSV.
///
/// A purpose field is free text, so it can and will contain a comma, a quote or a line
/// break. Every field is quoted and every embedded quote doubled — a spreadsheet that
/// mis-parses one row silently shifts every column after it.
enum CSVExporter {
    static let columnCount = 7

    static func csv(_ data: ReportData, profile: ReportProfile) -> String {
        let header = ["Date", "From", "To", "Purpose", "Distance (\(unitLabel(profile.unit)))", "Rate", "Amount"]
        var lines = [row(header)]

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        for entry in data.rows {
            lines.append(row([
                dateFormatter.string(from: entry.date),
                entry.from,
                entry.to,
                entry.purpose,
                decimalString(profile.unit.value(fromMeters: entry.distanceMeters), places: 1),
                entry.rate.map { rateString($0) } ?? "",
                entry.amount.map { plain($0) } ?? "",
            ]))
        }

        lines.append(row([
            "TOTAL",
            "",
            "",
            "\(data.businessTripCount) business trips",
            decimalString(profile.unit.value(fromMeters: data.totalDistanceMeters), places: 1),
            "",
            plain(data.totalAmount),
        ]))

        // CRLF is what RFC 4180 specifies, and what Excel on Windows expects.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func write(_ csv: String, to url: URL) throws {
        // The BOM is what makes Excel read the file as UTF-8 instead of the local codepage,
        // which is the difference between "Café client" and "CafÃ© client".
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        try data.write(to: url, options: .atomic)
    }

    static func fileName(for data: ReportData, locale: Locale) -> String {
        let title = data.period.title(locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "-")
        return "MileageReport-\(title).csv"
    }

    // MARK: - Field encoding

    private static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    private static func escape(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Machine-readable numbers: always a dot, never a locale separator. A CSV opened in
    /// another country must still parse.
    private static func decimalString(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    /// Always two decimals, always a dot. `NSDecimalNumber.description` drops trailing
    /// zeros, so a total of 20 euros came out as "20" — which reads as a different figure in
    /// a column of amounts.
    private static func plain(_ value: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }

    /// Rates keep up to four decimals. Two is not enough: France's electric uplift gives
    /// 0.7632 €/km, and printing it as "0.76" makes every row fail to reconcile — distance ×
    /// rate no longer equals the amount, which is the first thing an accountant checks.
    private static func rateString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? plain(value)
    }

    private static func unitLabel(_ unit: DistanceUnit) -> String {
        unit == .kilometers ? "km" : "mi"
    }
}
