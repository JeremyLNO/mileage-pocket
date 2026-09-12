import XCTest
import PDFKit
@testable import MileagePocket

final class ReportTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func trip(
        _ start: Date,
        km: Double,
        type: TripType = .business,
        amount: String? = "10.00",
        purpose: String = "Client visit",
        version: String = "2026.1"
    ) -> Trip {
        let trip = Trip(startedAt: start)
        trip.endedAt = start.addingTimeInterval(1800)
        trip.rawDistanceMeters = km * 1000
        trip.tripType = type
        trip.purpose = purpose
        trip.startAddress = "Paris"
        trip.endAddress = "Versailles"
        trip.currencyCode = "EUR"
        trip.mileageRate = Decimal(string: "0.45")
        trip.calculatedAmount = amount.flatMap { Decimal(string: $0) }
        trip.mileageRuleVersion = version
        return trip
    }

    private var profile: ReportProfile {
        ReportProfile(
            userName: "Jane Doe",
            companyName: "Doe Consulting",
            vehicleLabel: "Tesla Model 3",
            countryCode: "FR",
            countryName: "France",
            ruleDescription: "Official mileage scale",
            ruleVersion: "2026.1",
            ruleSourceURL: URL(string: "https://www.impots.gouv.fr/bareme-kilometrique"),
            isOfficialRate: true,
            unit: .kilometers,
            locale: Locale(identifier: "en_US")
        )
    }

    // MARK: - Totals

    func testPersonalTripsAreExcludedByDefault() {
        let trips = [
            trip(date(2026, 9, 1), km: 10),
            trip(date(2026, 9, 2), km: 20),
            trip(date(2026, 9, 3), km: 30),
            trip(date(2026, 9, 4), km: 40, type: .personal),
            trip(date(2026, 9, 5), km: 50, type: .personal),
        ]
        let data = ReportBuilder.build(trips: trips, period: .month(year: 2026, month: 9), calendar: calendar)
        XCTAssertEqual(data.businessTripCount, 3)
        XCTAssertEqual(data.personalTripCount, 0)
        XCTAssertEqual(data.totalDistanceMeters, 60_000, accuracy: 0.001)
        XCTAssertEqual(data.totalAmount, Decimal(string: "30.00"))
    }

    func testPersonalTripsAreIncludedOnRequest() {
        let trips = [trip(date(2026, 9, 1), km: 10), trip(date(2026, 9, 4), km: 40, type: .personal)]
        let data = ReportBuilder.build(trips: trips, period: .month(year: 2026, month: 9), includePersonal: true, calendar: calendar)
        XCTAssertEqual(data.rows.count, 2)
        XCTAssertEqual(data.businessTripCount, 1)
        XCTAssertEqual(data.personalTripCount, 1)
        XCTAssertEqual(data.businessDistanceMeters, 10_000, accuracy: 0.001)
    }

    func testTripsOutsideThePeriodAreLeftOut() {
        let trips = [
            trip(date(2026, 8, 31, 23, 59), km: 10),
            trip(date(2026, 9, 1, 0, 1), km: 20),
            trip(date(2026, 10, 1, 0, 1), km: 30),
        ]
        let data = ReportBuilder.build(trips: trips, period: .month(year: 2026, month: 9), calendar: calendar)
        XCTAssertEqual(data.rows.count, 1)
        XCTAssertEqual(data.totalDistanceMeters, 20_000, accuracy: 0.001)
    }

    /// A drive that starts on 31 December and ends on 1 January belongs to the year it began
    /// in, and is counted exactly once.
    func testATripCrossingNewYearIsCountedOnceInItsStartingYear() {
        let newYearTrip = trip(date(2025, 12, 31, 23, 50), km: 30)
        newYearTrip.endedAt = date(2026, 1, 1, 0, 20)

        let previousYear = ReportBuilder.build(trips: [newYearTrip], period: .year(2025), calendar: calendar)
        let nextYear = ReportBuilder.build(trips: [newYearTrip], period: .year(2026), calendar: calendar)

        XCTAssertEqual(previousYear.rows.count, 1)
        XCTAssertEqual(nextYear.rows.count, 0)
    }

    func testQuarterCoversItsThreeMonthsAndNothingElse() {
        let trips = [
            trip(date(2026, 6, 30), km: 10),
            trip(date(2026, 7, 1), km: 20),
            trip(date(2026, 9, 30, 23, 30), km: 30),
            trip(date(2026, 10, 1), km: 40),
        ]
        let data = ReportBuilder.build(trips: trips, period: .quarter(year: 2026, quarter: 3), calendar: calendar)
        XCTAssertEqual(data.rows.count, 2)
        XCTAssertEqual(data.totalDistanceMeters, 50_000, accuracy: 0.001)
    }

    func testCustomPeriodIncludesBothEndDaysInFull() {
        let trips = [
            trip(date(2026, 9, 10, 0, 5), km: 10),
            trip(date(2026, 9, 12, 23, 55), km: 20),
            trip(date(2026, 9, 13, 0, 5), km: 30),
        ]
        let period = ReportPeriod.custom(start: date(2026, 9, 10, 12), end: date(2026, 9, 12, 8))
        let data = ReportBuilder.build(trips: trips, period: period, calendar: calendar)
        XCTAssertEqual(data.rows.count, 2, "both boundary days count as whole days")
    }

    func testYearlyDistanceBeforeATripCountsOnlyEarlierBusinessTripsOfTheSameYear() {
        let target = trip(date(2026, 6, 1), km: 100)
        let trips = [
            trip(date(2026, 1, 1), km: 500),
            trip(date(2026, 2, 1), km: 300, type: .personal),
            trip(date(2025, 12, 1), km: 900),
            trip(date(2026, 12, 1), km: 700),
            target,
        ]
        let before = ReportBuilder.yearlyDistanceMeters(before: target, in: trips, calendar: calendar)
        XCTAssertEqual(before, 500_000, accuracy: 0.001)
    }

    // MARK: - CSV

    func testCSVEscapesQuotesCommasAndNewlines() {
        let awkward = trip(date(2026, 9, 1), km: 10, purpose: "Meeting, \"urgent\"\nwith legal")
        let data = ReportBuilder.build(trips: [awkward], period: .month(year: 2026, month: 9), calendar: calendar)
        let csv = CSVExporter.csv(data, profile: profile)

        XCTAssertTrue(csv.contains("\"Meeting, \"\"urgent\"\"\nwith legal\""), csv)
        let header = csv.components(separatedBy: "\r\n")[0]
        XCTAssertEqual(header.components(separatedBy: "\",\"").count, CSVExporter.columnCount)
    }

    func testCSVNumbersUseADotWhateverTheLocale() {
        let data = ReportBuilder.build(trips: [trip(date(2026, 9, 1), km: 24.3, amount: "15.73")], period: .month(year: 2026, month: 9), calendar: calendar)
        var frenchProfile = profile
        frenchProfile = ReportProfile(
            userName: profile.userName, companyName: profile.companyName, vehicleLabel: profile.vehicleLabel,
            countryCode: "FR", countryName: "France", ruleDescription: profile.ruleDescription,
            ruleVersion: profile.ruleVersion, ruleSourceURL: profile.ruleSourceURL, isOfficialRate: true,
            unit: .kilometers, locale: Locale(identifier: "fr_FR")
        )
        let csv = CSVExporter.csv(data, profile: frenchProfile)
        XCTAssertTrue(csv.contains("\"24.3\""), csv)
        XCTAssertTrue(csv.contains("\"15.73\""), csv)
        XCTAssertFalse(csv.contains("\"24,3\""), "a machine-readable CSV must not carry a locale decimal comma")
    }

    func testCSVFileStartsWithAUTF8BOM() throws {
        let data = ReportBuilder.build(trips: [trip(date(2026, 9, 1), km: 10)], period: .month(year: 2026, month: 9), calendar: calendar)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).csv")
        try CSVExporter.write(CSVExporter.csv(data, profile: profile), to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let bytes = try Data(contentsOf: url).prefix(3)
        XCTAssertEqual(Array(bytes), [0xEF, 0xBB, 0xBF])
    }

    func testCSVCarriesATotalsRow() {
        let data = ReportBuilder.build(
            trips: [trip(date(2026, 9, 1), km: 10), trip(date(2026, 9, 2), km: 15)],
            period: .month(year: 2026, month: 9),
            calendar: calendar
        )
        let lines = CSVExporter.csv(data, profile: profile).components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 4, "header + 2 trips + total")
        XCTAssertTrue(lines.last!.hasPrefix("\"TOTAL\""), lines.last!)
        XCTAssertTrue(lines.last!.contains("\"20.00\""), lines.last!)
    }

    // MARK: - PDF

    private func renderPDF(_ data: ReportData) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString).pdf")
        _ = try PDFReportRenderer().render(data, profile: profile, to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(PDFDocument(url: url))
    }

    func testPDFOpensAndCarriesTheHeader() throws {
        let data = ReportBuilder.build(trips: [trip(date(2026, 9, 1), km: 24.3)], period: .month(year: 2026, month: 9), calendar: calendar)
        let document = try renderPDF(data)
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let text = try XCTUnwrap(document.page(at: 0)?.string)
        XCTAssertTrue(text.contains("MILEAGE REPORT"), text)
        XCTAssertTrue(text.contains("September 2026"), text)
        XCTAssertTrue(text.contains("Jane Doe"), text)
    }

    /// Proves the pagination actually splits: 120 rows cannot fit on two A4 pages at this
    /// row height, so a single-page document would mean rows were silently dropped.
    func testPDFPaginatesLongReports() throws {
        let trips = (0..<120).map { index in
            trip(date(2026, 9, 1 + index % 28, 8 + index % 10), km: Double(10 + index % 40))
        }
        let data = ReportBuilder.build(trips: trips, period: .month(year: 2026, month: 9), calendar: calendar)
        XCTAssertEqual(data.rows.count, 120)

        let document = try renderPDF(data)
        XCTAssertGreaterThanOrEqual(document.pageCount, 3, "120 rows must not claim to fit on two pages")
    }

    func testPDFLastPageCarriesTheDisclaimerAndTheRuleSource() throws {
        let trips = (0..<40).map { index in trip(date(2026, 9, 1 + index % 28), km: 12) }
        let data = ReportBuilder.build(trips: trips, period: .month(year: 2026, month: 9), calendar: calendar)
        let document = try renderPDF(data)
        let lastPage = try XCTUnwrap(document.page(at: document.pageCount - 1)?.string)

        XCTAssertTrue(lastPage.contains("Verify eligibility according to your local tax regulations"), lastPage)
        XCTAssertTrue(lastPage.contains("not a certified tax statement"), lastPage)
        XCTAssertTrue(lastPage.contains("impots.gouv.fr"), lastPage)
        XCTAssertTrue(lastPage.contains("2026.1"), lastPage)
    }

    func testPDFFlagsWhenSeveralRuleVersionsApplyInsideOnePeriod() throws {
        let trips = [
            trip(date(2026, 1, 5), km: 10, version: "2025.1"),
            trip(date(2026, 6, 5), km: 10, version: "2026.1"),
        ]
        let data = ReportBuilder.build(trips: trips, period: .year(2026), calendar: calendar)
        XCTAssertEqual(data.ruleVersions, ["2025.1", "2026.1"])

        let document = try renderPDF(data)
        let lastPage = try XCTUnwrap(document.page(at: document.pageCount - 1)?.string)
        XCTAssertTrue(lastPage.contains("more than one rule version"), lastPage)
    }

    func testPDFIsStillProducedForAnEmptyPeriod() throws {
        let data = ReportBuilder.build(trips: [], period: .month(year: 2026, month: 9), calendar: calendar)
        XCTAssertTrue(data.isEmpty)
        let document = try renderPDF(data)
        XCTAssertEqual(document.pageCount, 1)
        let text = try XCTUnwrap(document.page(at: 0)?.string)
        XCTAssertTrue(text.contains("No business trips recorded"), text)
    }
}
