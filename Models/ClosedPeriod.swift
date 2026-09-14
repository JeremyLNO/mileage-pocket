import Foundation
import SwiftData

/// A period the user has declared finished, with what it was worth at that moment.
///
/// Closing is not a lock — nothing in this app stops someone correcting a trip, and an app
/// that refused would be lying about who owns the record. It is a **witness**: the totals as
/// they stood when the claim was filed, so that a figure changing afterwards is visible
/// instead of silent. Filing a report and then editing a trip inside it is how two documents
/// that disagree end up in front of an accountant, each of them produced by this app.
///
/// Every property is optional or defaulted and nothing is `.unique`: CloudKit rejects a
/// SwiftData schema that has either, and the store then fails to open at launch.
@Model
final class ClosedPeriod {
    var id: UUID = UUID()
    /// The period, stored as its own bounds rather than as a month number: a quarter and a
    /// year close the same way, and a range is what every comparison needs anyway.
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var closedAt: Date = Date()

    /// What the period was worth when it was closed.
    var distanceMeters: Double = 0
    var amount: Decimal?
    var currencyCode: String?
    var tripCount: Int = 0

    init(
        startedAt: Date,
        endedAt: Date,
        closedAt: Date = .now,
        distanceMeters: Double = 0,
        amount: Decimal? = nil,
        currencyCode: String? = nil,
        tripCount: Int = 0
    ) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.closedAt = closedAt
        self.distanceMeters = distanceMeters
        self.amount = amount
        self.currencyCode = currencyCode
        self.tripCount = tripCount
    }

    func covers(_ range: Range<Date>) -> Bool {
        startedAt == range.lowerBound && endedAt == range.upperBound
    }
}
