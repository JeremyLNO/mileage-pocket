import Foundation

/// Everything a report needs, computed once and handed to both exporters, so the PDF and
/// the CSV can never disagree about a total.
struct ReportData: Sendable {
    let period: ReportPeriod
    let rows: [ReportRow]
    let businessTripCount: Int
    let personalTripCount: Int
    let totalDistanceMeters: Double
    let businessDistanceMeters: Double
    /// One total per currency. A year that crosses a border produces two, and adding them
    /// together would print a number that means nothing — the old code summed them and
    /// labelled the result with whichever currency the first trip happened to use.
    let totalsByCurrency: [(currency: String, amount: Decimal)]
    let currencyCode: String
    /// Every rule version that contributed. More than one means the scale changed inside
    /// the period, and the footer says so rather than implying a single rule applied.
    let ruleVersions: [String]

    /// The largest currency's total. Never zero just because several currencies are in play —
    /// that would have swapped one silent lie for another. Callers that print it must check
    /// `isMixedCurrency` and disclose the rest.
    var totalAmount: Decimal { totalsByCurrency.first?.amount ?? 0 }

    var isMixedCurrency: Bool { totalsByCurrency.count > 1 }

    var isEmpty: Bool { rows.isEmpty }
}

/// One printed line. Flattened away from `Trip` on purpose: rendering must not touch
/// SwiftData objects on a background thread.
struct ReportRow: Sendable, Identifiable {
    let id: UUID
    let date: Date
    let from: String
    let to: String
    let purpose: String
    let distanceMeters: Double
    let rate: Decimal?
    let amount: Decimal?
    let currencyCode: String?
    let tripType: TripType
    let isManuallyEdited: Bool
    let vehicleName: String?
}

enum ReportBuilder {
    /// - Parameter includePersonal: personal trips are excluded by default — the report
    ///   exists to justify business mileage, and a private drive on an employer's claim is
    ///   noise at best.
    static func build(
        trips: [Trip],
        period: ReportPeriod,
        includePersonal: Bool = false,
        calendar: Calendar = .current,
        vehicleNames: [UUID: String] = [:],
        fallbackCurrency: String = "EUR"
    ) -> ReportData {
        let range = period.range(calendar: calendar)
        let selected = trips
            .filter { range.contains($0.startedAt) }
            .filter { includePersonal || $0.tripType == .business }
            .sorted { $0.startedAt < $1.startedAt }

        let rows = selected.map { trip in
            ReportRow(
                id: trip.id,
                date: trip.startedAt,
                from: trip.startAddress ?? trip.startStreet ?? "—",
                to: trip.endAddress ?? trip.endStreet ?? "—",
                purpose: trip.purpose ?? "",
                distanceMeters: trip.distanceMeters,
                rate: trip.mileageRate,
                amount: trip.calculatedAmount,
                currencyCode: trip.currencyCode,
                tripType: trip.tripType,
                isManuallyEdited: trip.isManuallyEdited,
                vehicleName: trip.vehicleID.flatMap { vehicleNames[$0] }
            )
        }

        let businessRows = rows.filter { $0.tripType == .business }
        var byCurrency: [String: Decimal] = [:]
        for row in rows {
            guard let amount = row.amount, amount != 0 else { continue }
            byCurrency[row.currencyCode ?? fallbackCurrency, default: 0] += amount
        }
        let totals = byCurrency
            .map { (currency: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }

        return ReportData(
            period: period,
            rows: rows,
            businessTripCount: businessRows.count,
            personalTripCount: rows.count - businessRows.count,
            totalDistanceMeters: rows.reduce(0) { $0 + $1.distanceMeters },
            businessDistanceMeters: businessRows.reduce(0) { $0 + $1.distanceMeters },
            totalsByCurrency: totals,
            currencyCode: totals.first?.currency ?? fallbackCurrency,
            ruleVersions: Array(Set(selected.compactMap(\.mileageRuleVersion))).sorted()
        )
    }

    /// Distance already driven in the trip's tax year *before* it, which tiered scales need.
    ///
    /// The window is passed in rather than assumed to be the calendar year: Britain's opens
    /// on 6 April and Australia's on 1 July, and counting from 1 January reset the British
    /// 10 000-mile allowance three months early — re-pricing a whole quarter at the higher
    /// rate and calling it official.
    ///
    /// Personal trips are excluded: they consume no allowance.
    static func yearlyDistanceMeters(
        before trip: Trip,
        in trips: [Trip],
        window: Range<Date>
    ) -> Double {
        trips
            .filter { $0.id != trip.id }
            .filter { $0.tripType == .business }
            .filter { window.contains($0.startedAt) }
            .filter { $0.startedAt < trip.startedAt }
            .reduce(0) { $0 + $1.distanceMeters }
    }
}
