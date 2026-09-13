import CoreLocation
import SwiftData
import XCTest
@testable import MileagePocket

/// The wiring layer, which had no tests at all — and which is where every money defect this
/// app has had actually lived. The engine was proved; nothing proved it was plugged in.
@MainActor
final class CumulativeYearTests: XCTestCase {
    /// Stands in for the recorder: these tests never record, they only write trips.
    private final class InertRecorder: TripRecording {
        var state: RecorderState = .idle
        var onUpdate: (() -> Void)?
        var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
        var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
        var currentDistanceMeters: Double = 0
        var startedAt: Date?
        var routeSamples: [LocationSample] = []

        func start(vehicleID: UUID?) throws {}
        func stop() async throws -> Trip { throw RecorderError.notRecording }
        func resumeIfNeeded() throws {}
        func requestPermission() {}
    }

    private func makeDependencies(country: String) throws -> AppDependencies {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let dependencies = AppDependencies(container: container, recorderFactory: { _ in InertRecorder() })
        dependencies.settingsStore.applyCountry(country)
        dependencies.settingsStore.settings.rateMode = .official
        dependencies.settingsStore.save()
        return dependencies
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
    }

    private func addTrip(_ dependencies: AppDependencies, on day: Date, miles: Double) {
        dependencies.createManualTrip(
            date: day, from: "A", to: "B",
            distanceMeters: DistanceUnit.miles.meters(fromValue: miles),
            tripType: .business, purpose: "", clientName: "", vehicleID: nil
        )
    }

    private func trips(_ dependencies: AppDependencies) -> [Trip] {
        (try? dependencies.context.fetch(
            FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt)])
        )) ?? []
    }

    /// The British scale charges the first 10 000 miles of the year at one rate and the rest
    /// at another. Where a trip sits in the year therefore decides what it is worth.
    func testABackdatedTripRepricesTheRestOfTheYear() throws {
        let dependencies = try makeDependencies(country: "GB")

        addTrip(dependencies, on: date(2026, 6, 1), miles: 9_900)
        addTrip(dependencies, on: date(2026, 7, 1), miles: 200)

        let before = trips(dependencies)
        XCTAssertEqual(before.count, 2)
        // 100 miles under the threshold at 0.55, 100 over it at 0.25.
        XCTAssertEqual(before[1].calculatedAmount, Decimal(string: "80.00"))

        // A forgotten May trip, entered in July. May is inside the British window, which
        // opens on 6 April — a January date would be testing something else entirely.
        addTrip(dependencies, on: date(2026, 5, 2), miles: 200)

        let after = trips(dependencies)
        XCTAssertEqual(after.count, 3)
        XCTAssertEqual(after[0].calculatedAmount, Decimal(string: "110.00"), "the backdated trip itself")
        // The June trip now starts at mile 200 and crosses the threshold inside itself.
        XCTAssertEqual(after[1].calculatedAmount, Decimal(string: "5415.00"))
        // The July trip is now entirely above the threshold.
        XCTAssertEqual(
            after[2].calculatedAmount, Decimal(string: "50.00"),
            "a trip that used to straddle the threshold must be repriced once the year shifts"
        )
    }

    func testDeletingATripRepricesTheRestOfTheYear() throws {
        let dependencies = try makeDependencies(country: "GB")
        addTrip(dependencies, on: date(2026, 5, 2), miles: 200)
        addTrip(dependencies, on: date(2026, 6, 1), miles: 9_900)
        addTrip(dependencies, on: date(2026, 7, 1), miles: 200)

        let earliest = trips(dependencies)[0]
        dependencies.delete(earliest)

        let after = trips(dependencies)
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after[0].calculatedAmount, Decimal(string: "5445.00"))
        XCTAssertEqual(
            after[1].calculatedAmount, Decimal(string: "80.00"),
            "removing an earlier trip must move the later ones back down the bands"
        )
    }

    /// The freeze still holds: correcting a cumulative total must not move a trip onto a
    /// different version of the scale.
    func testTheFrozenRuleVersionSurvivesTheRecalculation() throws {
        let dependencies = try makeDependencies(country: "GB")
        addTrip(dependencies, on: date(2026, 6, 1), miles: 100)
        let version = trips(dependencies)[0].mileageRuleVersion
        XCTAssertNotNil(version)

        addTrip(dependencies, on: date(2026, 5, 2), miles: 50)
        XCTAssertEqual(trips(dependencies)[1].mileageRuleVersion, version)
    }

    /// A flat rate owes nothing to the year: adding a trip must leave the others untouched,
    /// and the replay must not run at all.
    func testAFlatRateCountryIsUnaffectedByOrder() throws {
        let dependencies = try makeDependencies(country: "DE")
        addTrip(dependencies, on: date(2026, 6, 1), miles: 100)
        let before = trips(dependencies)[0].calculatedAmount

        addTrip(dependencies, on: date(2026, 5, 2), miles: 5_000)

        XCTAssertEqual(trips(dependencies)[1].calculatedAmount, before)
    }

    /// Personal trips consume no allowance and must not shift the business ones.
    func testAPersonalTripDoesNotConsumeTheAllowance() throws {
        let dependencies = try makeDependencies(country: "GB")
        addTrip(dependencies, on: date(2026, 6, 1), miles: 100)
        let businessAmount = trips(dependencies)[0].calculatedAmount

        dependencies.createManualTrip(
            date: date(2026, 5, 2), from: "A", to: "B",
            distanceMeters: DistanceUnit.miles.meters(fromValue: 12_000),
            tripType: .personal, purpose: "", clientName: "", vehicleID: nil
        )

        let business = trips(dependencies).first { $0.tripType == .business }
        XCTAssertEqual(business?.calculatedAmount, businessAmount)
    }

    /// A different tax year is a different allowance.
    func testAnotherYearIsLeftAlone() throws {
        let dependencies = try makeDependencies(country: "GB")
        addTrip(dependencies, on: date(2025, 6, 1), miles: 9_900)
        addTrip(dependencies, on: date(2026, 6, 1), miles: 200)
        let amount2026 = trips(dependencies)[1].calculatedAmount

        addTrip(dependencies, on: date(2025, 1, 15), miles: 200)

        XCTAssertEqual(trips(dependencies).last?.calculatedAmount, amount2026)
    }
}
