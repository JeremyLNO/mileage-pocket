import CoreLocation
import Foundation
import SwiftData
import XCTest
@testable import MileagePocket

/// The figures the home screen shows.
///
/// None of them is hard to compute and every one of them is easy to get subtly wrong in a
/// way nobody notices: a day boundary off by an hour, a personal trip counted as claimable,
/// a rate printed under a total it does not produce. A widget is read at a glance and
/// believed — there is no screen behind it where the reader checks the arithmetic.
@MainActor
final class WidgetFiguresTests: XCTestCase {
    /// A Wednesday inside the bundled rule pack's validity window, at midday, so that
    /// "yesterday" is a full day and no test depends on when it was run.
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private var calendar = Calendar(identifier: .gregorian)

    private struct Rig {
        let dependencies: AppDependencies
    }

    private func makeRig() throws -> Rig {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let dependencies = AppDependencies(container: container)
        dependencies.bootstrap()
        return Rig(dependencies: dependencies)
    }

    private func trip(
        at date: Date,
        meters: Double,
        type: TripType = .business,
        finished: Bool = true,
        rate: Decimal? = nil
    ) -> Trip {
        let trip = Trip(startedAt: date)
        if finished { trip.endedAt = date.addingTimeInterval(1_800) }
        trip.rawDistanceMeters = meters
        trip.tripType = type
        trip.isReviewed = true
        trip.mileageRate = rate
        trip.mileageUnit = .kilometers
        trip.currencyCode = "EUR"
        return trip
    }

    // MARK: - The day

    func testTodayCountsEveryDriveOfTheDayAndOnlyThoseOfTheDay() throws {
        let rig = try makeRig()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let figures = rig.dependencies.widgetFigures(
            from: [
                trip(at: now, meters: 12_000),
                // Personal, and it still counts: the day's figure is what was driven, not
                // what can be claimed. That is what the split bar under the month is for.
                trip(at: now.addingTimeInterval(-3_600), meters: 8_000, type: .personal),
                trip(at: yesterday, meters: 40_000),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(figures.todayDistanceMeters, 20_000)
        XCTAssertEqual(figures.yesterdayDistanceMeters, 40_000)
    }

    /// A drive in progress is not part of any figure. Its distance is moving and the snapshot
    /// is written only when something happens, so counting it puts a number on the home
    /// screen that was true for a moment — and the drive already has a face of its own.
    func testADriveStillRunningIsLeftOutOfTheDay() throws {
        let rig = try makeRig()
        let figures = rig.dependencies.widgetFigures(
            from: [
                trip(at: now, meters: 12_000),
                trip(at: now, meters: 99_000, finished: false),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(figures.todayDistanceMeters, 12_000)
    }

    // MARK: - The month

    func testTheMonthIsSplitBetweenWorkAndPrivateLife() throws {
        let rig = try makeRig()
        let earlier = calendar.date(byAdding: .day, value: -6, to: now)!
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        let figures = rig.dependencies.widgetFigures(
            from: [
                trip(at: now, meters: 60_000, type: .business),
                trip(at: earlier, meters: 12_000, type: .business),
                trip(at: earlier, meters: 28_000, type: .personal),
                trip(at: lastMonth, meters: 500_000, type: .business),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(figures.monthBusinessMeters, 72_000)
        XCTAssertEqual(figures.monthPersonalMeters, 28_000)
        XCTAssertEqual(figures.monthTotalMeters, 100_000)
        XCTAssertEqual(figures.monthTripCount, 3, "last month's drive is not this month's")
        XCTAssertEqual(try XCTUnwrap(figures.businessShare), 0.72, accuracy: 0.0001)
    }

    // MARK: - The rate

    /// France prices by tranches and by fiscal horsepower, Ireland by bands. Where the scale
    /// moves, no single rate times the month's distance gives the month's total — and
    /// printing one under that total invites the reader to check an arithmetic that was never
    /// performed.
    func testARateIsShownOnlyWhenOneRateReallyAppliesToTheWholeMonth() throws {
        let rig = try makeRig()

        let oneRate = rig.dependencies.widgetFigures(
            from: [trip(at: now, meters: 10_000, rate: 0.529), trip(at: now, meters: 20_000, rate: 0.529)],
            now: now, calendar: calendar
        )
        XCTAssertNotNil(oneRate.formattedRate)
        XCTAssertTrue(try XCTUnwrap(oneRate.formattedRate).contains("km"))

        let twoRates = rig.dependencies.widgetFigures(
            from: [trip(at: now, meters: 10_000, rate: 0.529), trip(at: now, meters: 20_000, rate: 0.316)],
            now: now, calendar: calendar
        )
        XCTAssertNil(twoRates.formattedRate, "a tiered scale has no single rate to print")

        let noRate = rig.dependencies.widgetFigures(
            from: [trip(at: now, meters: 10_000, rate: nil)],
            now: now, calendar: calendar
        )
        XCTAssertNil(noRate.formattedRate)
    }

    /// Zero is not a rate, it is the absence of one — and the two have to be told apart.
    ///
    /// The first version of this test put a *personal* trip in the month and claimed its
    /// zero rate could hide the real one. It could not: only business trips are ever looked
    /// at, so the test passed with the guard removed and proved nothing. A business trip
    /// carrying a zero rate is the case that exists — a trip priced before a rule pack
    /// covered it, or reclassified — and without the guard the widget prints
    /// "Based on €0.00/km" under a total of four hundred euros.
    func testAZeroRateIsNotTreatedAsARate() throws {
        let rig = try makeRig()

        let alongsideAReal = rig.dependencies.widgetFigures(
            from: [
                trip(at: now, meters: 10_000, type: .business, rate: 0.529),
                trip(at: now, meters: 10_000, type: .business, rate: 0),
            ],
            now: now, calendar: calendar
        )
        XCTAssertEqual(alongsideAReal.formattedRate?.contains("0.529"), true,
                       "a zero must not read as a second rate and suppress the real one")

        let onItsOwn = rig.dependencies.widgetFigures(
            from: [trip(at: now, meters: 10_000, type: .business, rate: 0)],
            now: now, calendar: calendar
        )
        XCTAssertNil(onItsOwn.formattedRate, "\"Based on €0.00/km\" is not information")
    }

    // MARK: - The last drive

    func testTheLastDriveIsTheMostRecentFinishedOne() throws {
        let rig = try makeRig()
        let older = trip(at: calendar.date(byAdding: .day, value: -2, to: now)!, meters: 10_000)
        let newest = trip(at: now, meters: 58_000)
        newest.startAddress = "Paris"
        newest.endAddress = "Orly"
        let running = trip(at: now.addingTimeInterval(3_600), meters: 1_000, finished: false)

        let figures = rig.dependencies.widgetFigures(from: [older, newest, running], now: now, calendar: calendar)

        let last = try XCTUnwrap(figures.lastTrip)
        XCTAssertEqual(last.start, "Paris")
        XCTAssertEqual(last.end, "Orly")
        XCTAssertTrue(last.isBusiness)
        XCTAssertFalse(last.distanceText.isEmpty)
        XCTAssertFalse(last.durationText.isEmpty)
    }

    func testWithNoDrivesAtAllNothingIsInvented() throws {
        let rig = try makeRig()
        let figures = rig.dependencies.widgetFigures(from: [], now: now, calendar: calendar)

        XCTAssertEqual(figures.todayDistanceMeters, 0)
        XCTAssertEqual(figures.monthTripCount, 0)
        XCTAssertNil(figures.businessShare, "a bar drawn from no data is a bar that says something")
        XCTAssertNil(figures.dayChange)
        XCTAssertNil(figures.lastTrip)
    }
}

/// The two derived figures, which have nothing to do with the store and everything to do
/// with not printing nonsense.
final class WidgetFiguresArithmeticTests: XCTestCase {
    private func figures(today: Double, yesterday: Double) -> WidgetFigures {
        WidgetFigures(
            todayDistanceMeters: today,
            yesterdayDistanceMeters: yesterday,
            monthBusinessMeters: 0,
            monthPersonalMeters: 0,
            monthTripCount: 0,
            formattedRate: nil,
            lastTrip: nil
        )
    }

    func testTheDayOnDayChangeIsAFraction() throws {
        XCTAssertEqual(try XCTUnwrap(figures(today: 112, yesterday: 100).dayChange), 0.12, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(figures(today: 50, yesterday: 100).dayChange), -0.5, accuracy: 0.0001)
    }

    /// A first drive after a day off is not a hundred per cent of anything, and it is
    /// certainly not infinite. The honest thing to draw is nothing at all.
    func testAfterADayWithNoDrivingThereIsNothingToCompareAgainst() {
        XCTAssertNil(figures(today: 42_000, yesterday: 0).dayChange)
        XCTAssertNil(figures(today: 0, yesterday: 0).dayChange)
    }
}
