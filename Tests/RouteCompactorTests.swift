import XCTest
@testable import MileagePocket

/// The route is kept only to draw a line on a map, but it is kept *in the user's CloudKit
/// database*, so it has to be small — and it still has to look like the road that was driven.
final class RouteCompactorTests: XCTestCase {

    func testStraightLineCollapsesToItsEndpoints() {
        let line = RouteFixtures.straightLine(pointCount: 100, stepMeters: 10)
        let simplified = RouteCompactor.simplify(line, toleranceMeters: 5)

        XCTAssertLessThanOrEqual(
            simplified.count, 2,
            "100 collinear fixes carry exactly two points of information"
        )
        XCTAssertEqual(simplified.first, line.first)
        XCTAssertEqual(simplified.last, line.last)
    }

    func testASharpTurnSurvivesSimplification() {
        // 500 m north, then 500 m east: the corner is the whole shape of this route.
        let north = RouteFixtures.straightLine(
            pointCount: 51, stepMeters: 10, bearingDegrees: 0, speedMetersPerSecond: 10
        )
        let corner = north[north.count - 1]
        var east: [LocationSample] = []
        for step in 1...50 {
            let point = RouteFixtures.offset(
                latitude: corner.latitude, longitude: corner.longitude,
                eastMeters: Double(step) * 10, northMeters: 0
            )
            east.append(LocationSample(
                latitude: point.latitude, longitude: point.longitude,
                horizontalAccuracy: 5, altitude: 35, speed: 10,
                timestamp: corner.timestamp.addingTimeInterval(Double(step))
            ))
        }

        let simplified = RouteCompactor.simplify(north + east, toleranceMeters: 5)

        XCTAssertEqual(simplified.count, 3, "start, corner, end — nothing more is needed")
        let keptCorner = simplified.contains { sample in
            Geodesy.distance(from: sample, to: corner) < 1
        }
        XCTAssertTrue(keptCorner, "dropping the corner would redraw the route through buildings")
    }

    func testEncodeDecodeRoundTrip() {
        let (route, _) = RouteFixtures.parisToVersailles()
        let simplified = RouteCompactor.simplify(route, toleranceMeters: 10)
        XCTAssertGreaterThan(simplified.count, 5)

        let decoded = RouteCompactor.decode(RouteCompactor.encode(simplified))

        XCTAssertEqual(decoded.count, simplified.count)
        for (original, restored) in zip(simplified, decoded) {
            XCTAssertEqual(restored.latitude, original.latitude, accuracy: 1e-5)
            XCTAssertEqual(restored.longitude, original.longitude, accuracy: 1e-5)
            XCTAssertEqual(
                restored.timestamp.timeIntervalSinceReferenceDate,
                original.timestamp.timeIntervalSinceReferenceDate,
                accuracy: 0.001,
                "timestamps are stored to the millisecond — finer than any GPS fix needs"
            )
        }
    }

    func testDecodingGarbageYieldsNothingRatherThanCrashing() {
        XCTAssertEqual(RouteCompactor.decode(Data()), [])
        XCTAssertEqual(RouteCompactor.decode(Data([0xFF, 0x02, 0x03])), [])
    }

    func testSevenHundredAndTwentyPointsFitInSixKilobytes() {
        let route = RouteFixtures.straightLine(
            pointCount: 720, stepMeters: 20, speedMetersPerSecond: 20
        )
        let encoded = RouteCompactor.encode(route)

        XCTAssertEqual(RouteCompactor.decode(encoded).count, 720)
        XCTAssertLessThan(
            encoded.count, 6 * 1024,
            "a route blob rides in every trip record and syncs to iCloud; \(encoded.count) bytes"
        )
    }
}
