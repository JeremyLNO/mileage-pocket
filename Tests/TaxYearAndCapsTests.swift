import XCTest
@testable import MileagePocket

/// When a country's allowance year opens, and what caps it. Both were missing, and both
/// produced figures that looked official and were not.
final class TaxYearAndCapsTests: XCTestCase {
    private var store: RulePackStore!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        store = RulePackStore()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// A tax year opens at midnight, not at noon — the fixture dates above are midday.
    private func midnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: date(year, month, day))
    }

    // MARK: - When the year opens

    /// HMRC's year runs 6 April to 5 April. Counting from 1 January reset the 10 000-mile
    /// allowance three months early and re-priced a whole quarter at the higher rate.
    func testBritainCountsFromTheSixthOfApril() throws {
        let pack = try XCTUnwrap(store.pack(country: "GB", on: date(2026, 9, 12)))
        XCTAssertEqual(pack.taxYearOpening.month, 4)
        XCTAssertEqual(pack.taxYearOpening.day, 6)

        let window = pack.taxYearRange(containing: date(2026, 9, 12), calendar: calendar)
        XCTAssertEqual(window.lowerBound, midnight(2026, 4, 6))
        XCTAssertEqual(window.upperBound, midnight(2027, 4, 6))
    }

    /// Tested on the bound: 5 April belongs to the previous year, 6 April opens the new one.
    func testTheBritishYearBoundaryIsTestedOnTheBound() throws {
        let pack = try XCTUnwrap(store.pack(country: "GB", on: date(2026, 9, 12)))

        let beforeOpening = pack.taxYearRange(containing: date(2026, 4, 5), calendar: calendar)
        XCTAssertEqual(beforeOpening.lowerBound, midnight(2025, 4, 6), "5 April is still last year")

        let onOpening = pack.taxYearRange(containing: date(2026, 4, 6), calendar: calendar)
        XCTAssertEqual(onOpening.lowerBound, midnight(2026, 4, 6))
    }

    func testAustraliaCountsFromTheFirstOfJuly() throws {
        let pack = try XCTUnwrap(store.pack(country: "AU", on: date(2026, 9, 12)))
        let window = pack.taxYearRange(containing: date(2026, 9, 12), calendar: calendar)
        XCTAssertEqual(window.lowerBound, midnight(2026, 7, 1))
        XCTAssertEqual(window.upperBound, midnight(2027, 7, 1))
    }

    func testEverywhereElseStillCountsFromJanuary() throws {
        for country in ["FR", "DE", "US", "CA", "ES", "NL", "PT", "IE", "BE", "CH"] {
            let pack = try XCTUnwrap(store.pack(country: country, on: date(2026, 9, 12)), country)
            XCTAssertEqual(pack.taxYearOpening.month, 1, country)
            XCTAssertEqual(pack.taxYearOpening.day, 1, country)
        }
    }

    // MARK: - Ceilings

    /// The Australian cents-per-kilometre method prices the first 5 000 km of the year and
    /// nothing beyond. Pricing on regardless overstated a 20 000 km year fourfold.
    func testAustraliaStopsAtFiveThousandKilometres() throws {
        let pack = try XCTUnwrap(store.pack(country: "AU", on: date(2026, 9, 12)))
        let rule = DeclarativeMileageRule(pack: pack)

        func amount(km: Double, alreadyDriven: Double = 0) -> Decimal {
            rule.calculate(
                distanceMeters: km * 1000, vehicle: nil,
                date: date(2026, 9, 12), yearlyDistanceMeters: alreadyDriven * 1000
            ).amount
        }

        // 5 000 km at 0.91
        XCTAssertEqual(amount(km: 5_000), Decimal(string: "4550.00"))
        // Four times as far earns exactly the same: the method stops.
        XCTAssertEqual(amount(km: 20_000), Decimal(string: "4550.00"))
        // A trip that straddles the ceiling is paid only for the part below it.
        XCTAssertEqual(amount(km: 1_000, alreadyDriven: 4_500), Decimal(string: "455.00"))
        // Entirely beyond it, nothing.
        XCTAssertEqual(amount(km: 1_000, alreadyDriven: 6_000), 0)
    }

    /// Switzerland caps the year in money rather than in distance.
    func testSwitzerlandStopsAtItsMonetaryCeiling() throws {
        let pack = try XCTUnwrap(store.pack(country: "CH", on: date(2026, 9, 12)))
        XCTAssertEqual(pack.annualCapAmount, Decimal(string: "3200"))
        let rule = DeclarativeMileageRule(pack: pack)

        func amount(km: Double, alreadyDriven: Double = 0) -> Decimal {
            rule.calculate(
                distanceMeters: km * 1000, vehicle: nil,
                date: date(2026, 9, 12), yearlyDistanceMeters: alreadyDriven * 1000
            ).amount
        }

        // 3 200 CHF is reached at 4 266.67 km (0.75/km).
        XCTAssertEqual(amount(km: 4_000), Decimal(string: "3000.00"))
        XCTAssertEqual(amount(km: 10_000), Decimal(string: "3200.00"), "the year cannot claim more")
        XCTAssertEqual(amount(km: 1_000, alreadyDriven: 10_000), 0, "once capped, later trips earn nothing")
    }

    /// A country with neither ceiling must be untouched by the machinery.
    func testACountryWithNoCeilingIsUnaffected() throws {
        let pack = try XCTUnwrap(store.pack(country: "DE", on: date(2026, 9, 12)))
        XCTAssertNil(pack.annualCapAmount)
        let rule = DeclarativeMileageRule(pack: pack)
        let result = rule.calculate(
            distanceMeters: 50_000_000, vehicle: nil,
            date: date(2026, 9, 12), yearlyDistanceMeters: 0
        )
        XCTAssertEqual(result.amount, Decimal(string: "15000.00"), "50 000 km at 0.30")
    }
}
