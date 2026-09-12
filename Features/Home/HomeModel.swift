import Foundation
import Observation
import SwiftData

/// The month's figures, recomputed from the store rather than kept as a running total —
/// editing or deleting an old trip has to move the headline number, and a cached counter is
/// how that quietly stops happening.
@Observable
@MainActor
final class HomeModel {
    private(set) var monthDistanceMeters: Double = 0
    private(set) var monthAmount: Decimal = 0
    private(set) var businessTripCount: Int = 0
    private(set) var lastTrip: Trip?
    private(set) var currencyCode: String = "EUR"

    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    var monthTitle: String {
        Date.now.formatted(.dateTime.month(.wide))
    }

    func refresh(settings: UserSettings) {
        currencyCode = settings.currencyCode
        let trips = (try? context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []

        let period = ReportPeriod.current(calendar: calendar)
        let data = ReportBuilder.build(trips: trips, period: period, calendar: calendar, fallbackCurrency: settings.currencyCode)

        monthDistanceMeters = data.totalDistanceMeters
        monthAmount = data.totalAmount
        businessTripCount = data.businessTripCount
        lastTrip = trips.first { $0.endedAt != nil }
    }
}
