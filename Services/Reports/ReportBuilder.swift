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
    let totalAmount: Decimal
    let currencyCode: String
    /// Every rule version that contributed. More than one means the scale changed inside
    /// the period, and the footer says so rather than implying a single rule applied.
    let ruleVersions: [String]

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
                from: trip.startAddress ?? "—",
                to: trip.endAddress ?? "—",
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
        let total = rows.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }

        return ReportData(
            period: period,
            rows: rows,
            businessTripCount: businessRows.count,
            personalTripCount: rows.count - businessRows.count,
            totalDistanceMeters: rows.reduce(0) { $0 + $1.distanceMeters },
            businessDistanceMeters: businessRows.reduce(0) { $0 + $1.distanceMeters },
            totalAmount: total,
            currencyCode: rows.compactMap(\.currencyCode).first ?? fallbackCurrency,
            ruleVersions: Array(Set(selected.compactMap(\.mileageRuleVersion))).sorted()
        )
    }

    /// Distance already driven in the trip's tax year *before* it, which tiered scales need.
    /// Personal trips are excluded: they do not consume an allowance.
    static func yearlyDistanceMeters(
        before trip: Trip,
        in trips: [Trip],
        calendar: Calendar = .current
    ) -> Double {
        let year = ReportPeriod.taxYear(of: trip.startedAt, calendar: calendar)
        return trips
            .filter { $0.id != trip.id }
            .filter { $0.tripType == .business }
            .filter { ReportPeriod.taxYear(of: $0.startedAt, calendar: calendar) == year }
            .filter { $0.startedAt < trip.startedAt }
            .reduce(0) { $0 + $1.distanceMeters }
    }
}
