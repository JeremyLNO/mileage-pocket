import PDFKit
import SwiftData
import XCTest
@testable import MileagePocket

/// Two ways a report used to print a number that meant nothing.
final class CurrencyAndUnitTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    private func trip(_ start: Date, km: Double, amount: String, currency: String) -> Trip {
        let trip = Trip(startedAt: start)
        trip.endedAt = start.addingTimeInterval(1800)
        trip.rawDistanceMeters = km * 1000
        trip.tripType = .business
        trip.startAddress = "A"
        trip.endAddress = "B"
        trip.currencyCode = currency
        trip.mileageRate = Decimal(string: "0.30")
        trip.calculatedAmount = Decimal(string: amount)
        trip.mileageRuleVersion = "2026.1"
        return trip
    }

    private var profile: ReportProfile {
        ReportProfile(
            userName: "Jane Doe", companyName: nil, vehicleLabel: nil,
            countryCode: "FR", countryName: "France",
            ruleDescription: "Official mileage scale", ruleVersion: "2026.1",
            ruleSourceURL: nil, isOfficialRate: true,
            unit: .kilometers, locale: Locale(identifier: "en_US")
        )
    }

    // MARK: - Currencies

    /// Someone who moves from the United States to France mid-year had their dollars and
    /// euros added together and the result labelled with whichever came first.
    func testEachCurrencyIsTotalledSeparately() {
        let trips = [
            trip(date(2026, 3, 1), km: 100, amount: "76.00", currency: "USD"),
            trip(date(2026, 5, 1), km: 100, amount: "53.00", currency: "EUR"),
            trip(date(2026, 6, 1), km: 100, amount: "53.00", currency: "EUR"),
        ]
        let data = ReportBuilder.build(trips: trips, period: .year(2026), calendar: calendar)

        XCTAssertTrue(data.isMixedCurrency)
        XCTAssertEqual(data.totalsByCurrency.count, 2)
        // Sorted by size: euros lead.
        XCTAssertEqual(data.totalsByCurrency[0].currency, "EUR")
        XCTAssertEqual(data.totalsByCurrency[0].amount, Decimal(string: "106.00"))
        XCTAssertEqual(data.totalsByCurrency[1].currency, "USD")
        XCTAssertEqual(data.totalsByCurrency[1].amount, Decimal(string: "76.00"))
    }

    /// A single currency must stay perfectly ordinary — no disclosure, one total.
    func testASingleCurrencyIsNotReportedAsMixed() {
        let data = ReportBuilder.build(
            trips: [trip(date(2026, 5, 1), km: 100, amount: "53.00", currency: "EUR")],
            period: .year(2026), calendar: calendar
        )
        XCTAssertFalse(data.isMixedCurrency)
        XCTAssertEqual(data.totalAmount, Decimal(string: "53.00"))
        XCTAssertEqual(data.currencyCode, "EUR")
    }

    /// The total must never be zero merely because two currencies are present — that would
    /// swap one silent lie for another.
    func testAMixedTotalIsNeverZero() {
        let trips = [
            trip(date(2026, 3, 1), km: 100, amount: "76.00", currency: "USD"),
            trip(date(2026, 5, 1), km: 100, amount: "53.00", currency: "EUR"),
        ]
        let data = ReportBuilder.build(trips: trips, period: .year(2026), calendar: calendar)
        XCTAssertGreaterThan(data.totalAmount, 0)
    }

    func testTheCSVCarriesACurrencyColumnAndOneTotalPerCurrency() {
        let trips = [
            trip(date(2026, 3, 1), km: 100, amount: "76.00", currency: "USD"),
            trip(date(2026, 5, 1), km: 100, amount: "53.00", currency: "EUR"),
        ]
        let data = ReportBuilder.build(trips: trips, period: .year(2026), calendar: calendar)
        let csv = CSVExporter.csv(data, profile: profile)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines[0].components(separatedBy: "\",\"").count, CSVExporter.columnCount)
        XCTAssertTrue(lines[0].hasSuffix("\"Currency\""), lines[0])
        let totals = lines.filter { $0.hasPrefix("\"TOTAL\"") }
        XCTAssertEqual(totals.count, 2, "one totals line per currency")
        XCTAssertTrue(totals.contains { $0.contains("\"EUR\"") })
        XCTAssertTrue(totals.contains { $0.contains("\"USD\"") })
    }

    func testThePDFDisclosesThatCurrenciesWereNotAdded() throws {
        let trips = [
            trip(date(2026, 3, 1), km: 100, amount: "76.00", currency: "USD"),
            trip(date(2026, 5, 1), km: 100, amount: "53.00", currency: "EUR"),
        ]
        let data = ReportBuilder.build(trips: trips, period: .year(2026), calendar: calendar)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mixed-\(UUID().uuidString).pdf")
        _ = try PDFReportRenderer().render(data, profile: profile, to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let document = try XCTUnwrap(PDFDocument(url: url))
        let raw = try XCTUnwrap(document.page(at: document.pageCount - 1)?.string)
        // Whitespace is collapsed before matching: the renderer wraps, so a phrase that sits
        // on one line in the source can be split across two in the extracted text.
        let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        XCTAssertTrue(text.contains("more than one currency"), raw)
        XCTAssertTrue(text.contains("not added together"), raw)
        XCTAssertTrue(text.contains("$76.00 + €53.00"), "both totals must be printed, unsummed")
    }

    // MARK: - The frozen unit

    /// The rate is frozen in the unit the scale uses. Correcting a distance while Settings
    /// happened to display miles re-applied a per-kilometre rate to a mileage figure.
    func testCorrectingADistanceUsesTheRatesOwnUnitNotTheDisplayUnit() throws {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let context = ModelContext(container)

        let trip = Trip(startedAt: date(2026, 5, 1))
        trip.rawDistanceMeters = 100_000
        trip.tripType = .business
        trip.mileageRate = Decimal(string: "0.50")
        trip.mileageUnit = .kilometers
        context.insert(trip)

        // 100 km at 0.50/km is 50. Read as miles it would be 62.14 miles × 0.50 = 31.07.
        let kilometres = Decimal(DistanceUnit.kilometers.value(fromMeters: trip.distanceMeters))
        XCTAssertEqual(MileageRounding.money(kilometres * Decimal(string: "0.50")!), Decimal(string: "50.00"))

        let unit = try XCTUnwrap(trip.mileageUnit)
        XCTAssertEqual(unit, .kilometers, "the unit travels with the rate, not with Settings")
    }
}
