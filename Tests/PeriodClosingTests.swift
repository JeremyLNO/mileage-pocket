import Foundation
import SwiftData
import XCTest
@testable import MileagePocket

/// Declaring a month finished, and noticing when it stops being what was filed.
@MainActor
final class PeriodClosingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var range: Range<Date> {
        ReportPeriod.month(year: 2026, month: 8).range(calendar: calendar)
    }

    private func trip(
        on day: Int,
        reviewed: Bool = true,
        metres: Double = 10_000,
        updatedAt: Date? = nil
    ) -> Trip {
        let startedAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 9))!
        let trip = Trip(startedAt: startedAt)
        trip.endedAt = startedAt.addingTimeInterval(1_800)
        trip.rawDistanceMeters = metres
        trip.isReviewed = reviewed
        trip.updatedAt = updatedAt ?? startedAt
        return trip
    }

    private func closed(at date: Date, distanceMeters: Double) -> ClosedPeriod {
        ClosedPeriod(
            startedAt: range.lowerBound, endedAt: range.upperBound,
            closedAt: date, distanceMeters: distanceMeters, tripCount: 1
        )
    }

    func testAPeriodWithNothingInItCannotBeClosed() {
        let status = PeriodClosing.status(trips: [], range: range, closed: nil)
        XCTAssertFalse(status.canClose, "there is nothing to file")
    }

    /// The one refusal that matters. Filing a month whose drives are still unanswered puts
    /// the default on the claim — which is exactly what the qualification queue exists to
    /// prevent, so the closing screen must not walk past it.
    func testAPeriodWithUnqualifiedTripsCannotBeClosed() {
        let status = PeriodClosing.status(
            trips: [trip(on: 3), trip(on: 4, reviewed: false)], range: range, closed: nil
        )

        XCTAssertEqual(status.unqualifiedCount, 1)
        XCTAssertFalse(status.canClose)
    }

    func testAFullyQualifiedPeriodCanBeClosed() {
        let status = PeriodClosing.status(trips: [trip(on: 3), trip(on: 4)], range: range, closed: nil)

        XCTAssertEqual(status.tripCount, 2)
        XCTAssertEqual(status.distanceMeters, 20_000)
        XCTAssertTrue(status.canClose)
    }

    /// A trip in another month is not this month's business, qualified or not.
    func testOnlyTripsInsideThePeriodCount() {
        let july = Trip(startedAt: calendar.date(from: DateComponents(year: 2026, month: 7, day: 30))!)
        july.endedAt = july.startedAt.addingTimeInterval(600)
        july.isReviewed = false

        let status = PeriodClosing.status(trips: [trip(on: 3), july], range: range, closed: nil)

        XCTAssertEqual(status.tripCount, 1)
        XCTAssertEqual(status.unqualifiedCount, 0)
        XCTAssertTrue(status.canClose)
    }

    func testAClosedPeriodSaysSoAndCannotBeClosedTwice() {
        let closedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let status = PeriodClosing.status(
            trips: [trip(on: 3)], range: range, closed: closed(at: closedAt, distanceMeters: 10_000)
        )

        XCTAssertTrue(status.isClosed)
        XCTAssertFalse(status.canClose)
        XCTAssertFalse(status.changedSinceClose)
        XCTAssertNil(status.drift)
    }

    /// Nothing forbids correcting a trip after the claim went out. What is forbidden is the
    /// app saying nothing about it: two documents that disagree, both produced here.
    func testATripEditedAfterTheCloseIsFlaggedWithItsDrift() {
        let closedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let corrected = trip(on: 3, metres: 14_000, updatedAt: closedAt.addingTimeInterval(3_600))

        let status = PeriodClosing.status(
            trips: [corrected], range: range, closed: closed(at: closedAt, distanceMeters: 10_000)
        )

        XCTAssertTrue(status.changedSinceClose)
        XCTAssertEqual(status.drift ?? 0, 4_000, accuracy: 0.1)
    }

    /// A drive remembered later is an addition, not an edit — and it moves the total just as
    /// much.
    func testATripAddedAfterTheCloseIsFlaggedToo() {
        let closedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let late = trip(on: 5, updatedAt: closedAt.addingTimeInterval(7_200))

        let status = PeriodClosing.status(
            trips: [trip(on: 3), late], range: range, closed: closed(at: closedAt, distanceMeters: 10_000)
        )

        XCTAssertTrue(status.changedSinceClose)
        XCTAssertEqual(status.drift ?? 0, 10_000, accuracy: 0.1)
    }

    // MARK: - End to end

    func testClosingRefusesUntilEverythingIsQualifiedThenRecordsWhatWasFiled() throws {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let dependencies = AppDependencies(container: container, recorderFactory: { _ in InertRecorder() })
        dependencies.bootstrap()

        let unqualified = trip(on: 4, reviewed: false)
        dependencies.context.insert(trip(on: 3))
        dependencies.context.insert(unqualified)
        try dependencies.context.save()

        XCTAssertFalse(dependencies.closePeriod(range), "a month with an unanswered drive is not filed")
        XCTAssertNil(dependencies.closedPeriod(for: range))

        dependencies.reviewTrip(unqualified, as: .business)

        XCTAssertTrue(dependencies.closePeriod(range))
        let record = try XCTUnwrap(dependencies.closedPeriod(for: range))
        XCTAssertEqual(record.tripCount, 2)
        XCTAssertEqual(record.distanceMeters, 20_000, accuracy: 0.1)

        dependencies.reopenPeriod(range)
        XCTAssertNil(dependencies.closedPeriod(for: range), "re-opening leaves no second witness behind")
    }
}
