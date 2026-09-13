import XCTest
@testable import MileagePocket

/// How a trip is named. The rule is a product decision, so it is pinned here rather than
/// left to whichever view formats it first.
final class TripEndpointLabelTests: XCTestCase {
    private let paris = PlaceLabel(street: "12 Avenue Gambetta", town: "Paris")
    private let versailles = PlaceLabel(street: "4 Rue Ségoffin", town: "Versailles")
    private let parisElsewhere = PlaceLabel(street: "8 Rue de Belfort", town: "Paris")

    func testDifferentTownsAreNamedByTheirTowns() {
        let labels = TripEndpointLabel.format(start: paris, end: versailles, distanceMeters: 24_300)
        XCTAssertEqual(labels.start, "Paris")
        XCTAssertEqual(labels.end, "Versailles")
    }

    /// The case that prompted this: a local round of visits was labelled "Paris → Paris",
    /// which distinguishes nothing from any other trip that day.
    func testTheSameTownAtBothEndsIsNamedByTheStreets() {
        let labels = TripEndpointLabel.format(start: paris, end: parisElsewhere, distanceMeters: 1_900)
        XCTAssertEqual(labels.start, "12 Avenue Gambetta")
        XCTAssertEqual(labels.end, "8 Rue de Belfort")
    }

    /// A long drive that happens to end in the town it started from is a loop, not a local
    /// errand: at that scale the street is noise.
    func testALongTripKeepsTheTownEvenWhenBothEndsShareIt() {
        let labels = TripEndpointLabel.format(start: paris, end: parisElsewhere, distanceMeters: 120_000)
        XCTAssertEqual(labels.start, "Paris")
        XCTAssertEqual(labels.end, "Paris")
    }

    /// Tested on the bound itself.
    func testTheLongTripThresholdIsTestedOnTheBound() {
        let justUnder = TripEndpointLabel.format(
            start: paris, end: parisElsewhere,
            distanceMeters: TripEndpointLabel.longTripThresholdMeters - 1
        )
        XCTAssertEqual(justUnder.start, "12 Avenue Gambetta", "just under the bound is still local")

        let onTheBound = TripEndpointLabel.format(
            start: paris, end: parisElsewhere,
            distanceMeters: TripEndpointLabel.longTripThresholdMeters
        )
        XCTAssertEqual(onTheBound.start, "Paris", "on the bound it counts as long")
    }

    func testAStreetIsUsedWhenNoTownIsKnown() {
        let motorway = PlaceLabel(street: "A6", town: nil)
        let labels = TripEndpointLabel.format(start: motorway, end: versailles, distanceMeters: 80_000)
        XCTAssertEqual(labels.start, "A6")
        XCTAssertEqual(labels.end, "Versailles")
    }

    func testNothingKnownFallsBackToADash() {
        let labels = TripEndpointLabel.format(
            start: PlaceLabel(street: nil, town: nil),
            end: PlaceLabel(street: nil, town: nil),
            distanceMeters: 5_000
        )
        XCTAssertEqual(labels.start, "—")
        XCTAssertEqual(labels.end, "—")
    }

    /// One end known and the other not must not drag the known one down to a dash.
    func testOneEndMissingLeavesTheOtherIntact() {
        let labels = TripEndpointLabel.format(
            start: paris,
            end: PlaceLabel(street: nil, town: nil),
            distanceMeters: 5_000
        )
        XCTAssertEqual(labels.start, "Paris")
        XCTAssertEqual(labels.end, "—")
    }
}
