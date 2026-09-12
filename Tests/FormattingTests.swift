import XCTest
@testable import MileagePocket

final class FormattingTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let frFR = Locale(identifier: "fr_FR")

    func testKilometresUseOneDecimal() {
        XCTAssertEqual(Fmt.distance(meters: 24_300, unit: .kilometers, locale: enUS), "24.3 km")
    }

    func testMilesConvertFromMetres() {
        XCTAssertEqual(Fmt.distance(meters: 24_300, unit: .miles, locale: enUS), "15.1 mi")
    }

    func testFrenchUsesACommaDecimalSeparator() {
        // Asserted by parts: French inserts a narrow no-break space (U+202F) before the
        // unit, which an equality check against a typed space fails on invisibly.
        let formatted = Fmt.distance(meters: 24_300, unit: .kilometers, locale: frFR)
        XCTAssertTrue(formatted.hasPrefix("24,3"), formatted)
        XCTAssertTrue(formatted.hasSuffix("km"), formatted)
    }

    func testDistanceValueOmitsTheUnit() {
        XCTAssertEqual(Fmt.distanceValue(meters: 486_000, unit: .kilometers, locale: enUS, fractionDigits: 0), "486")
    }

    func testTimerAlwaysShowsHoursMinutesSeconds() {
        XCTAssertEqual(Fmt.timer(1662), "00:27:42")
        XCTAssertEqual(Fmt.timer(0), "00:00:00")
        XCTAssertEqual(Fmt.timer(3661), "01:01:01")
        XCTAssertEqual(Fmt.timer(-5), "00:00:00", "a negative interval must not render a negative clock")
    }

    func testMoneyUsesTheGivenCurrencyAndLocale() {
        let french = Fmt.money(Decimal(string: "15.73")!, currencyCode: "EUR", locale: frFR)
        XCTAssertTrue(french.contains("15,73"), french)
        XCTAssertTrue(french.contains("€"), french)

        let american = Fmt.money(Decimal(string: "15.73")!, currencyCode: "USD", locale: enUS)
        XCTAssertTrue(american.contains("$15.73"), american)
    }

    func testRateShowsAmountPerUnit() {
        let rate = Fmt.rate(Decimal(string: "0.45")!, currencyCode: "GBP", unit: .miles, locale: Locale(identifier: "en_GB"))
        XCTAssertTrue(rate.contains("0.45"), rate)
        XCTAssertTrue(rate.hasSuffix("/mi"), rate)
    }
}
