import CoreLocation
import XCTest
@testable import MileagePocket

/// The rule the whole paywall rests on, tested as a pure function: every feature against
/// every access state, and the period boundary on the boundary itself.
final class AccessPolicyTests: XCTestCase {
    private let subscribed = Entitlement.subscribed(productID: ProductIDs.annual, expires: nil)
    private let none = Entitlement.none

    // MARK: - During the free period

    func testTheAppWorksNormallyDuringTheFreePeriod() {
        for feature in [PremiumFeature.startTrip, .manualTrip, .multipleVehicles] {
            XCTAssertTrue(
                AccessPolicy.allows(feature, entitlement: none, freePeriodActive: true),
                "\(feature) must work during the free period"
            )
        }
    }

    /// Exporting is what is being sold, so it is the one thing the free period does not open.
    func testExportIsNeverFreeEvenDuringTheFreePeriod() {
        XCTAssertFalse(AccessPolicy.allows(.exportReport, entitlement: none, freePeriodActive: true))
    }

    // MARK: - After it

    func testEverythingIsGatedOnceTheFreePeriodIsOver() {
        for feature in PremiumFeature.allCases {
            XCTAssertFalse(
                AccessPolicy.allows(feature, entitlement: none, freePeriodActive: false),
                "\(feature) must be gated after the free period"
            )
        }
    }

    func testASubscriptionOpensEverythingWhicheverWayItWasObtained() {
        for entitlement: Entitlement in [
            .subscribed(productID: ProductIDs.monthly, expires: nil),
            .trial(productID: ProductIDs.monthly, expires: .now),
            .gracePeriod(productID: ProductIDs.annual, expires: .now),
        ] {
            for feature in PremiumFeature.allCases {
                XCTAssertTrue(
                    AccessPolicy.allows(feature, entitlement: entitlement, freePeriodActive: false),
                    "\(feature) must be open with \(entitlement)"
                )
            }
        }
    }

    // MARK: - The period itself

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheFreePeriodLastsExactlyThreeDays() {
        let period = FreeAccessPeriod(startedAt: start)
        XCTAssertEqual(period.endsAt.timeIntervalSince(start), 3 * 24 * 3600)
    }

    /// Tested on the bound: the last instant inside is free, the instant it ends is not.
    func testTheBoundaryIsTestedOnTheBoundary() {
        let period = FreeAccessPeriod(startedAt: start)
        let end = start.addingTimeInterval(FreeAccessPeriod.duration)

        XCTAssertTrue(period.isActive(now: start))
        XCTAssertTrue(period.isActive(now: end.addingTimeInterval(-1)))
        XCTAssertFalse(period.isActive(now: end), "the instant it ends, it is over")
        XCTAssertFalse(period.isActive(now: end.addingTimeInterval(1)))
    }

    func testDaysRemainingCountsTheLastPartialDayAsOne() {
        let period = FreeAccessPeriod(startedAt: start)
        XCTAssertEqual(period.daysRemaining(now: start), 3)
        XCTAssertEqual(period.daysRemaining(now: start.addingTimeInterval(24 * 3600)), 2)
        XCTAssertEqual(period.daysRemaining(now: start.addingTimeInterval(2 * 24 * 3600 + 60)), 1)
        // Ten minutes left is still a day to show, not zero.
        XCTAssertEqual(period.daysRemaining(now: period.endsAt.addingTimeInterval(-600)), 1)
        XCTAssertEqual(period.daysRemaining(now: period.endsAt), 0)
    }

    /// A clock that has been moved backwards must not extend the period beyond its length.
    ///
    /// The old assertion was `<= 4`, which is exactly what the unclamped subtraction returns
    /// for a day of backdating: it asserted the absence of the rule it named. A year of
    /// backdating would have read 368 days and passed just as well.
    func testAnEarlierClockDoesNotExtendThePeriod() {
        let period = FreeAccessPeriod(startedAt: start)
        for backwards in [86_400.0, 30 * 86_400.0, 365 * 86_400.0] {
            let now = start.addingTimeInterval(-backwards)
            XCTAssertTrue(period.isActive(now: now))
            XCTAssertEqual(
                period.daysRemaining(now: now), 3,
                "winding the clock back \(Int(backwards / 86_400)) days must not buy a fourth free day"
            )
        }
    }
}

/// The install date has to outlive the app, or deleting and reinstalling hands out a fresh
/// free period on demand.
final class InstallDateStoreTests: XCTestCase {
    private var saved: Date?

    override func setUp() {
        super.setUp()
        // The keychain item outlives the app, so it outlives this test too: whatever the
        // simulator held is put back afterwards, or the UI tests that run next inherit a
        // free period that this suite silently rewrote.
        saved = InstallDateStore.read()
        InstallDateStore.clear()
    }

    override func tearDown() {
        InstallDateStore.clear()
        if let saved { InstallDateStore.write(saved) }
        super.tearDown()
    }

    func testFirstCallRecordsTheDateAndLaterCallsReturnTheSameOne() {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let recorded = InstallDateStore.firstLaunchDate(now: first)
        XCTAssertEqual(recorded.timeIntervalSince1970, first.timeIntervalSince1970, accuracy: 1)

        // A later launch must not move it — that is the whole point.
        let later = first.addingTimeInterval(10 * 86_400)
        let second = InstallDateStore.firstLaunchDate(now: later)
        XCTAssertEqual(second.timeIntervalSince1970, first.timeIntervalSince1970, accuracy: 1)
    }

    func testTheDateIsReadBackFromTheKeychainNotFromMemory() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        InstallDateStore.write(date)
        let read = try XCTUnwrap(InstallDateStore.read())
        XCTAssertEqual(read.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1)
    }

    func testNothingIsReportedBeforeAnythingIsWritten() {
        XCTAssertNil(InstallDateStore.read())
    }
}

/// The two paths that handed premium away, and the archive that must stay free.
@MainActor
final class AccessLeakTests: XCTestCase {

    private func makeDependencies() throws -> AppDependencies {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        return AppDependencies(container: container, recorderFactory: { _ in InertRecorder() })
    }

    /// Duplicating creates a trip, so it is the same permission as creating one. Leaving it
    /// open made "record trips" free to anyone willing to press a button twice.
    func testDuplicatingIsGatedLikeCreating() throws {
        let dependencies = try makeDependencies()
        XCTAssertEqual(
            AccessPolicy.allows(.manualTrip, entitlement: .none, freePeriodActive: false),
            dependencies.canAccess(.manualTrip, now: dependencies.freePeriod.endsAt),
            "duplicating must answer to the same rule as manual entry"
        )
    }

    /// The archive exists so a person can leave with what they recorded. It must not be the
    /// paid report by another name — it used to be exactly that, personal trips included.
    func testTheFreeArchiveIsNotTheReport() throws {
        let dependencies = try makeDependencies()
        dependencies.createManualTrip(
            date: Date(timeIntervalSince1970: 1_800_000_000), from: "A", to: "B",
            distanceMeters: 10_000, tripType: .business, purpose: "Visit",
            clientName: "", vehicleID: nil
        )

        let url = try XCTUnwrap(dependencies.exportAllData())
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertEqual(url.pathExtension, "json", "the archive is data, not a formatted report")
        XCTAssertTrue(contents.contains("\"trips\""))
        XCTAssertTrue(contents.contains("\"distanceMeters\""))
        // None of what makes the report worth paying for.
        XCTAssertFalse(contents.contains("TOTAL"), "no totals")
        XCTAssertFalse(contents.contains("business trips"), "no report summary")
        XCTAssertFalse(contents.contains("Verify eligibility"), "no rule provenance")
    }

    func testTheArchiveStaysAvailableWithoutASubscription() throws {
        let dependencies = try makeDependencies()
        XCTAssertFalse(
            dependencies.canAccess(.exportReport, now: dependencies.freePeriod.endsAt),
            "the paid export stays gated"
        )
        XCTAssertNotNil(dependencies.exportAllData(), "the archive must not depend on paying")
    }
}
