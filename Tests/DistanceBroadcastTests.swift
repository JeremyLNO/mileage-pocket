import XCTest
@testable import MileagePocket

/// The schedule every screen now shares.
///
/// The defect it exists for was visible in one photograph: at the same second, the phone in
/// the cradle read **1.6 km** and the CarPlay dashboard read **1.5 km**. Two surfaces, two
/// clocks, one drive — and no way for the driver to know which to believe.
@MainActor
final class DistanceBroadcastTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func started() -> DistanceBroadcast {
        var broadcast = DistanceBroadcast()
        broadcast.begin(at: epoch)
        return broadcast
    }

    func testATripOpensAtZeroStraightAway() {
        let broadcast = started()
        XCTAssertEqual(broadcast.publishedMeters, 0)
        XCTAssertEqual(broadcast.publishedAt, epoch, "a screen blank for the first five seconds reads as a tracker that never started")
    }

    /// On the second, not after it. Thresholds are wrong at the boundary first.
    func testFiveSecondsExactlyPublishes() {
        var broadcast = started()
        XCTAssertFalse(broadcast.consider(20, now: epoch.addingTimeInterval(4.99)))
        XCTAssertEqual(broadcast.publishedMeters, 0)

        XCTAssertTrue(broadcast.consider(20, now: epoch.addingTimeInterval(5)))
        XCTAssertEqual(broadcast.publishedMeters, 20)
    }

    /// A hundred metres arrives first on a motorway: at 130 km/h it takes under three
    /// seconds, and a figure three seconds stale is a figure a passenger can catch out.
    func testAHundredMetresPublishesBeforeTheFiveSecondsAreUp() {
        var broadcast = started()
        XCTAssertFalse(broadcast.consider(99.9, now: epoch.addingTimeInterval(1)))
        XCTAssertTrue(broadcast.consider(100, now: epoch.addingTimeInterval(1)))
        XCTAssertEqual(broadcast.publishedMeters, 100)
    }

    func testNeitherThresholdMetChangesNothing() {
        var broadcast = started()
        XCTAssertFalse(broadcast.consider(40, now: epoch.addingTimeInterval(3)))
        XCTAssertEqual(broadcast.publishedMeters, 0, "the number on screen must not move on its own")
    }

    /// A car at a red light publishes nothing — there is nothing to publish — and the very
    /// first metre after it moves off appears at once, because the clock kept running.
    func testAStandingCarPublishesNothingAndMovesAgainImmediately() {
        var broadcast = started()
        XCTAssertTrue(broadcast.consider(500, now: epoch.addingTimeInterval(30)))

        XCTAssertFalse(broadcast.consider(500, now: epoch.addingTimeInterval(120)), "no movement, no update")
        XCTAssertTrue(broadcast.consider(501, now: epoch.addingTimeInterval(121)))
        XCTAssertEqual(broadcast.publishedMeters, 501)
    }

    /// The end of a drive does not wait for a schedule: the summary sheet shows the figure
    /// that was written to the trip, to the metre.
    func testSettlingIgnoresTheSchedule() {
        var broadcast = started()
        broadcast.settle(on: 2_437, now: epoch.addingTimeInterval(0.2))
        XCTAssertEqual(broadcast.publishedMeters, 2_437)
    }

    /// The rule on its own, at both boundaries and on the wrong side of each.
    func testTheRuleItself() {
        XCTAssertTrue(DistanceBroadcast.shouldPublish(current: 0, published: 0, since: 5))
        XCTAssertFalse(DistanceBroadcast.shouldPublish(current: 0, published: 0, since: 4.999))
        XCTAssertTrue(DistanceBroadcast.shouldPublish(current: 100, published: 0, since: 0))
        XCTAssertFalse(DistanceBroadcast.shouldPublish(current: 99.999, published: 0, since: 0))
        // Symmetric on purpose: a distance can only grow today, but a rule that assumes it
        // is a rule that breaks silently the day a correction moves it back.
        XCTAssertTrue(DistanceBroadcast.shouldPublish(current: 0, published: 100, since: 0))
    }
}
