import CoreLocation
import SwiftData
import XCTest
@testable import MileagePocket

final class FrequentLocationTests: XCTestCase {
    // Place de la Concorde, Paris.
    private let baseLatitude = 48.8656
    private let baseLongitude = 2.3212

    /// Offsets a coordinate due north so that `Geodesy.distance` — the function the matcher
    /// actually uses — measures exactly `meters` from the base point.
    ///
    /// Dividing by `metersPerDegreeLatitude` is not the same metre: that constant is built on
    /// the WGS84 *equatorial* radius while `distance` is a haversine on the *mean* radius, so
    /// a requested 150 m measured 149.83 m. The boundary test was probing 149.83 and 150.83 —
    /// never the bound — and a radius that drifted by ±0.8 m, or an inclusive `<=` turned
    /// into `<`, left it green. Solving for the offset removes the discrepancy entirely.
    private func north(_ meters: Double) -> Double {
        let approximate = baseLatitude + meters / Geodesy.metersPerDegreeLatitude
        guard meters > 0 else { return approximate }
        let measured = Geodesy.distance(
            fromLatitude: baseLatitude, longitude: baseLongitude,
            toLatitude: approximate, longitude: baseLongitude
        )
        guard measured > 0 else { return approximate }
        return baseLatitude + (approximate - baseLatitude) * (meters / measured)
    }

    private func place(_ latitude: Double, label: String) -> FrequentLocation {
        let location = FrequentLocation(latitude: latitude, longitude: baseLongitude)
        location.label = label
        return location
    }

    func testAPointWellInsideTheRadiusMatches() {
        let known = [place(baseLatitude, label: "Client ABC")]
        let match = FrequentLocationMatcher.match(latitude: north(80), longitude: baseLongitude, in: known)
        XCTAssertEqual(match?.label, "Client ABC")
    }

    func testAPointWellOutsideTheRadiusDoesNotMatch() {
        let known = [place(baseLatitude, label: "Client ABC")]
        XCTAssertNil(FrequentLocationMatcher.match(latitude: north(200), longitude: baseLongitude, in: known))
    }

    /// The boundary to within a millimetre, measured in the same metre the matcher uses.
    ///
    /// It used to probe 149.83 m and 150.83 m: the fixture offset by the WGS84 *equatorial*
    /// radius while `Geodesy.distance` measures on the *mean* one, so neither side was near
    /// the bound and the radius could drift ±0.8 m — or 150 could stop being included — with
    /// nothing turning red. `north` now solves for the offset, so these two points sit one
    /// millimetre either side of 150 m.
    ///
    /// A millimetre, not zero: `<=` and `<` differ only at a distance that is exactly 150.0 in
    /// binary floating point, which no coordinate reliably produces. What is testable — and
    /// what actually protects the feature — is that the radius is 150 m and not 149.9 or
    /// 150.5.
    func testTheRadiusBoundaryIsInclusive() {
        let known = [place(baseLatitude, label: "Client ABC")]
        XCTAssertNotNil(FrequentLocationMatcher.match(latitude: north(149.999), longitude: baseLongitude, in: known))
        XCTAssertNil(FrequentLocationMatcher.match(latitude: north(150.001), longitude: baseLongitude, in: known))
    }

    func testTheNearestKnownPlaceWinsWhenTwoAreInRange() {
        let known = [
            place(north(140), label: "Far"),
            place(north(20), label: "Near"),
        ]
        let match = FrequentLocationMatcher.match(latitude: baseLatitude, longitude: baseLongitude, in: known)
        XCTAssertEqual(match?.label, "Near")
    }

    func testNoKnownPlacesMeansNoSuggestion() {
        XCTAssertNil(FrequentLocationMatcher.match(latitude: baseLatitude, longitude: baseLongitude, in: []))
    }

    /// Counting was tested on `+=`, which is Swift's, not the app's. The line that matters is
    /// in `learnDestination`, reached from `finishTrip` — and nothing exercised it, so
    /// deleting the whole of destination learning left the suite green.
    @MainActor
    func testFinishingTripsToTheSamePlaceAccumulatesVisits() throws {
        let dependencies = try makeDependencies()

        for index in 0..<3 {
            let trip = Trip(startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400))
            trip.endedAt = trip.startedAt.addingTimeInterval(900)
            trip.rawDistanceMeters = 12_000
            // Each drive ends a few metres from the last — the same car park, not the same
            // pixel, which is the case the matcher exists for.
            trip.endLatitude = north(Double(index) * 20)
            trip.endLongitude = baseLongitude
            trip.endAddress = "Client ABC"
            dependencies.context.insert(trip)
            dependencies.finishTrip(trip)
        }

        let learned = try dependencies.context.fetch(FetchDescriptor<FrequentLocation>())
        XCTAssertEqual(learned.count, 1, "three drives to one place must learn one place")
        XCTAssertEqual(learned.first?.visitCount, 3, "every arrival has to count")
    }

    /// A drive that ends somewhere else is a different place, not another visit.
    @MainActor
    func testFinishingATripFarAwayLearnsASecondPlace() throws {
        let dependencies = try makeDependencies()

        for latitude in [baseLatitude, north(4_000)] {
            let trip = Trip(startedAt: Date(timeIntervalSince1970: 1_700_000_000))
            trip.endedAt = trip.startedAt.addingTimeInterval(900)
            trip.rawDistanceMeters = 12_000
            trip.endLatitude = latitude
            trip.endLongitude = baseLongitude
            dependencies.context.insert(trip)
            dependencies.finishTrip(trip)
        }

        XCTAssertEqual(try dependencies.context.fetch(FetchDescriptor<FrequentLocation>()).count, 2)
    }

    @MainActor
    private func makeDependencies() throws -> AppDependencies {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        return AppDependencies(container: container, recorderFactory: { _ in InertRecorder() })
    }
}
