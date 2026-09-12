import XCTest
@testable import MileagePocket

final class FrequentLocationTests: XCTestCase {
    // Place de la Concorde, Paris.
    private let baseLatitude = 48.8656
    private let baseLongitude = 2.3212

    /// Offsets a coordinate due north by a known number of metres.
    private func north(_ meters: Double) -> Double {
        baseLatitude + meters / Geodesy.metersPerDegreeLatitude
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

    /// The boundary itself, not "around" it: 150 m is inside, a metre further is not.
    func testTheRadiusBoundaryIsInclusive() {
        let known = [place(baseLatitude, label: "Client ABC")]
        XCTAssertNotNil(FrequentLocationMatcher.match(latitude: north(150), longitude: baseLongitude, in: known))
        XCTAssertNil(FrequentLocationMatcher.match(latitude: north(151), longitude: baseLongitude, in: known))
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

    func testVisitCountingAccumulatesOnRepeatVisits() {
        let location = place(baseLatitude, label: "Client ABC")
        XCTAssertEqual(location.visitCount, 1)
        location.visitCount += 1
        location.visitCount += 1
        XCTAssertEqual(location.visitCount, 3)
    }
}
