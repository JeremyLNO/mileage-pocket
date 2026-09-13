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
    func testAnEarlierClockDoesNotExtendThePeriod() {
        let period = FreeAccessPeriod(startedAt: start)
        XCTAssertTrue(period.isActive(now: start.addingTimeInterval(-86_400)))
        XCTAssertLessThanOrEqual(period.daysRemaining(now: start.addingTimeInterval(-86_400)), 4)
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
